import Foundation

/// Por que uma ação do diálogo não pôde ser aplicada (SPEC §7.11). Em todos os casos nada foi
/// gravado no log: a mensagem continua no feed e a pessoa pode responder de outro jeito.
enum CoachServiceError: Error, Equatable {
    /// A sugestão da revisão não está mais no relatório guardado.
    case suggestionNotFound
    /// Os exercícios que a sugestão muda não estão mais no programa ativo (ele foi editado ou
    /// trocado depois da revisão).
    case suggestionOutdated
    /// Nenhum exercício do catálogo serve de substituto (RF-34).
    case noSubstitute
}
