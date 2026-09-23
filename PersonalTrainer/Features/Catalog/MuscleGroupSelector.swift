import SwiftUI
import TrainerCore

/// Multi-seleção de grupos musculares em "chips" (duas ou três colunas), para caber numa linha de
/// `Form` em vez de dez linhas por lista. Não guarda estado: mostra `selected` e avisa o toque em
/// `onToggle`; a regra (ordem, exclusão entre primários e secundários) fica no ViewModel.
struct MuscleGroupSelector: View {
    private let selected: [MuscleGroup]
    private let disabled: Set<MuscleGroup>
    private let onToggle: (MuscleGroup) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    /// - Parameters:
    ///   - selected: grupos marcados (a ordem é do chamador; o primeiro primário define a seção).
    ///   - disabled: grupos exibidos esmaecidos e sem toque (ex.: já marcados como primários).
    init(
        selected: [MuscleGroup],
        disabled: Set<MuscleGroup> = [],
        onToggle: @escaping (MuscleGroup) -> Void
    ) {
        self.selected = selected
        self.disabled = disabled
        self.onToggle = onToggle
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(MuscleGroup.allCases, id: \.self) { group in
                chip(for: group)
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(for group: MuscleGroup) -> some View {
        let isSelected = selected.contains(group)
        let isDisabled = disabled.contains(group)
        return Button {
            onToggle(group)
        } label: {
            Text(group.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        // Vários botões na mesma linha de Form: sem `.borderless` a linha inteira dispararia
        // todos os botões de uma vez.
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
