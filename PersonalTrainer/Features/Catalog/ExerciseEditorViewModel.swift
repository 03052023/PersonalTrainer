import Foundation
import Observation
import os
import TrainerCore

/// Estado do editor de exercício (SPEC RF-15; TASKS T2.5). Cria exercícios do usuário e edita
/// qualquer exercício do catálogo, sempre pelo `CatalogRepositoring` (AGENTS R4): nada aqui toca o
/// `ModelContext`.
@Observable
@MainActor
final class ExerciseEditorViewModel {
    enum Mode: Equatable {
        case create
        case edit(UUID)
    }

    /// Opções do incremento mínimo de carga (SPEC §7.1: 2,5 kg barra/halter; 5 kg máquina de
    /// placas; 1 nível/placa). "Personalizado" aceita qualquer valor finito > 0 (P8).
    enum IncrementChoice: String, CaseIterable, Hashable {
        case twoAndHalf
        case five
        case one
        case custom

        var label: String {
            switch self {
            case .twoAndHalf: return "2,5"
            case .five: return "5"
            case .one: return "1"
            case .custom: return "Personalizado"
            }
        }

        /// Valor fixo da opção; `nil` para `.custom` (vem do campo de texto).
        var value: Double? {
            switch self {
            case .twoAndHalf: return 2.5
            case .five: return 5
            case .one: return 1
            case .custom: return nil
            }
        }
    }

    let mode: Mode
    /// Campos editados. Nome, equipamento, unidade, unilateral e padrão de movimento vão direto por
    /// binding; músculos, incremento e notas passam pelos métodos/propriedades abaixo.
    var draft: ExerciseDraft
    /// Mensagem pt-BR para o `.alert` da view; a view zera ao fechar o alerta.
    var errorMessage: String?
    /// Id gravado pelo último `saveExercise()` bem-sucedido.
    private(set) var savedExerciseID: UUID?
    /// `true` para exercícios do seed em modo edição: a view avisa que uma atualização do catálogo
    /// padrão pode restaurar nome e músculos (o seed v2 só preserva notas e arquivamento).
    let isSeedExercise: Bool

