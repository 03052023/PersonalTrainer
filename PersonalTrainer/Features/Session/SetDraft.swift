import Foundation
import TrainerCore

/// Valores pré-preenchidos da próxima série, editados pelo usuário em `SetEntryView` (RF-04).
/// Construído pelo `ActiveSessionViewModel` a partir da prescrição (1ª série) ou da série anterior.
/// É puro estado de UI: nada aqui é persistido; ao confirmar, vira um evento `setLogged`.
struct SetDraft: Sendable, Hashable {
    /// Carga em kg (ou placas/nível conforme `loadUnit`). Passo do stepper = `loadIncrement`.
    var load: Double
    /// Repetições, segundos ou passos, conforme `measure` (SPEC RF-43). Gravado em `reps`.
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
    /// O que o número da série conta (SPEC RF-43), vindo do catálogo do seed pelo `slug`.
    let measure: ExerciseMeasure

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
        note: PrescriptionNote,
        measure: ExerciseMeasure = .reps
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
        self.measure = measure
    }

    /// Texto curto da prescrição, ex.: "3 × 8–12 · 60 kg · RIR 2" ou "3 × 20–40 s · — · RIR 2".
    /// Usa a carga PRESCRITA, não a que o usuário está editando: é a mesma convenção da Home
    /// (`PrescriptionRow`) e do histórico, inclusive o "—" da calibração sem carga (SPEC P2).
    var prescriptionSummary: String {
        let range = MeasureText.range(min: repMin, max: repMax, measure: measure)
        return "\(plannedSets) × \(range) · \(prescribedLoadText ?? "—") · RIR \(targetRIR)"
    }

    /// Leitura por voz da mesma prescrição (SPEC RF-41 d): "3 séries de 8 a 12 repetições,
    /// 60 kg, parar com 2 repetições de reserva".
    var prescriptionSpokenText: String {
        PrescriptionSpeech.text(
            sets: plannedSets,
            repMin: repMin,
            repMax: repMax,
            measure: measure,
            loadText: prescribedLoadText,
            targetRIR: targetRIR
        )
    }

    /// Carga prescrita na unidade do exercício; `nil` na calibração sem carga (SPEC P2).
    private var prescribedLoadText: String? {
        guard let prescribedLoad else {
            return nil
        }
        switch loadUnit {
        case .kilograms: return LoadFormatter.kilograms(prescribedLoad)
        case .plates: return "\(Int(prescribedLoad.rounded())) placas"
        case .level: return "nível \(Int(prescribedLoad.rounded()))"
        }
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
