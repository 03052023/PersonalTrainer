import Foundation

/// SPEC §7.18 L3 (AGENTS R9). Live: UserDefaults + bundle; Fake: memória.
///
/// Guarda a versão e a data do último pedido de avaliação e diz se o app veio da loja e em que versão
/// está. As contagens da L3 não ficam aqui: vêm do histórico (`SessionPlanning`). Quem lê e grava é o
/// `RatingPromptGate`; nenhuma view grava aqui direto.
protocol RatingPromptStoring: AnyObject {
    /// O último pedido gravado, ou `nil` se o app nunca pediu.
    func lastRequest() -> RatingPromptRecord?
    /// Substitui o último pedido por `record`.
    func recordRequest(_ record: RatingPromptRecord)
    /// O app veio da App Store. Fora dela (cópia de teste, build de desenvolvimento, simulador) nunca pede.
    var isStoreInstall: Bool { get }
    /// `CFBundleShortVersionString` do app (SPEC L7); vazio se faltar.
    var currentVersion: String { get }
}
