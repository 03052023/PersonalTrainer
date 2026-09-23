import SwiftUI
import TrainerCore

/// Uma linha do card da Home (SPEC F1, RF-01; CA1-1): nome do exercício, resumo
/// "S × min–max · carga · RIR T · descanso", a nota da prescrição em pt-BR e o botão
/// "Por quê?" da nota (SPEC RF-32).
/// View pura: só formata o `PlannedExercise`; nada de coordinator ou SwiftData.
struct PrescriptionRow: View {
    let exercise: PlannedExercise
    let references: ReferenceCatalog

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
                Text(Self.summary(for: exercise))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Só o texto é combinado: o botão "Por quê?" fica fora para continuar acionável
            // sozinho no VoiceOver.
            .accessibilityElement(children: .combine)

            // Esconde-se sozinho quando o catálogo não tem referências para a nota.
            WhyButton(topic: ReferenceCatalog.topic(for: exercise.prescription.note), catalog: references)
        }
    }

    // MARK: - Formatação (pt-BR)

    /// Ex.: "3 × 8–12 · 60 kg · RIR 2 · 2 min"; carga `nil` (SPEC P2) vira "—".
    static func summary(for exercise: PlannedExercise) -> String {
        let prescription = exercise.prescription
        let load = loadText(prescription.load, unit: exercise.exercise.loadUnit)
        let rest = restText(seconds: prescription.restSeconds)
        return "\(prescription.sets) × \(prescription.repMin)–\(prescription.repMax) · \(load) · RIR \(prescription.targetRIR) · \(rest)"
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

    /// Rótulos fixos acordados para o M1 (AGENTS §4: textos de UI em pt-BR no código).
    static func noteText(_ note: PrescriptionNote) -> String {
        switch note {
        case .calibrate: return "Calibrar"
        case .increase: return "Subir"
        case .hold: return "Manter"
        case .retry: return "Repetir"
        case .decrease: return "Reduzir"
        case .returning: return "Retorno"
        case .deload: return "Deload"
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
