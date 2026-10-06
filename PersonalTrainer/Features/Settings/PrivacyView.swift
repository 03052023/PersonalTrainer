import SwiftUI

/// Página "Privacidade" (SPEC §7.18 L2; contrato V25 §5.3 e §6.1): o que fica no aparelho, o que o
/// app lê e grava no Saúde, o que é o arquivo de backup e para onde vão os links. Texto factual, em
/// `PrivacyText`; nenhuma promessa absoluta e nenhuma mensagem de efeito (decisão 20).
///
/// Aberta a partir da seção "Sobre" de `MoreOptionsView`, que já está dentro da `NavigationStack` do
/// `SettingsView`; por isso não traz a própria. Só leitura: nada grava e nada pede permissão.
///
/// A política e o suporte entram como `Link` só quando o endereço existe em `AppLinks`; sem ele a
/// linha some e nada provisório aparece no lugar.
struct PrivacyView: View {
    private let policyURL: URL?
    private let supportURL: URL?

    /// - Parameters:
    ///   - policyURL: o padrão é o de `AppLinks`; previews e testes podem passar outro.
    ///   - supportURL: idem.
    init(
        policyURL: URL? = AppLinks.privacyPolicyURL,
        supportURL: URL? = AppLinks.supportURL
    ) {
        self.policyURL = policyURL
        self.supportURL = supportURL
    }

    var body: some View {
        Form {
            // Papel (DESIGN §14): as linhas em `surface`, como nas outras listas da direção.
            Group {
                introSection
                deviceSection
                healthSection
                backupSection
                linksSection
            }
            .listRowBackground(Theme.surface)
        }
        // Papel (DESIGN §14): o fundo do formulário dá lugar ao papel.
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle(PrivacyText.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Seções

    /// Sem cabeçalho.
    private var introSection: some View {
        Section {
            Text(PrivacyText.intro)
        }
    }

    private var deviceSection: some View {
        Section {
            Text(PrivacyText.deviceData)
            Text(PrivacyText.deletingApp)
        } header: {
            Text(PrivacyText.deviceHeader)
        }
    }

    private var healthSection: some View {
        Section {
            Text(PrivacyText.health)
            Text(PrivacyText.healthReads)
            Text(PrivacyText.healthWrites)
        } header: {
            Text(PrivacyText.healthHeader)
        }
    }

    private var backupSection: some View {
        Section {
            Text(PrivacyText.backup)
            Text(PrivacyText.deviceBackup)
        } header: {
            Text(PrivacyText.backupHeader)
        }
    }

    private var linksSection: some View {
        Section {
            Text(PrivacyText.referenceLinks)
            if let policyURL {
                Link(destination: policyURL) {
                    Label(PrivacyText.policyLink, systemImage: "arrow.up.right.square")
                }
            }
            if let supportURL {
                Link(destination: supportURL) {
                    Label(PrivacyText.supportLink, systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text(PrivacyText.linksHeader)
        }
    }
}

#Preview("Privacidade") {
    NavigationStack {
        PrivacyView()
    }
}