    private var storedIncrementChoice: IncrementChoice
    private var storedCustomIncrementText: String
    /// Rascunho como abriu (ou como foi gravado por último), para `hasUnsavedChanges`.
    private var originalDraft: ExerciseDraft
    private let catalog: any CatalogRepositoring

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Catalog"
    )

    /// - Parameter exercise: `nil` cria um exercício novo; senão edita este.
    init(catalog: any CatalogRepositoring, exercise: ExerciseDefinition? = nil) {
        // Tudo calculado em locais e com o nome da classe (não `Self`): com @Observable, ler
        // `self.draft` antes de inicializar todas as propriedades seria uso de `self` antes da hora.
        let initialDraft: ExerciseDraft
        let initialMode: Mode
        let seed: Bool
        if let exercise {
            initialDraft = ExerciseDraft(from: exercise)
            initialMode = .edit(exercise.id)
            seed = !exercise.isCustom
        } else {
            initialDraft = ExerciseDraft()
            initialMode = .create
            seed = false
        }
        let choice = ExerciseEditorViewModel.choice(for: initialDraft.loadIncrement)
        let customText = choice == .custom
            ? ExerciseEditorViewModel.incrementText(initialDraft.loadIncrement)
            : ""

        self.catalog = catalog
        self.mode = initialMode
        self.isSeedExercise = seed
        self.draft = initialDraft
        self.originalDraft = ExerciseEditorViewModel.normalized(initialDraft)
        self.storedIncrementChoice = choice
        self.storedCustomIncrementText = customText
    }

    var title: String {
        switch mode {
        case .create: return "Novo exercício"
        case .edit: return "Editar exercício"
        }
    }

    /// Salvar só com nome, ≥ 1 grupo primário e incremento válido (`ExerciseDraft.isValid`).
    var canSave: Bool {
        draft.isValid
    }

    /// Há edição não gravada: a view impede fechar a sheet arrastando.
    var hasUnsavedChanges: Bool {
        normalizedDraft != originalDraft
    }

    /// Ponte para `.alert(isPresented:)`: verdadeiro enquanto há mensagem; atribuir `false` limpa.
    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    // MARK: - Incremento

    var incrementChoice: IncrementChoice {
        get { storedIncrementChoice }
        set {
            storedIncrementChoice = newValue
            if newValue == .custom, storedCustomIncrementText.isEmpty {
                // Parte do valor atual para o campo não abrir vazio (e o Salvar não apagar).
                storedCustomIncrementText = Self.incrementText(draft.loadIncrement)
            }
            applyIncrement()
        }
    }

    /// Texto do incremento personalizado; aceita vírgula ou ponto ("1,25", "1.25").
    var customIncrementText: String {
        get { storedCustomIncrementText }
        set {
            storedCustomIncrementText = newValue
            applyIncrement()
        }
    }

    /// Valor inválido vira 0 no rascunho: `isValid` exige incremento > 0 e o Salvar desabilita.
    private func applyIncrement() {
        if let fixed = storedIncrementChoice.value {
            draft.loadIncrement = fixed
        } else {
            draft.loadIncrement = Self.parseIncrement(storedCustomIncrementText) ?? 0
        }
    }

    // MARK: - Notas da máquina

    /// `machineNotes` é opcional no rascunho; o campo de texto vê "" e o `saveExercise()` grava `nil`
    /// quando só há espaços.
    var machineNotesText: String {
        get { draft.machineNotes ?? "" }
        set { draft.machineNotes = newValue.isEmpty ? nil : newValue }
    }

    // MARK: - Músculos

    /// Liga/desliga um grupo primário, preservando a ordem de marcação (o primeiro define a seção
    /// do exercício no seletor). Marcar como primário tira o grupo dos secundários.
    func togglePrimary(_ group: MuscleGroup) {
        if let index = draft.primaryMuscles.firstIndex(of: group) {
            draft.primaryMuscles.remove(at: index)
        } else {
            draft.primaryMuscles.append(group)
            draft.secondaryMuscles.removeAll { $0 == group }
        }
    }

    /// Liga/desliga um grupo secundário. Grupos já primários são ignorados (a view os esmaece).
    func toggleSecondary(_ group: MuscleGroup) {
        guard !draft.primaryMuscles.contains(group) else { return }
        if let index = draft.secondaryMuscles.firstIndex(of: group) {
            draft.secondaryMuscles.remove(at: index)
        } else {
            draft.secondaryMuscles.append(group)
        }
    }

    /// Resumo para o rodapé da seção de primários: qual grupo define a seção no seletor.
    var mainGroupText: String {
        guard let first = draft.primaryMuscles.first else {
            return "Marque ao menos um grupo primário."
        }
        return "Principal: \(first.displayName). O primeiro grupo marcado define a seção do exercício no seletor."
    }

    // MARK: - Salvar

    /// Grava pelo repositório. Devolve `true` em sucesso (a view fecha); em falha deixa a
    /// mensagem em `errorMessage` e mantém o rascunho para o usuário corrigir.
    @discardableResult
    func saveExercise() -> Bool {
        let toSave = normalizedDraft
        guard toSave.isValid else {
            errorMessage = "Preencha o nome, marque ao menos um grupo primário e informe um incremento maior que zero."
            return false
        }
        do {
            switch mode {
            case .create:
                // Segundo toque em "Salvar" antes de a sheet fechar atualiza o que acabou de ser
                // criado em vez de duplicar o exercício.
                if let createdID = savedExerciseID {
                    try catalog.updateExercise(id: createdID, with: toSave)
                } else {
                    savedExerciseID = try catalog.createExercise(toSave)
                }
            case .edit(let id):
                try catalog.updateExercise(id: id, with: toSave)
                savedExerciseID = id
            }
            draft = toSave
            originalDraft = toSave
            return true
        } catch {
            Self.logger.error("Falha ao salvar exercício: \(String(describing: error), privacy: .public)")
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// O rascunho atual como será gravado (ver `normalized(_:)`).
    var normalizedDraft: ExerciseDraft {
        ExerciseEditorViewModel.normalized(draft)
    }

    // MARK: - Helpers puros (testáveis sem UI)

    /// Nome e notas sem espaços nas pontas; notas vazias viram `nil`.
    nonisolated static func normalized(_ draft: ExerciseDraft) -> ExerciseDraft {
        var result = draft
        result.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (draft.machineNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        result.machineNotes = notes.isEmpty ? nil : notes
        return result
    }

    /// Opção do Picker que corresponde a um incremento já gravado; outros valores são personalizados.
    nonisolated static func choice(for increment: Double) -> IncrementChoice {
        for option in IncrementChoice.allCases {
            if let value = option.value, value == increment {
                return option
            }
        }
        return .custom
    }

    /// "1,25" → 1.25; aceita vírgula ou ponto. `nil` para vazio, não numérico, não finito ou ≤ 0.
    nonisolated static func parseIncrement(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    /// 1.25 → "1,25"; 2 → "2". Texto inicial do campo personalizado.
    nonisolated static func incrementText(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "" }
        if value == value.rounded(), value < 1_000_000 {
            return String(Int(value))
        }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }

    private static func message(for error: any Error) -> String {
        if let catalogError = error as? CatalogRepositoryError {
            switch catalogError {
            case .exerciseNotFound:
                return "Este exercício não foi encontrado no catálogo."
            case .invalidDraft:
                return "Preencha o nome, marque ao menos um grupo primário e informe um incremento maior que zero."
            }
        }
        return "Não foi possível salvar o exercício."
    }
}
