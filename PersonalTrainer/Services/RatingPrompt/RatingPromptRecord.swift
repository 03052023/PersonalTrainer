import Foundation

/// O último pedido de avaliação (SPEC §7.18 L3): a versão do app (`CFBundleShortVersionString`) e a data
/// em que o app chamou a caixa do sistema. É tudo o que o app guarda sobre a avaliação; o iOS não conta se
/// a caixa apareceu, então isto registra o pedido, não a exibição.
struct RatingPromptRecord: Equatable, Sendable {
    let version: String
    let date: Date
}
