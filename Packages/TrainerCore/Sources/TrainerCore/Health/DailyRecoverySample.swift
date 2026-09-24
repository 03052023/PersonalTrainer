import Foundation

/// Sinais de recuperação de um dia (SPEC §7.10 A4), já agregados pelo serviço de HealthKit.
/// Valores ausentes são `nil`; zero ou negativo também é tratado como ausente pelo cálculo.
public struct DailyRecoverySample: Codable, Sendable, Hashable {
    /// Início do dia no calendário do usuário. O cálculo normaliza com `startOfDay` de qualquer forma.
    public let day: Date
    /// HRV (SDNN) média do dia, em milissegundos.
    public let hrvSDNN: Double?
    /// FC de repouso do dia, em bpm.
    public let restingHeartRate: Double?
    /// Horas de sono atribuídas a este dia (a noite que termina nele).
    public let sleepHours: Double?

    public init(day: Date, hrvSDNN: Double? = nil, restingHeartRate: Double? = nil, sleepHours: Double? = nil) {
        self.day = day
        self.hrvSDNN = hrvSDNN
        self.restingHeartRate = restingHeartRate
        self.sleepHours = sleepHours
    }
}
