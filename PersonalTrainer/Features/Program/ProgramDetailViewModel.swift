import Foundation
import Observation
import os
import TrainerCore

/// Estado da edição de um programa (T2.6, T2.12, T2.20; SPEC RF-16, RF-33, RF-34).
///
/// Compartilhado por `ProgramDetailView` (nome, objetivo, dias) e `DayEditorView` (alvos do dia).
/// Toda escrita passa pelo `ProgramRepositoring` e cada escrita termina relendo o programa: a UI
/// mostra sempre o que foi gravado, nunca uma cópia local otimista (AGENTS R4).
///
/// Os erros ficam separados por tela (`errorMessage` na tela do programa, `dayErrorMessage` no
/// editor do dia) porque as duas vivem ao mesmo tempo na pilha de navegação e um único estado
/// faria as duas tentarem apresentar o mesmo alerta.
@Observable
@MainActor
final class ProgramDetailViewModel {
    let programID: UUID
    /// Programa relido do repositório; `nil` antes do primeiro `refresh()` ou se sumiu.
    private(set) var program: ProgramTemplate?
    /// Todo o catálogo, arquivados inclusive: um alvo pode apontar para um exercício arquivado
    /// e o nome precisa continuar aparecendo.
    private(set) var exercisesByID: [UUID: ExerciseDefinition] = [:]
    /// Catálogo sem arquivados, na ordem do repositório: é o que os seletores oferecem.
    private(set) var availableExercises: [ExerciseDefinition] = []
    private(set) var didFailToLoad = false
    /// Verdadeiro depois da primeira leitura (com ou sem sucesso): separa "carregando" de
    /// "programa não encontrado".
    private(set) var hasLoaded = false
    /// Alerta da tela do programa.
    var errorMessage: String?
    /// Alerta do editor do dia.
    var dayErrorMessage: String?

