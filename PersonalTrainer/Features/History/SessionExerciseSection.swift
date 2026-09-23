import SwiftUI
import TrainerCore

/// Uma `Section` de `SessionDetailView` por exercício da sessão (SPEC F5, CA1-7):
/// cabeçalho com nome, prescrição ("3 × 8–12 · 60 kg · RIR 2") e badge "Pulado";
/// uma linha por série ("1 · 60 kg × 10 · RIR 2"), aquecimento marcado, ordenadas por `index`.
///
/// Só leitura: recebe o snapshot da prescrição e as séries; nada aqui escreve (R4).
@MainActor
struct SessionExerciseSection: View {
    let sessionExercise: SessionExerciseModel

    init(sessionExercise: SessionExerciseModel) {
        self.sessionExercise = sessionExercise
    }

    var body: some View {
        Section {
            if orderedSets.isEmpty {
                Text(sessionExercise.wasSkipped ? "Exercício pulado · nenhuma série registrada" : "Nenhuma série registrada")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orderedSets, id: \.uuid) { set in
                    setRow(set)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sessionExercise.exerciseName)
                        .font(.headline)
                    if sessionExercise.wasSkipped {
                        Text("Pulado")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(prescriptionText)
                    .font(.subheadline)
                if let noteText {
                    Text(noteText)
                        .font(.caption)
                }
            }
            // Cabeçalho de lista vem em caixa alta por padrão; nomes de exercício não.
            .textCase(nil)
        }
    }

    // MARK: - Linhas

    private var orderedSets: [SetLogModel] {
        sessionExercise.sets.sorted { $0.index < $1.index }
    }

    private func setRow(_ set: SetLogModel) -> some View {
        HStack {
            Text(setLine(set))
            if set.isWarmup {
                Spacer()
                Text("Aquecimento")
                    .font(.caption)
            }
        }
        // Aquecimento não entra em volume nem progressão (SPEC P1); fica visualmente secundário.
        .foregroundStyle(set.isWarmup ? Color.secondary : Color.primary)
    }

    // MARK: - Textos

    /// "1 · 60 kg × 10 · RIR 2". `index` é 0-based (`SessionCoordinating.logSet`); o usuário
    /// conta a partir de 1.
    private func setLine(_ set: SetLogModel) -> String {
        "\(set.index + 1) · \(loadText(set.load)) × \(set.reps) · \(rirText(set.rir))"
    }

    /// "3 × 8–12 · 60 kg · RIR 2"; carga `nil` (calibração, SPEC P2) vira "—".
    private var prescriptionText: String {
        let loadText: String
        if let load = sessionExercise.prescribedLoad {
            loadText = self.loadText(load)
        } else {
            loadText = "—"
        }
        return "\(sessionExercise.prescribedSets) × \(sessionExercise.prescribedRepMin)–\(sessionExercise.prescribedRepMax) · \(loadText) · RIR \(sessionExercise.prescribedRIR)"
    }

    /// Nota da prescrição em pt-BR; `nil` para raw desconhecido (não inventa padrão).
    private var noteText: String? {
        guard let note = sessionExercise.note else {
            return nil
        }
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

    /// A unidade vem do catálogo relacionado; se a relação foi anulada, assume kg
    /// (o único caso em que o snapshot não basta para formatar).
    private var loadUnit: LoadUnit {
        sessionExercise.exercise?.loadUnit ?? .kilograms
    }

    private func loadText(_ load: Double) -> String {
        switch loadUnit {
        case .kilograms: return LoadFormatter.kilograms(load)
        case .plates: return "\(Int(load.rounded())) placas"
        case .level: return "nível \(Int(load.rounded()))"
        }
    }

    private func rirText(_ rir: Int?) -> String {
        guard let rir else {
            return "RIR —"
        }
        return "RIR \(rir)"
    }
}
