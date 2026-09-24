import Foundation

/// Minutos aeróbicos de um dia da semana corrente (SPEC §7.10 A1), para o gráfico do detalhe.
public struct DailyAerobicMinutes: Codable, Sendable, Hashable {
    /// Início do dia (00:00 no calendário do usuário).
    public let day: Date
    public let moderate: Int
    public let vigorous: Int

    public init(day: Date, moderate: Int, vigorous: Int) {
        self.day = day
        self.moderate = moderate
        self.vigorous = vigorous
    }
}