    private let programs: any ProgramRepositoring
    private let catalog: any CatalogRepositoring

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "ProgramDetail"
    )

    init(programID: UUID, programs: any ProgramRepositoring, catalog: any CatalogRepositoring) {
        self.programID = programID
        self.programs = programs
        self.catalog = catalog
    }

    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    var isPresentingDayError: Bool {
        get { dayErrorMessage != nil }
        set {
            if !newValue {
                dayErrorMessage = nil
            }
        }
    }

    /// Objetivo efetivo do programa (`nil` em arquivos v1 = hipertrofia).
    var goal: ProgramGoal {
        program?.effectiveGoal ?? .hypertrophy
    }

    /// Dias na ordem de `order` (SPEC S1).
    var days: [ProgramDayTemplate] {
        (program?.days ?? []).sorted { $0.order < $1.order }
    }

    // MARK: - Leitura

    /// Relê programa e catálogo. Chamado pela tela do programa ao aparecer.
    func refresh() {
        reload(onDayScreen: false)
    }

    /// A falha de leitura vai para o alerta da tela visível: depois de uma escrita no editor do
    /// dia, é o editor que avisa.
    private func reload(onDayScreen: Bool) {
        defer { hasLoaded = true }
        do {
            program = try programs.program(id: programID)
            let everything = try catalog.allExercises(includeArchived: true)
            exercisesByID = Dictionary(everything.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            availableExercises = try catalog.allExercises(includeArchived: false)
            didFailToLoad = false
        } catch {
            didFailToLoad = true
            Self.logger.error("Program detail load failed: \(String(describing: error), privacy: .public)")
            let message = Self.message(for: error, fallback: "Não foi possível carregar o programa.")
            if onDayScreen {
                dayErrorMessage = message
            } else {
                errorMessage = message
            }
        }
    }

    func day(id dayID: UUID) -> ProgramDayTemplate? {
        program?.days.first { $0.id == dayID }
    }

    /// Alvos do dia na ordem de `order`.
    func targets(inDay dayID: UUID) -> [ExerciseTarget] {
        (day(id: dayID)?.exercises ?? []).sorted { $0.order < $1.order }
    }

    func exercise(for target: ExerciseTarget) -> ExerciseDefinition? {
        exercisesByID[target.exerciseID]
    }

    func exerciseName(for target: ExerciseTarget) -> String {
        exercisesByID[target.exerciseID]?.name ?? "Exercício removido do catálogo"
    }

    /// Texto da linha do alvo, com a unidade de carga do exercício.
    func summary(for target: ExerciseTarget) -> String {
        Self.targetSummary(target, unit: exercisesByID[target.exerciseID]?.loadUnit ?? .kilograms)
    }

    // MARK: - Programa (nome e objetivo)

    /// Renomeia. Nome vazio (só espaços) é recusado antes de ir ao repositório.
    func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "O nome do programa não pode ficar vazio."
            return
        }
        guard trimmed != program?.name else { return }
        perform(fallback: "Não foi possível renomear o programa.", onDayScreen: false) {
            try programs.rename(programID: programID, to: trimmed)
        }
    }

    /// Troca o objetivo (T2.12). Com `applyDefaults`, o repositório reescreve faixa, RIR e
    /// descanso de todos os exercícios conforme `ProgramGoal.defaults` (SPEC §7.9).
    func setGoal(_ newGoal: ProgramGoal, applyDefaults: Bool) {
        perform(fallback: "Não foi possível trocar o objetivo.", onDayScreen: false) {
            try programs.setGoal(programID: programID, goal: newGoal, applyDefaults: applyDefaults)
        }
    }

    // MARK: - Dias do programa (T2.22, RF-36)

    /// RF-36: no máximo `ProgramLimits.maxDays` dias por programa.
    var canAddDay: Bool {
        days.count < ProgramLimits.maxDays
    }

    /// RF-36: no mínimo `ProgramLimits.minDays` dia por programa.
    var canRemoveDay: Bool {
        days.count > ProgramLimits.minDays
    }

    /// Acrescenta um dia com o próximo rótulo livre ("Dia D", "Dia E"…, RF-36).
    func addDay() {
        guard canAddDay else {
            errorMessage = Self.message(for: ProgramRepositoryError.tooManyDays, fallback: "")
            return
        }
        perform(fallback: "Não foi possível adicionar o dia.", onDayScreen: false) {
            _ = try programs.addDay(programID: programID, name: nil)
        }
    }

    /// Renomeia um dia. Nome vazio (só espaços) é recusado antes de ir ao repositório.
    func renameDay(id dayID: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "O nome do dia não pode ficar vazio."
            return
        }
        guard trimmed != day(id: dayID)?.name else { return }
        perform(fallback: "Não foi possível renomear o dia.", onDayScreen: false) {
            try programs.renameDay(id: dayID, to: trimmed)
        }
    }

    /// Remove um dia (a view confirma antes de chamar). RF-36: o programa nunca fica com menos
    /// de `ProgramLimits.minDays` dias; nesse caso nada é removido e a tela avisa. O histórico
    /// (por sessão) não muda (ARCHITECTURE §5, decisão 3).
    func removeDay(id dayID: UUID) {
        guard canRemoveDay else {
            errorMessage = Self.message(for: ProgramRepositoryError.tooFewDays, fallback: "")
            return
        }
        perform(fallback: "Não foi possível remover o dia.", onDayScreen: false) {
            try programs.removeDay(id: dayID)
        }
    }

    /// Reordena os dias com a semântica de `.onMove` (mesmo algoritmo de `moveTargets`).
    func moveDays(fromOffsets source: IndexSet, toOffset destination: Int) {
        let current = days.map(\.id)
        let desired = Self.reordered(current, moving: source, to: destination)
        guard desired != current else { return }
        perform(fallback: "Não foi possível reordenar os dias.", onDayScreen: false) {
            for (index, id) in Self.moveSteps(from: current, to: desired) {
                try programs.moveDay(id: id, toIndex: index)
            }
        }
    }

    // MARK: - Dia (RF-33, RF-34, RF-16)

    /// RF-33: no máximo `ProgramLimits.maxExercisesPerDay` por dia.
    func canAddExercise(toDay dayID: UUID) -> Bool {
        targets(inDay: dayID).count < ProgramLimits.maxExercisesPerDay
    }

    func addExercise(_ exerciseID: UUID, toDay dayID: UUID) {
        guard canAddExercise(toDay: dayID) else {
            dayErrorMessage = Self.message(for: ProgramRepositoryError.tooManyExercises, fallback: "")
            return
        }
        perform(fallback: "Não foi possível adicionar o exercício.", onDayScreen: true) {
            _ = try programs.addExercise(exerciseID: exerciseID, toDay: dayID)
        }
    }

    /// Remove os alvos nas posições dadas (índices da lista ordenada). RF-33: o dia nunca fica
    /// com menos de `ProgramLimits.minExercisesPerDay`; nesse caso nada é removido e a tela avisa.
    func removeTargets(atOffsets offsets: IndexSet, inDay dayID: UUID) {
        let current = targets(inDay: dayID)
        let ids = offsets.filter { current.indices.contains($0) }.map { current[$0].id }
        guard !ids.isEmpty else { return }
        guard current.count - ids.count >= ProgramLimits.minExercisesPerDay else {
            dayErrorMessage = Self.message(for: ProgramRepositoryError.tooFewExercises, fallback: "")
            return
        }
        perform(fallback: "Não foi possível remover o exercício.", onDayScreen: true) {
            for id in ids {
                try programs.removeTarget(id: id)
            }
        }
    }

    /// Reordena com a semântica de `.onMove` (destino = índice antes da remoção). Cada passo usa
    /// `moveTarget(id:toIndex:)`, que renumera `order` de 0 a n-1 no repositório.
    func moveTargets(fromOffsets source: IndexSet, toOffset destination: Int, inDay dayID: UUID) {
        let current = targets(inDay: dayID).map(\.id)
        let desired = Self.reordered(current, moving: source, to: destination)
        guard desired != current else { return }
        perform(fallback: "Não foi possível reordenar os exercícios.", onDayScreen: true) {
            for (index, id) in Self.moveSteps(from: current, to: desired) {
                try programs.moveTarget(id: id, toIndex: index)
            }
        }
    }

    /// RF-34 na edição: troca o exercício do alvo mantendo séries, faixa, RIR e descanso.
    func replaceExercise(targetID: UUID, with exerciseID: UUID) {
        perform(fallback: "Não foi possível trocar o exercício.", onDayScreen: true) {
            try programs.replaceExercise(targetID: targetID, with: exerciseID)
        }
    }

    /// Substitutos sugeridos para o alvo (mesmo padrão de movimento e grupo primário, RF-34),
    /// sem repetir exercícios que já estão no dia.
    func substitutes(forTargetID targetID: UUID, inDay dayID: UUID, limit: Int = 20) -> [ExerciseDefinition] {
        let dayTargets = targets(inDay: dayID)
        guard
            let target = dayTargets.first(where: { $0.id == targetID }),
            let exercise = exercisesByID[target.exerciseID]
        else {
            return []
        }
        return ExerciseSubstitution.candidates(
            for: exercise,
            in: availableExercises,
            excluding: Set(dayTargets.map(\.exerciseID)),
            limit: limit
        )
    }

    /// Rascunho pré-preenchido para `TargetEditorSheet`.
    func makeDraft(forTargetID targetID: UUID, inDay dayID: UUID) -> TargetDraft? {
        guard let target = targets(inDay: dayID).first(where: { $0.id == targetID }) else {
            return nil
        }
        let exercise = exercisesByID[target.exerciseID]
        return TargetDraft(
            target: target,
            loadUnit: exercise?.loadUnit ?? .kilograms,
            loadIncrement: exercise?.loadIncrement ?? 2.5,
            isBodyweight: exercise?.equipment == .bodyweight
        )
    }

    /// Grava séries/faixa/RIR/descanso/carga inicial (RF-16). O rascunho é validado antes.
    func updateTarget(id targetID: UUID, with draft: TargetDraft) {
        if let problem = draft.validationMessage {
            dayErrorMessage = problem
            return
        }
        perform(fallback: "Não foi possível salvar o exercício.", onDayScreen: true) {
            try programs.updateTarget(
                id: targetID,
                sets: draft.sets,
                repMin: draft.repMin,
                repMax: draft.repMax,
                targetRIR: draft.targetRIR,
                restSeconds: draft.restSeconds,
                startingLoad: draft.startingLoad
            )
        }
    }

    // MARK: - Execução comum

    /// Executa a escrita, registra a falha no alerta da tela certa e sempre relê o programa.
    private func perform(fallback: String, onDayScreen: Bool, _ write: () throws -> Void) {
        do {
            try write()
        } catch {
            Self.logger.error("Program edit failed: \(String(describing: error), privacy: .public)")
            let message = Self.message(for: error, fallback: fallback)
            if onDayScreen {
                dayErrorMessage = message
            } else {
                errorMessage = message
            }
        }
        reload(onDayScreen: onDayScreen)
    }

    // MARK: - Helpers puros (testáveis sem UI)

    /// Mesma semântica de `MutableCollection.move(fromOffsets:toOffset:)` do SwiftUI, sem
    /// importar SwiftUI no ViewModel: os itens movidos mantêm a ordem relativa e entram antes do
    /// elemento que estava em `destination`.
    static func reordered<Element>(_ items: [Element], moving source: IndexSet, to destination: Int) -> [Element] {
        let valid = source.filter { items.indices.contains($0) }
        guard !valid.isEmpty else { return items }
        let moving = valid.sorted().map { items[$0] }
        var remaining: [Element] = []
        for (index, item) in items.enumerated() where !valid.contains(index) {
            remaining.append(item)
        }
        let clampedDestination = min(max(destination, 0), items.count)
        let shift = valid.filter { $0 < clampedDestination }.count
        let insertion = min(max(clampedDestination - shift, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertion)
        return remaining
    }

    /// Sequência de `(índice final, id)` que leva `current` a `desired` usando só "mover um item
    /// para a posição i". Um arrasto simples vira um único passo; casos gerais, no máximo n − 1.
    static func moveSteps(from current: [UUID], to desired: [UUID]) -> [(index: Int, id: UUID)] {
        guard Set(current) == Set(desired), current.count == desired.count else { return [] }
        // Arrasto de um só item: remover um elemento de `current` deixa os demais na ordem de
        // `desired`. Resolve em um passo, que é o caso comum do `.onMove`.
        for (index, id) in desired.enumerated() {
            var withoutMoved = current
            withoutMoved.removeAll { $0 == id }
            var desiredWithoutMoved = desired
            desiredWithoutMoved.remove(at: index)
            if withoutMoved == desiredWithoutMoved {
                return [(index: index, id: id)]
            }
        }
        var working = current
        var steps: [(index: Int, id: UUID)] = []
        for (index, id) in desired.enumerated() where working[index] != id {
            guard let from = working.firstIndex(of: id) else { continue }
            working.remove(at: from)
            working.insert(id, at: index)
            steps.append((index: index, id: id))
        }
        return steps
    }

    /// "3 × 8–12 · RIR 2 · 2 min", mais "· inicial 60 kg" quando há carga inicial (SPEC P2).
    static func targetSummary(_ target: ExerciseTarget, unit: LoadUnit) -> String {
        var text = "\(target.sets) × \(target.repMin)–\(target.repMax) · RIR \(target.targetRIR) · \(restText(seconds: target.restSeconds))"
        if let startingLoad = target.startingLoad {
            text += " · inicial \(loadText(startingLoad, unit: unit))"
        }
        return text
    }

    /// "1 exercício", "5 exercícios".
    static func exerciseCountText(_ count: Int) -> String {
        count == 1 ? "1 exercício" : "\(count) exercícios"
    }

    /// "2 min", "45 s", "1 min 30 s"; mesma convenção da Home.
    static func restText(seconds: Int) -> String {
        guard seconds > 0 else { return "sem descanso" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 {
            return "\(remainder) s"
        }
        if remainder == 0 {
            return "\(minutes) min"
        }
        return "\(minutes) min \(remainder) s"
    }

    /// Carga na unidade do exercício: "62,5 kg", "4 placas", "nível 7".
    static func loadText(_ load: Double, unit: LoadUnit) -> String {
        switch unit {
        case .kilograms:
            return LoadFormatter.kilograms(load)
        case .plates:
            let count = Int(load.rounded())
            return count == 1 ? "1 placa" : "\(count) placas"
        case .level:
            return "nível \(Int(load.rounded()))"
        }
    }

    static func message(for error: any Error, fallback: String) -> String {
        guard let repositoryError = error as? ProgramRepositoryError else {
            return fallback
        }
        switch repositoryError {
        case .programNotFound:
            return "Programa não encontrado."
        case .dayNotFound:
            return "Dia não encontrado no programa."
        case .targetNotFound:
            return "Exercício não encontrado no dia."
        case .exerciseNotFound:
            return "Exercício não encontrado no catálogo."
        case .cannotDeleteActive:
            return "O programa ativo não pode ser apagado."
        case .tooManyExercises:
            return "Cada dia pode ter no máximo \(ProgramLimits.maxExercisesPerDay) exercícios."
        case .tooFewExercises:
            return "Cada dia precisa de pelo menos \(ProgramLimits.minExercisesPerDay) exercício."
        case .tooManyDays:
            return "O programa pode ter no máximo \(ProgramLimits.maxDays) dias."
        case .tooFewDays:
            return "O programa precisa de pelo menos \(ProgramLimits.minDays) dia."
        case .invalidParameters(let detail):
            return detail.isEmpty ? "Valores inválidos." : "Valores inválidos: \(detail)"
        }
    }
}

// MARK: - Rascunho do alvo

extension ProgramDetailViewModel {
    /// Parâmetros editáveis de um alvo, com os limites do `ProgramRepositoring.updateTarget`:
    /// séries 1…10, 1 ≤ repMin < repMax ≤ 50, RIR 0…5, descanso 15…600 s em passos de 15 s,
    /// carga inicial ≥ 0 e múltipla do incremento (SPEC P8) ou `nil`.
    struct TargetDraft: Sendable, Hashable {
        static let setsRange = 1...10
        static let repMinLimit = 1
        static let repMaxLimit = 50
        static let rirRange = 0...5
        static let restRange = 15...600
        static let restStep = 15

        var sets: Int
        var repMin: Int
        var repMax: Int
        var targetRIR: Int
        var restSeconds: Int
        var startingLoad: Double?

        let loadUnit: LoadUnit
        let loadIncrement: Double
        /// Peso corporal aceita carga 0 (SPEC P8); os demais começam em um incremento.
        let isBodyweight: Bool

        /// Normaliza valores fora dos limites (dados antigos) para os steppers nunca receberem
        /// um intervalo inválido.
        init(target: ExerciseTarget, loadUnit: LoadUnit, loadIncrement: Double, isBodyweight: Bool) {
            let safeIncrement = loadIncrement.isFinite && loadIncrement > 0 ? loadIncrement : 1
            let repMax = min(max(target.repMax, Self.repMinLimit + 1), Self.repMaxLimit)
            self.sets = min(max(target.sets, Self.setsRange.lowerBound), Self.setsRange.upperBound)
            self.repMax = repMax
            self.repMin = min(max(target.repMin, Self.repMinLimit), repMax - 1)
            self.targetRIR = min(max(target.targetRIR, Self.rirRange.lowerBound), Self.rirRange.upperBound)
            self.restSeconds = Self.normalizedRest(target.restSeconds)
            self.startingLoad = Self.snappedLoad(target.startingLoad, increment: safeIncrement)
            self.loadUnit = loadUnit
            self.loadIncrement = safeIncrement
            self.isBodyweight = isBodyweight
        }

        /// Faixas dos steppers de repetições; nunca vazias porque `repMin < repMax` é mantido.
        var repMinRange: ClosedRange<Int> {
            Self.repMinLimit...max(Self.repMinLimit, repMax - 1)
        }

        var repMaxRange: ClosedRange<Int> {
            min(repMin + 1, Self.repMaxLimit)...Self.repMaxLimit
        }

        /// Menor carga inicial aceita pelo stepper.
        var minimumLoad: Double {
            isBodyweight ? 0 : loadIncrement
        }

        /// Maior múltiplo do incremento até 1000 (kg, placas ou nível).
        var maximumLoad: Double {
            max((1000 / loadIncrement).rounded(.down) * loadIncrement, minimumLoad)
        }

        /// Valor ao ligar a carga inicial.
        var defaultStartingLoad: Double {
            minimumLoad
        }

        /// `nil` quando válido; senão a primeira violação em pt-BR.
        var validationMessage: String? {
            if !Self.setsRange.contains(sets) {
                return "Séries devem ficar entre 1 e 10."
            }
            if repMin < Self.repMinLimit || repMax > Self.repMaxLimit || repMin >= repMax {
                return "A faixa de repetições deve ter mínimo menor que o máximo, entre 1 e 50."
            }
            if !Self.rirRange.contains(targetRIR) {
                return "O RIR alvo deve ficar entre 0 e 5."
            }
            if !Self.restRange.contains(restSeconds) {
                return "O descanso deve ficar entre 15 s e 10 min."
            }
            if let startingLoad {
                if !startingLoad.isFinite || startingLoad < 0 {
                    return "A carga inicial não pode ser negativa."
                }
                let ratio = startingLoad / loadIncrement
                if abs(ratio - ratio.rounded()) > 1e-6 {
                    return "A carga inicial deve ser múltipla do incremento do exercício."
                }
            }
            return nil
        }

        /// Arredonda ao passo de 15 s mais próximo e limita a 15…600 s.
        static func normalizedRest(_ seconds: Int) -> Int {
            let rounded = Int((Double(seconds) / Double(restStep)).rounded()) * restStep
            return min(max(rounded, restRange.lowerBound), restRange.upperBound)
        }

        /// Carga antiga fora da grade do incremento (SPEC P8) desce ao múltiplo anterior, para o
        /// stepper andar em múltiplos; negativa vira 0. Tolera erro de ponto flutuante.
        static func snappedLoad(_ load: Double?, increment: Double) -> Double? {
            guard let load, load.isFinite else { return nil }
            let ratio = max(load, 0) / increment
            let nearest = ratio.rounded()
            let steps = abs(ratio - nearest) < 1e-6 ? nearest : ratio.rounded(.down)
            return steps * increment
        }
    }
}
