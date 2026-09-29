import SwiftUI
import TrainerCore

/// Uma `Section` de `SessionDetailView` por exercício da sessão (SPEC F5, CA1-7):
/// cabeçalho com nome, a meta de hoje em palavras ("3 séries de 10 · 60 kg", RF-41, RF-46), o
/// selo leigo da nota com "Por quê?" (RF-32, só com novidade) e badge "Pulado"; uma linha por
/// série ("1 · 60 kg × 10"; peso do corpo sem carga: "1 · 10 repetições"), aquecimentos antigos
/// marcados "Aquecimento", ordenadas por `index`; e por fim o link para a evolução de carga do
/// exercício (T2.10).
///
/// Desde a 2.2 (`docs/V22-CONTRACT.md` §3.7): nada de RIR em texto nem na leitura do VoiceOver
/// (SPEC RF-41, decisão 18) — o dado continua na série (`SetLogModel.rir`), só não aparece aqui.
/// A prescrição e o selo vêm das funções compartilhadas `TodayTargetText` e `PrescriptionNote.badgeText`
/// (`docs/V22-CONTRACT.md` §2.3), as mesmas da Home, da ficha da sessão e da folha de informações.
///
/// A medida do exercício (SPEC RF-43), lida de `\.exerciseTraits` pelo `slug`, dá a unidade da
/// faixa e das séries ("3 séries de 20–40 s", "1 · 30 s").
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
                // Selo leigo (RF-41, decisão 18): some sozinho em `hold` ("Manter" não tem selo).
                if let note = sessionExercise.note, let badge = note.badgeText {
                    HStack(spacing: 8) {
                        Text(badge)
                            .font(.caption)
                        // Esconde-se sozinho quando o catálogo não tem referências para a nota.
                        WhyButton(topic: ReferenceCatalog.topic(for: note), catalog: references)
                    }
                }
            }
            // Cabeçalho de lista vem em caixa alta por padrão; nomes de exercício não.
            .textCase(nil)
        }
        .listRowBackground(Theme.surface)
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

    /// "1 · 60 kg × 10", "1 · 20 kg × 30 passos"; peso do corpo sem carga extra (SPEC RF-46):
    /// "1 · 10 repetições", por extenso, sem "0 kg" nem "—". `index` é 0-based
    /// (`SessionCoordinating.logSet`); o usuário conta a partir de 1. Nada de RIR (SPEC RF-41,
    /// decisão 18): o valor gravado na série continua intacto, só não aparece aqui.
    static func setLineText(
        index: Int,
        load: Double,
        reps: Int,
        measure: ExerciseMeasure,
        unit: LoadUnit,
        equipment: Equipment?
    ) -> String {
        let display = TodayTargetText.loadDisplay(load: load, unit: unit, equipment: equipment)
        guard let label = TodayTargetText.loadLabel(display) else {
            return "\(index + 1) · \(TodayTargetText.amount(reps, measure: measure))"
        }
        return "\(index + 1) · \(label) × \(MeasureText.amount(reps, measure: measure))"
    }

    private func setLine(_ set: SetLogModel) -> String {
        Self.setLineText(index: set.index, load: set.load, reps: set.reps, measure: measure, unit: loadUnit, equipment: equipment)
    }

    /// Meta de hoje em palavras, via `TodayTargetText.row` (a mesma função da Home, da ficha da
    /// sessão e da folha de informações; `docs/V22-CONTRACT.md` §2.3): "3 séries de 10 · 60 kg",
    /// "3 séries de 5" (peso do corpo sem carga, SPEC RF-46), "2 séries de 15 s". Carga `nil`
    /// (calibração, SPEC P2) mostra "escolha a carga". Nada de RIR (SPEC RF-41).
    static func prescriptionRowText(
        sets: Int,
        targetReps: Int,
        repMin: Int,
        measure: ExerciseMeasure,
        load: Double?,
        unit: LoadUnit,
        equipment: Equipment?
    ) -> String {
        let goal = TodayTargetText.goal(targetReps: targetReps, repMin: repMin)
        let display = TodayTargetText.loadDisplay(load: load, unit: unit, equipment: equipment)
        return TodayTargetText.row(sets: sets, goal: goal, measure: measure, load: display)
    }

    private var prescriptionText: String {
        Self.prescriptionRowText(
            sets: sessionExercise.prescribedSets,
            targetReps: sessionExercise.prescribedTargetReps,
            repMin: sessionExercise.prescribedRepMin,
            measure: measure,
            load: sessionExercise.prescribedLoad,
            unit: loadUnit,
            equipment: equipment
        )
    }

    /// Leitura do VoiceOver da meta de hoje, sem RIR (SPEC RF-41 d, desde a 2.2).
    private var prescriptionSpokenText: String {
        let goal = TodayTargetText.goal(targetReps: sessionExercise.prescribedTargetReps, repMin: sessionExercise.prescribedRepMin)
        let display = TodayTargetText.loadDisplay(load: sessionExercise.prescribedLoad, unit: loadUnit, equipment: equipment)
        return TodayTargetText.spokenRow(sets: sessionExercise.prescribedSets, goal: goal, measure: measure, load: display)
    }

    /// Repetições, segundos ou passos (SPEC RF-43); sem relação com o catálogo, repetições.
    private var measure: ExerciseMeasure {
        MeasureText.measure(of: sessionExercise.exercise, in: traits)
    }

    /// A unidade vem do catálogo relacionado; se a relação foi anulada, assume kg
    /// (o único caso em que o snapshot não basta para formatar).
    private var loadUnit: LoadUnit {
        sessionExercise.exercise?.loadUnit ?? .kilograms
    }

    /// `nil` quando a relação com o catálogo foi anulada; `TodayTargetText.loadDisplay` trata
    /// como exercício com carga (não peso do corpo), a mesma convenção de `loadUnit`.
    private var equipment: Equipment? {
        sessionExercise.exercise?.equipment
    }
}
