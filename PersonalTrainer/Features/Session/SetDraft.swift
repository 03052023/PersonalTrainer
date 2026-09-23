import Foundation
import TrainerCore

/// Valores pré-preenchidos da próxima série, editados pelo usuário em `SetEntryView` (RF-04).
/// Construído pelo `ActiveSessionViewModel` a partir da prescrição (1ª série) ou da série anterior.
/// É puro estado de UI: nada aqui é persistido; ao confirmar, vira um evento `setLogged`.
struct SetDraft: Sendable, Hashable {
    /// Carga em kg (ou placas/nível conforme `loadUnit`). Passo do stepper = `loadIncrement`.
    var load: Double
    var reps: Int
    /// RIR 0…5; `nil` = não informado.
    var rir: Int?
    var isWarmup: Bool

    // Contexto imutável para a view formatar e limitar os steppers.
    /// 0-based, gravado em `SetLogModel.index`. Único dentro do exercício: depois de apagar uma
    /// série (RF-19) pode haver lacunas, então não serve para exibição.
    let setIndex: Int
    /// 1-based, só para o título "Série 2 de 3": posição da próxima série entre as registradas.
    let setNumber: Int
    let plannedSets: Int
    /// Carga da prescrição gravada no snapshot; `nil` em calibração sem `startingLoad`
    /// (SPEC P2). Só para exibição: o stepper edita `load`, que começa em 0 nesse caso.
    let prescribedLoad: Double?
    let loadIncrement: Double
    let loadUnit: LoadUnit
    let repMin: Int
    let repMax: Int
    let targetReps: Int
    let targetRIR: Int
    let note: PrescriptionNote

    init(
        load: Double,
        reps: Int,
        rir: Int?,
        isWarmup: Bool = false,
        setIndex: Int,
        setNumber: Int? = nil,
        plannedSets: Int,
        prescribedLoad: Double?,
        loadIncrement: Double,
        loadUnit: LoadUnit,
        repMin: Int,
        repMax: Int,
        targetReps: Int,
        targetRIR: Int,
        note: PrescriptionNote
    ) {
        self.load = load
        self.reps = reps
        self.rir = rir
        self.isWarmup = isWarmup
        self.setIndex = setIndex
        // Sem lacunas (nenhuma série apagada), a posição coincide com o índice.
        self.setNumber = setNumber ?? setIndex + 1
        self.plannedSets = plannedSets
        self.prescribedLoad = prescribedLoad
        self.loadIncrement = loadIncrement
        self.loadUnit = loadUnit
        self.repMin = repMin
        self.repMax = repMax
        self.targetReps = targetReps
        self.targetRIR = targetRIR
        self.note = note
    }

    /// Texto curto da prescrição, ex.: "3 × 8–12 · 60 kg · RIR 2". Usa a carga PRESCRITA, não
    /// a que o usuário está editando: é a mesma convenção da Home (`PrescriptionRow`) e do
    /// histórico, inclusive o "—" da calibração sem carga (SPEC P2).
    var prescriptionSummary: String {
        let loadText: String
        if let prescribedLoad {
            switch loadUnit {
            case .kilograms: loadText = LoadFormatter.kilograms(prescribedLoad)
            case .plates: loadText = "\(Int(prescribedLoad.rounded())) placas"
            case .level: loadText = "nível \(Int(prescribedLoad.rounded()))"
            }
        } else {
            loadText = "—"
        }
        return "\(plannedSets) × \(repMin)–\(repMax) · \(loadText) · RIR \(targetRIR)"
    }
}

/// Formatação pt-BR de cargas, compartilhada por Home, sessão e histórico.
enum LoadFormatter {
    /// "60 kg", "62,5 kg". Sem casas decimais quando inteiro.
    static func kilograms(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) kg"
    }

    /// Carga opcional: `nil` vira "—" (prescrição de calibração, SPEC P2).
    static func kilograms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return kilograms(value)
    }
}
