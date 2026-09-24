import Foundation

/// Um treino aeróbico já agregado pelo serviço de HealthKit (ARCHITECTURE §8: amostras brutas não
/// saem do serviço). A FC chega como média por minuto, que é tudo que a regra A1 precisa.
public struct AerobicWorkoutSample: Codable, Sendable, Hashable, Identifiable {
    /// UUID do `HKWorkout`; treinos repetidos com o mesmo id contam uma vez.
    public let id: UUID
    public let activity: AerobicActivity
    public let start: Date
    public let end: Date
    /// FC média de cada minuto do treino, em bpm, na ordem do tempo. Vazio se o treino não tem FC.
    /// Pode ter menos entradas que a duração (minutos sem leitura usam `activity.defaultIntensity`).
    public let minuteHeartRates: [Double]

    public init(
        id: UUID = UUID(),
        activity: AerobicActivity,
        start: Date,
        end: Date,
        minuteHeartRates: [Double] = []
    ) {
        self.id = id
        self.activity = activity
        self.start = start
        self.end = end
        self.minuteHeartRates = minuteHeartRates
    }
}
