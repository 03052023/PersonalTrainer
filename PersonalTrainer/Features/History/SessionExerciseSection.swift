import SwiftUI
import TrainerCore

/// Uma `Section` de `SessionDetailView` por exercício da sessão (SPEC F5, CA1-7):
/// cabeçalho com nome, prescrição ("3 × 8–12 · 60 kg · RIR 2"), nota com "Por quê?" (RF-32)
/// e badge "Pulado"; uma linha por série ("1 · 60 kg × 10 · RIR 2"), aquecimento marcado,
/// ordenadas por `index`; e por fim o link para a evolução de carga do exercício (T2.10).
///
/// A medida do exercício (SPEC RF-43), lida de `\.exerciseTraits` pelo `slug`, dá a unidade da
/// faixa e das séries ("3 × 20–40 s", "1 · 0 kg × 30 s"); o VoiceOver lê a prescrição por extenso,
/// com "RIR 2" como "parar com 2 repetições de reserva" (SPEC RF-41 d).
///
/// Só leitura: recebe o snapshot da prescrição e as séries; nada aqui escreve (R4).
@MainActor
struct SessionExerciseSection: View {
    let sessionExercise: SessionExerciseModel
    let references: ReferenceCatalog

    @Environment(\.exerciseTraits) private var traits

    init(sessionExercise: SessionExerciseModel, references: ReferenceCatalog) {
        self.sessionExercise = sessionExercise
        self.references = references
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
            NavigationLink {
                // Nome atual do catálogo quando a relação existe (o exercício pode ter sido
                // renomeado depois); senão, o nome copiado na sessão.
                ExerciseProgressView(
                    exerciseUUID: sessionExercise.exerciseUUID,
                    exerciseName: sessionExercise.exercise?.name ?? sessionExercise.exerciseName
                )
            } label: {
                Label("Evolução de carga", systemImage: "chart.line.uptrend.xyaxis")
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
                    .accessibilityLabel(prescriptionSpokenText)
                if let note = sessionExercise.note {
                    HStack(spacing: 8) {
                        Text(Self.noteText(note))
                            .font(.caption)
                        // Esconde-se sozinho quando o catálogo não tem referências para a nota.
                        WhyButton(topic: ReferenceCatalog.topic(for: note), catalog: references)
                    }
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

    /// "1 · 60 kg × 10 · RIR 2" ou "1 · 20 kg × 30 passos · RIR 2". `index` é 0-based
    /// (`SessionCoordinating.logSet`); o usuário conta a partir de 1.
    private func setLine(_ set: SetLogModel) -> String {
        "\(set.index + 1) · \(loadText(set.load)) × \(MeasureText.amount(set.reps, measure: measure)) · \(rirText(set.rir))"
    }

    /// "3 × 8–12 · 60 kg · RIR 2" ou "3 × 20–40 s · 0 kg · RIR 2"; carga `nil` (calibração,
    /// SPEC P2) vira "—".
    private var prescriptionText: String {
        let range = MeasureText.range(
            min: sessionExercise.prescribedRepMin,
            max: sessionExercise.prescribedRepMax,
            measure: measure
        )
        return "\(sessionExercise.prescribedSets) × \(range) · \(prescribedLoadText ?? "—") · RIR \(sessionExercise.prescribedRIR)"
    }

    /// Leitura por voz da prescrição (SPEC RF-41 d).
    private var prescriptionSpokenText: String {
        PrescriptionSpeech.text(
            sets: sessionExercise.prescribedSets,
            repMin: sessionExercise.prescribedRepMin,
            repMax: sessionExercise.prescribedRepMax,
            measure: measure,
            loadText: prescribedLoadText,
            targetRIR: sessionExercise.prescribedRIR
        )
    }

    /// Carga prescrita na unidade do exercício; `nil` na calibração sem carga (SPEC P2).
    private var prescribedLoadText: String? {
        sessionExercise.prescribedLoad.map { loadText($0) }
    }

    /// Repetições, segundos ou passos (SPEC RF-43); sem relação com o catálogo, repetições.
    private var measure: ExerciseMeasure {
        MeasureText.measure(of: sessionExercise.exercise, in: traits)
    }

    /// Nota da prescrição em pt-BR. Raw desconhecido nem chega aqui (`note == nil` esconde a
    /// linha: não inventa padrão).
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
