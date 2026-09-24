import SwiftUI
import TrainerCore

/// Uma linha do card da Home (SPEC F1, RF-01; CA1-1): nome do exercício, resumo
/// "S × min–max · carga · RIR T · descanso", a nota da prescrição em pt-BR e o botão
/// "Por quê?" da nota (SPEC RF-32).
///
/// A faixa sai na medida do exercício (SPEC RF-43, lida de `\.exerciseTraits` pelo `slug`):
/// "3 × 20–40 s", "3 × 20–40 passos". O VoiceOver lê o resumo por extenso, com "RIR 2" como
/// "parar com 2 repetições de reserva" (SPEC RF-41 d).
/// View pura: só formata o `PlannedExercise`; nada de coordinator ou SwiftData.
struct PrescriptionRow: View {
    let exercise: PlannedExercise
    let references: ReferenceCatalog

    @Environment(\.exerciseTraits) private var traits

    init(exercise: PlannedExercise, references: ReferenceCatalog) {
        self.exercise = exercise
        self.references = references
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(exercise.exercise.name)
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    PrescriptionNoteBadge(note: exercise.prescription.note)
                }
                Text(Self.summary(for: exercise, measure: measure))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Self.spokenSummary(for: exercise, measure: measure))
            }
            // Só o texto é combinado: o botão "Por quê?" fica fora para continuar acionável
            // sozinho no VoiceOver.
            .accessibilityElement(children: .combine)

            // Esconde-se sozinho quando o catálogo não tem referências para a nota.
            WhyButton(topic: ReferenceCatalog.topic(for: exercise.prescription.note), catalog: references)
        }
    }

    /// Repetições, segundos ou passos (SPEC RF-43). Personalizado sempre em repetições.
    private var measure: ExerciseMeasure {
        traits.traits(for: exercise.exercise).measure
    }

    // MARK: - Formatação (pt-BR)

    /// Ex.: "3 × 8–12 · 60 kg · RIR 2 · 2 min" ou "3 × 20–40 s · 0 kg · RIR 2 · 1 min";
    /// carga `nil` (SPEC P2) vira "—".
    static func summary(for exercise: PlannedExercise, measure: ExerciseMeasure = .reps) -> String {
        let prescription = exercise.prescription
        let range = MeasureText.range(min: prescription.repMin, max: prescription.repMax, measure: measure)
        let load = loadText(prescription.load, unit: exercise.exercise.loadUnit)
        let rest = restText(seconds: prescription.restSeconds)
        return "\(prescription.sets) × \(range) · \(load) · RIR \(prescription.targetRIR) · \(rest)"
    }

    /// Leitura por voz do resumo (SPEC RF-41 d): "3 séries de 8 a 12 repetições, 60 kg, parar
    /// com 2 repetições de reserva, descanso de 2 minutos".
    static func spokenSummary(for exercise: PlannedExercise, measure: ExerciseMeasure = .reps) -> String {
        let prescription = exercise.prescription
        return PrescriptionSpeech.text(
            sets: prescription.sets,
            repMin: prescription.repMin,
            repMax: prescription.repMax,
            measure: measure,
            loadText: prescription.load.map { loadText($0, unit: exercise.exercise.loadUnit) },
            targetRIR: prescription.targetRIR,
            restSeconds: prescription.restSeconds
        )
    }

    /// Mesma convenção de `SetDraft.prescriptionSummary`: kg via `LoadFormatter`, placas e nível
    /// como inteiros.
    static func loadText(_ load: Double?, unit: LoadUnit) -> String {
        guard let load else { return "—" }
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

    /// "2 min", "90 s" abaixo de um minuto vira "45 s", e valores quebrados "1 min 30 s".
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

    /// Rótulos fixos acordados para o M1 (AGENTS §4: textos de UI em pt-BR no código). A nota de
    /// semana leve segue o vocabulário do DESIGN §6 ("semana leve", nunca "deload").
    static func noteText(_ note: PrescriptionNote) -> String {
        switch note {
        case .calibrate: return "Calibrar"
        case .increase: return "Subir"
        case .hold: return "Manter"
        case .retry: return "Repetir"
        case .decrease: return "Reduzir"
        case .returning: return "Retorno"
        case .deload: return "Semana leve"
        }
    }
}

/// Selo colorido da nota. Privado ao arquivo: só a linha o usa.
private struct PrescriptionNoteBadge: View {
    let note: PrescriptionNote

    var body: some View {
        Text(PrescriptionRow.noteText(note))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var tint: Color {
        switch note {
        case .calibrate: return .blue
        case .increase: return .green
        case .hold: return .gray
        case .retry: return .yellow
        case .decrease: return .orange
        case .returning: return .teal
        case .deload: return .purple
        }
    }
}
