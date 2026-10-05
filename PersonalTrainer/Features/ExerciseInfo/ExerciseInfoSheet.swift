import SwiftUI
import TrainerCore

/// Folha de leitura "Informações do exercício" (SPEC RF-47; DESIGN §13; docs/V22-CONTRACT.md §2.2,
/// §3.2), aberta ao tocar no nome do exercício na tela Hoje e na ficha da sessão.
///
/// Andaime do arquiteto: a assinatura do `init` é o contrato entre as tarefas `home`, `session` e
/// `exercise-info`; o conteúdo completo (hoje, por que esta carga, da última vez, notas da máquina
/// e as ações) é desta tarefa. As frases vêm de `ExerciseInfoText`, não do `body` (contrato §3.2).
///
/// As ações só aparecem quando quem apresenta passa o fechamento: a Home não passa nenhum; a ficha
/// passa "Trocar" só antes da primeira série do exercício (SPEC RF-34) e "Pular" enquanto ele não
/// foi pulado. A folha só chama o fechamento: fechar a folha e fazer a ação é de quem apresenta.
struct ExerciseInfoSheet: View {
    private let content: ExerciseInfoContent
    private let references: ReferenceCatalog
    private let onSubstitute: (() -> Void)?
    private let onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// Guias do "Como fazer" (SPEC RF-40, RF-47 desde a 2.3): a seção só aparece quando o exercício tem guia (E1).
    @Environment(\.exerciseGuides) private var guides

    init(
        content: ExerciseInfoContent,
        references: ReferenceCatalog,
        onSubstitute: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil
    ) {
        self.content = content
        self.references = references
        self.onSubstitute = onSubstitute
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    title

                    ExerciseInfoSectionCard(title: "Hoje") {
                        Text(ExerciseInfoText.today(content))
                    }

                    ExerciseInfoSectionCard(title: ExerciseInfoText.whyTitle(content)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ExerciseInfoText.why(content))
                            WhyButton(topic: ReferenceCatalog.topic(for: content.note), catalog: references)
                        }
                    }

                    if let lastSession = content.lastSession {
                        ExerciseInfoSectionCard(title: ExerciseInfoText.lastTimeTitle(lastSession)) {
                            Text(ExerciseInfoText.lastTime(
                                lastSession,
                                unit: content.loadUnit,
                                equipment: content.equipment,
                                measure: content.measure
                            ))
                        }
                    }

                    if let machineNotes = content.machineNotes, !machineNotes.isEmpty {
                        ExerciseInfoSectionCard(title: "Notas da máquina") {
                            Text(machineNotes)
                        }
                    }

                    // SPEC RF-47 (2.3): é assim que a tela Hoje chega à guia; na sessão vale o exercício realizado.
                    if let guide = ExerciseGuideText.guide(forSlug: content.slug, isCustom: content.isCustom, in: guides) {
                        ExerciseInfoSectionCard(title: ExerciseGuideText.sectionTitle) {
                            ExerciseGuideButton(
                                guide: guide,
                                exerciseName: content.name,
                                primaryMuscles: content.primaryMuscles,
                                style: .full
                            )
                        }
                    }

                    if onSubstitute != nil || onSkip != nil {
                        actions
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    /// DESIGN §5/§13: título da folha em New York.
    private var title: some View {
        Text(content.name)
            .font(.system(.title2, design: .serif, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// "Máquina ocupada? Trocar por outro parecido" e "Pular este exercício", em `accent`, nunca
    /// vermelho (DESIGN §13). Fora das seções em `surface`: não é conteúdo de leitura, é ação.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let onSubstitute {
                Button("Máquina ocupada? Trocar por outro parecido", action: onSubstitute)
            }
            if let onSkip {
                Button("Pular este exercício", action: onSkip)
            }
        }
        .foregroundStyle(Theme.accent)
        .fontWeight(.medium)
    }
}

/// Cartão de seção em `surface`, com o rótulo em New York (DESIGN §5, "títulos de seção").
private struct ExerciseInfoSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inkCard()
    }
}

#Preview("Informações do exercício — com histórico") {
    Text("Hoje")
        .sheet(isPresented: .constant(true)) {
            ExerciseInfoSheet(
                content: .previewSquat,
                references: WhySheet.previewCatalog,
                onSubstitute: {},
                onSkip: {}
            )
        }
}

#Preview("Informações do exercício — primeira vez, peso do corpo") {
    Text("Hoje")
        .sheet(isPresented: .constant(true)) {
            ExerciseInfoSheet(content: .previewPushUpFirstTime, references: WhySheet.previewCatalog)
        }
}

extension ExerciseInfoContent {
    fileprivate static let previewSquat = ExerciseInfoContent(
        id: UUID(),
        exerciseID: UUID(),
        name: "Agachamento livre",
        equipment: .barbell,
        loadUnit: .kilograms,
        measure: .reps,
        machineNotes: nil,
        sets: 3,
        targetReps: 3,
        repMin: 3,
        repMax: 5,
        targetRIR: 2,
        load: 62.5,
        restSeconds: 240,
        note: .increase,
        lastSession: ExerciseLastSession(
            sessionID: UUID(),
            date: Date(timeIntervalSince1970: 1_695_400_000),
            sets: [
                SetResult(load: 60, reps: 5, completedAt: Date()),
                SetResult(load: 60, reps: 5, completedAt: Date()),
                SetResult(load: 60, reps: 5, completedAt: Date()),
            ],
            wasDeload: false
        )
    )

    fileprivate static let previewPushUpFirstTime = ExerciseInfoContent(
        id: UUID(),
        exerciseID: UUID(),
        name: "Flexão",
        equipment: .bodyweight,
        loadUnit: .kilograms,
        measure: .reps,
        machineNotes: nil,
        sets: 3,
        targetReps: 8,
        repMin: 8,
        repMax: 12,
        targetRIR: 3,
        load: nil,
        restSeconds: 90,
        note: .calibrate,
        lastSession: nil
    )
}
