import Foundation

/// Recuperação: médias de 7 vs. 28 dias (SPEC §7.10 A4, RF-29). Médias ignoram dias sem dado;
/// `nil` quando não há nenhum dado na janela.
public struct RecoverySummary: Codable, Sendable, Hashable {
    /// HRV (SDNN) média, em ms.
    public let hrv7: Double?
    public let hrv28: Double?
    /// FC de repouso média, em bpm.
    public let restingHR7: Double?
    public let restingHR28: Double?
    /// Horas de sono médias.
    public let sleep7: Double?
    public let sleep28: Double?
    /// Dias dos últimos 7 (hoje incluído) com HRV ou sono registrados.
    public let nightsWithData7: Int
    /// Na ordem fixa de `RecoveryAlert.allCases`.
    public let alerts: [RecoveryAlert]

    public init(
        hrv7: Double?,
        hrv28: Double?,
        restingHR7: Double?,
        restingHR28: Double?,
        sleep7: Double?,
        sleep28: Double?,
        nightsWithData7: Int,
        alerts: [RecoveryAlert]
    ) {
        self.hrv7 = hrv7
        self.hrv28 = hrv28
        self.restingHR7 = restingHR7
        self.restingHR28 = restingHR28
        self.sleep7 = sleep7
        self.sleep28 = sleep28
        self.nightsWithData7 = nightsWithData7
        self.alerts = alerts
    }
}
