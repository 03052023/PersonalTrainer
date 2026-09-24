import Foundation

/// Falhas de `CoachLogStoring` ao gravar. Ler nunca falha (ver o protocolo).
enum CoachLogStoreError: Error, Equatable {
    /// A pasta Application Support/PersonalTrainer não pôde ser localizada.
    case directoryUnavailable
}
