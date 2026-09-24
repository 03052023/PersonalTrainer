import Foundation

/// Zonas de intensidade do aeróbico pela FC (SPEC §7.10 A1). Vive em `TrainerCore/Health`, fora de
/// `Engine/`: a FC classifica só o treino aeróbico e nunca entra na prescrição de musculação
/// (SPEC §7.6, P12, AGENTS R2).
///
/// - FCmáx = valor informado pelo usuário ou 208 − 0,7 × idade (Tanaka, Monahan, Seals 2001,
///   J Am Coll Cardiol 37(1):153–156, doi:10.1016/S0735-1097(00)01054-8).
/// - Com FC de repouso: % da FC de reserva (Karvonen), moderado 40–59 %, vigoroso ≥ 60 %.
/// - Sem FC de repouso: % da FCmáx, moderado 64–76 %, vigoroso ≥ 77 %.
///   Limiares da tabela de intensidade do ACSM (Garber et al. 2011, Med Sci Sports Exerc
///   43(7):1334–1359, doi:10.1249/MSS.0b013e318213fefb).
/// - Abaixo do limiar moderado = leve, que não conta para a meta (A2).
public struct HeartRateZones: Sendable, Hashable {
    /// Início da faixa moderada em fração da FCmáx (ACSM: 64 %).
    public static let moderateFractionOfMax = 0.64
    /// Início da faixa vigorosa em fração da FCmáx (ACSM: 77 %).
    public static let vigorousFractionOfMax = 0.77
    /// Início da faixa moderada em fração da FC de reserva (ACSM: 40 %).
    public static let moderateFractionOfReserve = 0.40
    /// Início da faixa vigorosa em fração da FC de reserva (ACSM: 60 %).
    public static let vigorousFractionOfReserve = 0.60

    /// FCmáx em bpm.
    public let maxHeartRate: Double
    /// FC de repouso em bpm quando válida (finita, > 0 e abaixo da FCmáx); `nil` → classifica por % da FCmáx.
    public let restingHeartRate: Double?

    /// - Parameters:
    ///   - maxHeartRate: FCmáx em bpm.
    ///   - restingHeartRate: FC de repouso (média de 7 dias no painel). Valor inválido é descartado,
    ///     e a classificação cai para % da FCmáx em vez de produzir uma reserva zero ou negativa.
    public init(maxHeartRate: Double, restingHeartRate: Double? = nil) {
        self.maxHeartRate = maxHeartRate
        if let resting = HealthMath.positive(restingHeartRate), resting < maxHeartRate {
            self.restingHeartRate = resting
        } else {
            self.restingHeartRate = nil
        }
    }

    /// `true` quando a classificação usa a FC de reserva (Karvonen).
    public var usesHeartRateReserve: Bool { restingHeartRate != nil }

    /// FCmáx prevista por idade (Tanaka 2001): 208 − 0,7 × idade.
    /// Calculada como `208 − 7 × idade / 10` para ser exata em ponto flutuante com idades inteiras.
    public static func tanakaMaxHeartRate(ageYears: Int) -> Double {
        208 - Double(7 * ageYears) / 10
    }

    /// FCmáx do usuário em `now`: o valor informado (> 0) prevalece; senão Tanaka pela idade.
    /// `nil` sem idade e sem valor informado.
    public static func maxHeartRate(physiology: UserPhysiology, now: Date, calendar: Calendar) -> Double? {
        if let override = physiology.maxHeartRateOverride, override > 0 {
            return Double(override)
        }
        guard let age = physiology.ageYears(at: now, calendar: calendar) else { return nil }
        return tanakaMaxHeartRate(ageYears: age)
    }

    /// Zonas do usuário, ou `nil` quando não há como saber a FCmáx. Sem zonas, todo minuto usa a
    /// intensidade padrão do tipo de treino (A1).
    public static func make(
        physiology: UserPhysiology,
        restingHeartRate: Double?,
        now: Date,
        calendar: Calendar
    ) -> HeartRateZones? {
        guard let max = maxHeartRate(physiology: physiology, now: now, calendar: calendar),
              max.isFinite, max > 0
        else {
            return nil
        }
        return HeartRateZones(maxHeartRate: max, restingHeartRate: restingHeartRate)
    }

    /// Intensidade de um minuto com FC média `heartRate` (bpm). `nil` para leitura inválida
    /// (não finita ou ≤ 0): o chamador trata o minuto como "sem FC".
    public func intensity(forHeartRate heartRate: Double) -> AerobicIntensity? {
        guard heartRate.isFinite, heartRate > 0, maxHeartRate.isFinite, maxHeartRate > 0 else {
            return nil
        }
        if let resting = restingHeartRate {
            let fraction = (heartRate - resting) / (maxHeartRate - resting)
            return Self.classify(
                fraction,
                moderate: Self.moderateFractionOfReserve,
                vigorous: Self.vigorousFractionOfReserve
            )
        }
        return Self.classify(
            heartRate / maxHeartRate,
            moderate: Self.moderateFractionOfMax,
            vigorous: Self.vigorousFractionOfMax
        )
    }

    /// Limites inclusivos no início de cada faixa: "64–76 %" significa [64 %, 77 %), então 76,5 % é moderado.
    private static func classify(_ fraction: Double, moderate: Double, vigorous: Double) -> AerobicIntensity {
        if fraction >= vigorous - HealthMath.epsilon { return .vigorous }
        if fraction >= moderate - HealthMath.epsilon { return .moderate }
        return .light
    }
}
