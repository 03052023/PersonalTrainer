import Foundation

/// Dados pessoais opcionais usados só para a FCmáx (A1) e para a faixa de VO2max (A3).
public struct UserPhysiology: Codable, Sendable, Hashable {
    public let birthDate: Date?
    public let sex: BiologicalSexValue?
    /// FCmáx informada pelo usuário, em bpm. Prevalece sobre a fórmula de Tanaka quando > 0.
    public let maxHeartRateOverride: Int?

    public init(birthDate: Date? = nil, sex: BiologicalSexValue? = nil, maxHeartRateOverride: Int? = nil) {
        self.birthDate = birthDate
        self.sex = sex
        self.maxHeartRateOverride = maxHeartRateOverride
    }

    /// Idade em anos completos em `now`, no calendário recebido (SPEC P11: nada de relógio do sistema).
    /// `nil` sem data de nascimento ou com data de nascimento no futuro.
    public func ageYears(at now: Date, calendar: Calendar) -> Int? {
        guard let birthDate, birthDate <= now,
              let years = calendar.dateComponents([.year], from: birthDate, to: now).year,
              years >= 0
        else {
            return nil
        }
        return years
    }
}
