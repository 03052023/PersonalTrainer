import SwiftUI

/// Passo a passo para renovar a instalação pelo Impactor (SPEC §7.11 C4, resposta "Como
/// renovar"). Com a conta Apple gratuita a instalação vale 7 dias; renovar é reinstalar por cima,
/// e os dados ficam.
///
/// Nunca pede nem mostra credencial: conta e senha da Apple são digitadas só no Impactor, no
/// computador (WINDOWS_SETUP §7). Apresentar em `.sheet`: a view traz a própria navegação.
struct RenewalHelpView: View {
    /// Validade atual (`CoachService.provisioningExpiry`); `nil` no simulador.
    let expiry: Date?
    /// Com valor, mostra o interruptor do aviso da véspera e devolve cada mudança (ligue a
    /// `CoachService.setExpiryReminderEnabled(_:)`, que pede a permissão ao ligar).
    let onReminderChange: ((Bool) -> Void)?

    @State private var isReminderOn: Bool
    @Environment(\.dismiss) private var dismiss

    init(expiry: Date?, isReminderEnabled: Bool = false, onReminderChange: ((Bool) -> Void)? = nil) {
        self.expiry = expiry
        self.onReminderChange = onReminderChange
        self._isReminderOn = State(initialValue: isReminderEnabled)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(validityText)
                    Text("Renovar é instalar o Magister de novo por cima do que já está no iPhone. Suas sessões, programas e ajustes continuam aqui.")
                        .foregroundStyle(.secondary)
                }

                Section("Passo a passo") {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .fontDesign(.rounded)
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                                .frame(minWidth: 20, alignment: .leading)
                            Text(step)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if onReminderChange != nil {
                    Section {
                        Toggle("Avisar na véspera, às 10h", isOn: $isReminderOn)
                    } footer: {
                        Text("Na primeira vez, o iPhone pergunta se o Magister pode mandar notificações.")
                    }
                }

                Section {
                    Label {
                        Text("O Magister nunca pede sua conta Apple nem sua senha. Elas são digitadas só no Impactor, no computador.")
                    } icon: {
                        Image(systemName: "lock")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Como renovar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .onChange(of: isReminderOn) { _, newValue in
                onReminderChange?(newValue)
            }
        }
    }

    /// Frase da validade, com data e hora no formato do Brasil.
    private var validityText: String {
        guard let expiry else {
            return "Não foi possível ler a validade desta instalação. Ela costuma durar 7 dias a partir da última instalação."
        }
        let style = Date.FormatStyle(locale: Locale(identifier: "pt_BR"), calendar: .current, timeZone: .current)
            .day()
            .month(.wide)
            .hour()
            .minute()
        return "A instalação atual vale até \(expiry.formatted(style))."
    }

    /// Os passos, em frases curtas (DESIGN §6). Sem nomes de botões do Impactor, que podem mudar
    /// entre versões.
    static let steps: [String] = [
        "Se quiser uma garantia extra, faça antes um backup em Ajustes. Reinstalar por cima não apaga nada.",
        "No computador, abra o Impactor e conecte o iPhone pelo cabo. Se o iPhone perguntar, toque em Confiar.",
        "No Impactor, escolha o arquivo do Magister (.ipa): o mesmo da última instalação ou uma versão mais nova.",
        "Instale por cima do app que já está no iPhone. Não apague o app antes: é isso que mantém seus dados.",
        "Se o Impactor pedir sua conta Apple, digite só nele.",
        "Abra o Magister. A nova instalação vale por mais 7 dias.",
    ]
}

#Preview("Como renovar") {
    RenewalHelpView(
        expiry: Date(timeIntervalSince1970: 1_790_380_800),
        isReminderEnabled: false,
        onReminderChange: { _ in }
    )
}

#Preview("Como renovar — sem data") {
    RenewalHelpView(expiry: nil)
}
