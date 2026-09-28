import SwiftUI
import TrainerCore

/// A folha "Como fazer" (SPEC RF-40, §7.12; DESIGN §12 e §13): o nome em New York, "Trabalha: …", a figura animada
/// com Pausar e Continuar (ou os quadros parados, com Reduzir Movimento e nas guias `static`), as legendas, os 3
/// passos e os 2 erros comuns. Fundo de papel.
///
/// Para o VoiceOver, a figura é um elemento só com a descrição da guia, seguido dos passos e dos erros; os textos
/// seguem o Dynamic Type. A animação para ao fechar a folha (a view sai da tela), com Pausar e com Reduzir
/// Movimento (SPEC E7).
struct ExerciseGuideSheet: View {
    private let figure: GuideFigure
    private let exerciseName: String
    private let worksLine: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var isPaused = false

    init(guide: ExerciseGuide, exerciseName: String, primaryMuscles: [MuscleGroup]) {
        self.figure = GuideFigure(guide: guide)
        self.exerciseName = exerciseName
        self.worksLine = ExerciseGuideText.worksLine(guide: guide, primaryMuscles: primaryMuscles)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    illustration
                    stepsSection
                    mistakesSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ExerciseGuideText.close) {
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - Partes

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exerciseName)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let worksLine {
                Text(worksLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Parado com Reduzir Movimento ou numa guia `static` (SPEC E7).
    private var showsStillFrames: Bool {
        reduceMotion || !figure.animates
    }

    private var illustration: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsStillFrames {
                GuideStaticFramesView(figure: figure)
            } else {
                GuideIllustrationView(figure: figure, isPaused: isPaused)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                pauseButton
                captions
            }
        }
        .padding(12)
        .inkCard()
    }

    private var pauseButton: some View {
        Button {
            isPaused.toggle()
        } label: {
            Label(
                isPaused ? ExerciseGuideText.resume : ExerciseGuideText.pause,
                systemImage: isPaused ? "play.fill" : "pause.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.accentSoft, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// As legendas numeradas dos quadros, na ordem do movimento. A figura já é descrita ao VoiceOver.
    private var captions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(figure.guide.frames.enumerated()), id: \.offset) { pair in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    numberBadge(pair.offset + 1)
                    Text(pair.element.caption)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(ExerciseGuideText.stepsTitle)
            ForEach(Array(figure.guide.steps.enumerated()), id: \.offset) { pair in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    numberBadge(pair.offset + 1)
                        .accessibilityHidden(true)
                    Text(pair.element)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "o erro: o que fazer": o erro em semibold e a correção em regular (SPEC E2).
    private var mistakesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(ExerciseGuideText.mistakesTitle)
            ForEach(Array(figure.guide.mistakes.enumerated()), id: \.offset) { pair in
                let parts = ExerciseGuideText.mistakeParts(pair.element)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parts.mistake)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let fix = parts.fix {
                            Text(fix)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .serif))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func numberBadge(_ number: Int) -> some View {
        Text(String(number))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(minWidth: 24, minHeight: 24)
            .background(Theme.accentSoft, in: Circle())
    }
}

#if DEBUG
#Preview("Como fazer — agachamento") {
    let catalog = ExerciseGuideLibrary.load(bundle: .main)
    if let guide = catalog.guide(forSlug: "barbell-back-squat") {
        ExerciseGuideSheet(guide: guide, exerciseName: "Agachamento livre", primaryMuscles: [.quads, .glutes])
    } else {
        Text("Guia indisponível")
    }
}

#Preview("Como fazer — caminhada (parada)") {
    let catalog = ExerciseGuideLibrary.load(bundle: .main)
    if let guide = catalog.guide(forSlug: "brisk-walk") {
        ExerciseGuideSheet(guide: guide, exerciseName: "Caminhada rápida", primaryMuscles: [.quads, .glutes])
    } else {
        Text("Guia indisponível")
    }
}
#endif
