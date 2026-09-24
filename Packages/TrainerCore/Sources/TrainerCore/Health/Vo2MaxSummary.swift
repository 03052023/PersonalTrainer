import Foundation

/// Resumo do VO2max estimado pelo Watch (SPEC §7.10 A3, RF-28).
public struct Vo2MaxSummary: Codable, Sendable, Hashable {
    /// Estimativa mais recente, em mL/kg/min.
    public let latest: Double
    public let latestDate: Date
    /// `latest` menos a média das estimativas feitas entre 80 e 100 dias atrás; `nil` sem amostras nessa janela.
    public let change90Days: Double?
    /// `nil` sem idade, sem sexo (ou `other`) ou com idade fora da tabela normativa (20–79 anos).
    public let band: FitnessBand?
    /// Idade usada para a faixa (anos completos na data do relatório).
    public let ageYears: Int?

    public init(latest: Double, latestDate: Date, change90Days: Double?, band: FitnessBand?, ageYears: Int?) {
        self.latest = latest
        self.latestDate = latestDate
        self.change90Days = change90Days
        self.band = band
        self.ageYears = ageYears
    }
}
