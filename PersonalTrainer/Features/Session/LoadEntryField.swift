import SwiftUI

/// Campo da carga de hoje no teclado decimal (SPEC RF-44 b/c, P10; DESIGN §13): na primeira vez com
/// carga e quando a pessoa toca na carga sublinhada da ficha. Aceita vírgula ou ponto; cada valor
/// válido vai para `onChange` na hora (as bolinhas acordam assim que há carga) e um campo vazio ou
/// inválido devolve `nil`. Nada é gravado aqui: a carga só vira dado quando uma bolinha é marcada.
///
/// O foco é da ficha (`FocusState<UUID?>`), para o botão "OK" da barra do teclado fechar qualquer
/// campo. `autoFocus` abre o teclado ao aparecer (troca de carga); na primeira vez, a pessoa toca
/// no campo.
struct LoadEntryField: View {
    private let exerciseID: UUID
    private let title: String
    private let unitLabel: String
    private let placeholder: String
    private let allowsZero: Bool
    private let focus: FocusState<UUID?>.Binding
    private let autoFocus: Bool
    private let onChange: (Double?) -> Void

    @State private var text: String

    init(
        exerciseID: UUID,
        title: String,
        unitLabel: String,
        placeholder: String,
        initialValue: Double?,
        allowsZero: Bool,
        focus: FocusState<UUID?>.Binding,
        autoFocus: Bool,
        onChange: @escaping (Double?) -> Void
    ) {
        self.exerciseID = exerciseID
        self.title = title
        self.unitLabel = unitLabel
        self.placeholder = placeholder
        self.allowsZero = allowsZero
        self.focus = focus
        self.autoFocus = autoFocus
        self.onChange = onChange
        self._text = State(initialValue: initialValue.map { SessionSheetText.editableLoadText($0) } ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .focused(focus, equals: exerciseID)
                    .accessibilityLabel(Text("\(title) de hoje, em \(unitLabel)"))

                Text(unitLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            )
        }
        .onChange(of: text) { _, newValue in
            onChange(SessionSheetText.parseLoad(newValue, allowsZero: allowsZero))
        }
        .onAppear {
            guard autoFocus else {
                return
            }
            // O foco só pega depois que o campo entra na tela; pedir no mesmo ciclo do
            // `onAppear` às vezes não abre o teclado.
            Task { @MainActor in
                focus.wrappedValue = exerciseID
            }
        }
    }
}
