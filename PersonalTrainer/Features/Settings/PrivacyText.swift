import Foundation

/// Os textos da página "Privacidade" e da seção "Sobre" (SPEC §7.18 L2, L3 e L5; contrato V25
/// §6.1 e §6.2), todos num lugar só para a `PrivacyView`, a `MoreOptionsView` e os testes.
///
/// São informação, não mensagem de efeito (decisão 20): dizem só o que dá para provar, sem promessa
/// absoluta, e nunca sugerem um serviço de nuvem para o arquivo de backup (diretriz 5.1.3(ii)).
/// `all` lista cada texto para o teste que varre as palavras proibidas.
enum PrivacyText {
    // MARK: - Página "Privacidade"

    static let title = "Privacidade"

    /// Sem cabeçalho de seção.
    static let intro = "O Magister não coleta dados: não tem conta, anúncios, rastreamento nem ferramentas de análise. Quem fez o app não recebe nada do que você registra."

    static let deviceHeader = "No iPhone"
    static let deviceData = "Seus treinos, planos, atividades e ajustes ficam no iPhone."
    static let deletingApp = "Apagar o app apaga os dados dele no iPhone. Os treinos já gravados no app Saúde ficam lá até você apagá-los no Saúde."

    static let healthHeader = "App Saúde"
    static let health = "O Magister lê e grava só se você permitir e usa esses dados apenas no aparelho. Para mudar, vá em Ajustes do iPhone › Saúde › Acesso a Dados e Dispositivos."
    static let healthReads = "Lê: treinos, frequência cardíaca, VO2máx, variabilidade da frequência cardíaca, frequência cardíaca em repouso, sono, passos, data de nascimento e sexo (os dois últimos são opcionais)."
    static let healthWrites = "Grava: cada sessão concluída, as de força como treino de força e as de aeróbico como treino aeróbico."

    static let backupHeader = "Backup"
    static let backup = "O arquivo só é criado quando você pede e vai para onde você escolher. Ele traz seus treinos e alguns dados de saúde, como a frequência cardíaca média. Guarde-o num lugar só seu."
    static let deviceBackup = "Se o backup do iPhone no iCloud estiver ligado, a Apple inclui os dados do app nele, como faz com qualquer app."

    static let linksHeader = "Links"
    /// O `Link` abre no navegador padrão da pessoa, que pode não ser o Safari.
    static let referenceLinks = "Os links das referências abrem no navegador do iPhone."
    /// Rótulos dos `Link`, que só aparecem com a URL em `AppLinks`.
    static let policyLink = "Política de privacidade"
    static let supportLink = "Suporte"

    // MARK: - Seção "Sobre"

    static let aboutPrivacy = "Privacidade"
    /// Só aparece com o ID do app na loja (`AppLinks.writeReviewURL`).
    static let rateApp = "Avaliar o Magister"
    /// L5: a única linha de aviso de saúde, fixa no rodapé do "Sobre".
    static let healthNotice = "O Magister não substitui a orientação de um médico ou de um profissional de educação física."

    // MARK: - Todos

    /// Cada texto acima, na ordem em que aparece, para os testes.
    static let all: [String] = [
        title,
        intro,
        deviceHeader,
        deviceData,
        deletingApp,
        healthHeader,
        health,
        healthReads,
        healthWrites,
        backupHeader,
        backup,
        deviceBackup,
        linksHeader,
        referenceLinks,
        policyLink,
        supportLink,
        aboutPrivacy,
        rateApp,
        healthNotice,
    ]
}
