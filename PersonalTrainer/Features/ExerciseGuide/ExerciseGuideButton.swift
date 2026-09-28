import SwiftUI
import TrainerCore

/// O botão "Como fazer" (`play.circle`, `accent`; SPEC RF-40 e E1; DESIGN §12 e §13), que abre a folha da guia. Quem
/// usa só o mostra quando existe guia para o exercício (`ExerciseGuideText.guide(forSlug:isCustom:in:)`): na ficha
/// da sessão, ao lado do nome (`compact`, só o símbolo); na folha "Informações do exercício" e no catálogo, com o
/// texto (`full`).
///
/// Apresenta a folha por conta própria, como o `WhyButton`: quem usa não guarda estado.
struct ExerciseGuideButton: View {
    enum Style: Sendable, Hashable {
        /// Símbolo e texto.
        case full
        /// Só o símbolo, com alvo de toque de 44 pt; o VoiceOver lê "Como fazer: <exercício>".
        case compact
    }

    private let guide: ExerciseGuide
    private let exerciseName: String
    private let primaryMuscles: [MuscleGroup]
    private let style: Style

    @State private var isShowingSheet = false

    init(guide: ExerciseGuide, exerciseName: String, primaryMuscles: [MuscleGroup], style: Style = .full) {
        self.guide = guide
        self.exerciseName = exerciseName
        self.primaryMuscles = primaryMuscles
        self.style = style
    }

    var body: some View {
        Button {
            isShowingSheet = true
        } label: {
            label
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(ExerciseGuideText.buttonAccessibilityLabel(exerciseName: exerciseName)))
        .accessibilityHint(Text("Mostra o movimento, os passos e os erros comuns"))
        .sheet(isPresented: $isShowingSheet) {
            ExerciseGuideSheet(guide: guide, exerciseName: exerciseName, primaryMuscles: primaryMuscles)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .full:
            Label(ExerciseGuideText.buttonTitle, systemImage: ExerciseGuideText.buttonSymbol)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        case .compact:
            Image(systemName: ExerciseGuideText.buttonSymbol)
                .font(.title3.weight(.light))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}
