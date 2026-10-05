import Foundation

/// Tudo o que a decisão do pedido de avaliação precisa (SPEC §7.18 L3), já calculado: as contagens vêm do
/// histórico, a versão e a data do último pedido vêm do que o app guardou, e "veio da loja" vem do app.
/// Nenhum relógio aqui: `now` é parâmetro de `RatingPromptPolicy.shouldRequest` (AGENTS R3).
public struct RatingPromptInput: Sendable, Equatable {
    /// Início da primeira sessão concluída do histórico (L3 a); `nil` sem nenhuma.
    public var firstCompletedSessionStart: Date?
    /// Sessões concluídas do histórico, incluindo a que acabou de terminar (L3 b).
    public var completedSessionCount: Int
    /// Como terminou a sessão que acabou de fechar (L3 c).
    public var sessionEnding: RatingSessionEnding
    /// `CFBundleShortVersionString` do app (L7).
    public var currentVersion: String
    /// Versão em que o app pediu pela última vez (L3 d); `nil` se nunca pediu.
    public var lastRequestVersion: String?
    /// Data do último pedido (L3 d); `nil` se nunca pediu.
    public var lastRequestAt: Date?
    /// O app veio da App Store: sem perfil de provisionamento embutido e fora do simulador.
    public var isStoreInstall: Bool

    public init(
        firstCompletedSessionStart: Date?,
        completedSessionCount: Int,
        sessionEnding: RatingSessionEnding,
        currentVersion: String,
        lastRequestVersion: String?,
        lastRequestAt: Date?,
        isStoreInstall: Bool
    ) {
        self.firstCompletedSessionStart = firstCompletedSessionStart
        self.completedSessionCount = completedSessionCount
        self.sessionEnding = sessionEnding
        self.currentVersion = currentVersion
        self.lastRequestVersion = lastRequestVersion
        self.lastRequestAt = lastRequestAt
        self.isStoreInstall = isStoreInstall
    }
}
