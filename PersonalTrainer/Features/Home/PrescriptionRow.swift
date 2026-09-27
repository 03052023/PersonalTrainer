import SwiftUI
import TrainerCore

/// Uma linha do cartão da Home (SPEC RF-01, RF-45, RF-46; DESIGN §9; docs/V22-CONTRACT.md §3.3):
/// número, nome, o selo leigo da nota (botão próprio, que abre o "Por quê?") e a meta de hoje em
/// palavras ("3 séries de 3 · 62,5 kg"; peso do corpo sem carga). Sem RIR nem descanso: eles
/// ficam só na ficha da sessão e na folha "Informações do exercício".
///
/// Tocar na linha (nome + meta) abre a folha de informações, por `onSelect`; quem apresenta a
/// folha é a `HomeView` (`.sheet(item:)`), com `HomeViewModel.infoContent(for:measure:)`. O selo é
/// um botão separado, lado a lado com o resto da linha — nunca dentro do rótulo de outro botão,
/// porque botões aninhados não funcionam no SwiftUI (docs/V22-CONTRACT.md §1.4) — para continuar
/// acionável sozinho no VoiceOver.
/// View pura: só formata o `PlannedExercise`; nada de coordinator ou SwiftData.
struct PrescriptionRow: View {
    /// Posição no plano (0-based); a linha mostra `index + 1`.
    let index: Int
    let exercise: PlannedExercise
    let references: ReferenceCatalog
    let onSelect: () -> Void

    @Environment(\.exerciseTraits) private var traits

    init(
        index: Int,
        exercise: PlannedExercise,
        references: ReferenceCatalog,
        onSelect: @escaping () -> Void
    ) {
        self.index = index
        self.exercise = exercise
        self.references = references
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 18, alignment: .leading)
                // O número é só ordem visual; o rótulo falado já diz "Exercício N".
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.exercise.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.rowText(for: exercise, measure: measure))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(Self.spokenRowLabel(index: index, exercise: exercise, measure: measure)))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Abre as informações do exercício"))

            Spacer(minLength: 8)

            if let badgeText = exercise.prescription.note.badgeText {
                NoteBadgeButton(
                    text: badgeText,
                    topic: ReferenceCatalog.topic(for: exercise.prescription.note),
                    catalog: references
                )
            }
        }
        // O alvo de toque é a linha inteira (menos o selo, que é o próprio botão do "Por quê?"):
        // o selo, por estar mais dentro na árvore, continua ganhando o toque sobre ele.
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /// Repetições, segundos ou passos (SPEC RF-43). Personalizado sempre em repetições.
    private var measure: ExerciseMeasure {
        traits.traits(for: exercise.exercise).measure
    }

    // MARK: - Formatação (pt-BR, docs/V22-CONTRACT.md §2.3)

    /// "3 séries de 3 · 62,5 kg", peso do corpo sem carga "3 séries de 5" (SPEC RF-46).
    static func rowText(for exercise: PlannedExercise, measure: ExerciseMeasure = .reps) -> String {
        TodayTargetText.row(
            sets: exercise.prescription.sets,
            goal: goal(for: exercise),
            measure: measure,
            load: loadDisplay(for: exercise)
        )
    }

    /// Leitura por voz da meta: "3 séries de 3 repetições, 62,5 kg".
    static func spokenRowText(for exercise: PlannedExercise, measure: ExerciseMeasure = .reps) -> String {
        TodayTargetText.spokenRow(
            sets: exercise.prescription.sets,
            goal: goal(for: exercise),
            measure: measure,
            load: loadDisplay(for: exercise)
        )
    }

    private static func goal(for exercise: PlannedExercise) -> Int {
        TodayTargetText.goal(targetReps: exercise.prescription.targetReps, repMin: exercise.prescription.repMin)
    }

    private static func loadDisplay(for exercise: PlannedExercise) -> TodayTargetText.LoadDisplay {
        TodayTargetText.loadDisplay(
            load: exercise.prescription.load,
            unit: exercise.exercise.loadUnit,
            equipment: exercise.exercise.equipment
        )
    }

    /// "Exercício 2, Agachamento livre. 3 séries de 3 repetições, 62,5 kg."
    private static func spokenRowLabel(index: Int, exercise: PlannedExercise, measure: ExerciseMeasure) -> String {
        "Exercício \(index + 1), \(exercise.exercise.name). \(spokenRowText(for: exercise, measure: measure))."
    }
}

/// Selo leigo da nota (DESIGN §7, §9.5): pílula em `accentSoft`/`accent` que já é o botão do
/// "Por quê?" — sem link separado. Some quando o catálogo não tem referência para a nota
/// (inclusive `ReferenceCatalog.empty`), igual ao `WhyButton`, para nunca abrir uma folha vazia.
/// Privado ao arquivo: só a linha o usa.
private struct NoteBadgeButton: View {
    let text: String
    let topic: String
    let catalog: ReferenceCatalog

    @State private var isShowingSheet = false

    var body: some View {
        if !catalog.references(for: topic).isEmpty {
            Button {
                isShowingSheet = true
            } label: {
                HStack(spacing: 3) {
                    Text(text)
                    Image(systemName: "questionmark.circle")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accentSoft, in: Capsule())
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Novidade: \(text)"))
            .accessibilityHint(Text("Mostra a explicação e as referências científicas"))
            .sheet(isPresented: $isShowingSheet) {
                WhySheet(topic: topic, catalog: catalog)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
