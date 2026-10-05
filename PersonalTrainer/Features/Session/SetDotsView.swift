import SwiftUI
import TrainerCore

/// Uma bolinha por série do exercício (SPEC RF-44 a/b; DESIGN §13): cheia = série feita, em `accent`
/// com o número feito em `onAccent`; vazia = contorno. Desenho de 32 pt, alvo de toque de 44 pt.
///
/// Tocar numa vazia marca a próxima série como prevista (`onMark`); tocar numa cheia abre "Corrigir
/// série" (`onEdit`). Com a sessão encerrada ou o exercício pulado, as vazias ficam cinza e
/// desabilitadas (`canMark == false`); desde a 2.3, a carga nunca bloqueia (RF-44 c). View pura: quem grava é o ViewModel (AGENTS R4).
struct SetDotsView: View {
    /// Uma bolinha: `setID` e `reps` preenchidos quando a série foi feita.
    struct Dot: Identifiable, Hashable {
        /// Posição 0-based.
        let id: Int
        let setID: UUID?
        let reps: Int?

        init(id: Int, setID: UUID?, reps: Int?) {
            self.id = id
            self.setID = setID
            self.reps = reps
        }
    }

    private let dots: [Dot]
    private let measure: ExerciseMeasure
    private let canMark: Bool
    private let canEdit: Bool
    private let onMark: () -> Void
    private let onEdit: (UUID) -> Void

    init(
        dots: [Dot],
        measure: ExerciseMeasure,
        canMark: Bool,
        canEdit: Bool,
        onMark: @escaping () -> Void,
        onEdit: @escaping (UUID) -> Void
    ) {
        self.dots = dots
        self.measure = measure
        self.canMark = canMark
        self.canEdit = canEdit
        self.onMark = onMark
        self.onEdit = onEdit
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(dots) { dot in
                dotButton(dot)
            }
        }
    }

    private func dotButton(_ dot: Dot) -> some View {
        let isFilled = dot.setID != nil
        let label = SessionSheetText.dotLabel(number: dot.id + 1, total: dots.count, reps: dot.reps, measure: measure)
        let hint = isFilled ? "Toque duas vezes para corrigir a série" : ""
        return Button {
            if let setID = dot.setID {
                onEdit(setID)
            } else {
                onMark()
            }
        } label: {
            dotShape(dot)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFilled ? !canEdit : !canMark)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint))
    }

    @ViewBuilder
    private func dotShape(_ dot: Dot) -> some View {
        if let reps = dot.reps, dot.setID != nil {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                Text(String(reps))
                    .font(.system(.footnote, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 3)
            }
            .frame(width: 32, height: 32)
        } else {
            Circle()
                .strokeBorder(canMark ? Theme.accent : Theme.textSecondary.opacity(0.4), lineWidth: 2)
                .frame(width: 32, height: 32)
        }
    }
}

#Preview("Duas feitas, uma por fazer") {
    SetDotsView(
        dots: [
            SetDotsView.Dot(id: 0, setID: UUID(), reps: 3),
            SetDotsView.Dot(id: 1, setID: UUID(), reps: 3),
            SetDotsView.Dot(id: 2, setID: nil, reps: nil),
        ],
        measure: .reps,
        canMark: true,
        canEdit: true,
        onMark: {},
        onEdit: { _ in }
    )
    .padding()
    .tint(Theme.accent)
}

#Preview("Esperando a carga") {
    SetDotsView(
        dots: (0..<4).map { SetDotsView.Dot(id: $0, setID: nil, reps: nil) },
        measure: .reps,
        canMark: false,
        canEdit: true,
        onMark: {},
        onEdit: { _ in }
    )
    .padding()
}
