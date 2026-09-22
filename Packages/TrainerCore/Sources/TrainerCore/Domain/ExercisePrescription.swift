import Foundation

public struct ExercisePrescription: Codable, Sendable, Hashable {
    public let exerciseID: UUID
    public let load: Double?
    public let sets: Int
    public let repMin: Int
    public let repMax: Int
    public let targetReps: Int
    public let targetRIR: Int
    public let restSeconds: Int
    public let note: PrescriptionNote

    public init(
        exerciseID: UUID,
        load: Double? = nil,
        sets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        targetReps: Int = 8,
        targetRIR: Int = 2,
        restSeconds: Int = 120,
        note: PrescriptionNote = .calibrate
    ) {
        self.exerciseID = exerciseID
        self.load = load
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.targetReps = targetReps
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.note = note
    }
}
