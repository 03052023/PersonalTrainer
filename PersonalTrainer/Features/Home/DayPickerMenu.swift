import SwiftUI
import TrainerCore

/// Nome do dia no card da Home como menu (SPEC S4, TASKS T2.14): lista os dias do programa
/// ativo e o item "Automático (próximo da rotação)". View pura: só devolve a escolha pelos
/// fechamentos; quem planeja é o `HomeViewModel`.
///
/// Com menos de dois dias (ou dias ainda não carregados) não há o que escolher e o nome
/// aparece como texto simples, sem menu.
struct DayPickerMenu: View {
    let dayName: String
    let days: [ProgramDayTemplate]
    /// `nil` = automático; senão, o dia escolhido à mão (marcado no menu).
    let selectedDayID: UUID?
    let isEnabled: Bool
    let onSelectDay: (UUID) -> Void
    let onSelectAutomatic: () -> Void

    init(
        dayName: String,
        days: [ProgramDayTemplate],
        selectedDayID: UUID?,
        isEnabled: Bool = true,
        onSelectDay: @escaping (UUID) -> Void,
        onSelectAutomatic: @escaping () -> Void
    ) {
        self.dayName = dayName
        self.days = days
        self.selectedDayID = selectedDayID
        self.isEnabled = isEnabled
        self.onSelectDay = onSelectDay
        self.onSelectAutomatic = onSelectAutomatic
    }

    var body: some View {
        if days.count < 2 {
            title
        } else {
            Menu {
                Button {
                    onSelectAutomatic()
                } label: {
                    itemLabel("Automático (próximo da rotação)", isSelected: selectedDayID == nil)
                }
                Divider()
                ForEach(Self.sorted(days), id: \.id) { day in
                    Button {
                        onSelectDay(day.id)
                    } label: {
                        itemLabel(day.name, isSelected: day.id == selectedDayID)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .disabled(!isEnabled)
            .accessibilityLabel(Text("Dia do treino: \(dayName)"))
            .accessibilityHint(Text("Toque para escolher outro dia do programa."))
        }
    }

    private var title: some View {
        Text(dayName)
            .font(.largeTitle.weight(.bold))
            // O rótulo de um `Menu` herda a cor de destaque; o título continua na cor do texto.
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private func itemLabel(_ text: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    /// Ordem do programa (`order`), como a rotação (SPEC S1); desempate por nome para ser estável.
    static func sorted(_ days: [ProgramDayTemplate]) -> [ProgramDayTemplate] {
        days.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.name < rhs.name
        }
    }
}
