import Foundation
import Testing
@testable import TrainerCore

@Test("Domain ExerciseDefinition faz round-trip Codable")
func exerciseDefinitionCodableRoundTrip() throws {
    let value = ExerciseDefinition(
        id: UUID(),
        slug: "leg-press-45",
        name: "Leg press 45°",
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings],
        equipment: .machine,
        loadUnit: .kilograms,
        loadIncrement: 5,
        isUnilateral: false,
        machineNotes: "Banco 3"
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain ProgramTemplate faz round-trip Codable")
func programTemplateCodableRoundTrip() throws {
    let exerciseID = UUID()
    let target = ExerciseTarget(exerciseID: exerciseID, order: 0, startingLoad: 40)
    let day = ProgramDayTemplate(name: "Dia A", order: 0, exercises: [target])
    let value = ProgramTemplate(name: "Programa padrão", days: [day], isActive: true)

    try expectCodableRoundTrip(value)
}

@Test("Domain ProgramDayTemplate faz round-trip Codable")
func programDayTemplateCodableRoundTrip() throws {
    let value = ProgramDayTemplate(
        id: UUID(),
        name: "Dia B",
        order: 1,
        exercises: [ExerciseTarget(exerciseID: UUID(), order: 0)]
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain ExerciseTarget faz round-trip Codable")
func exerciseTargetCodableRoundTrip() throws {
    let value = ExerciseTarget(
        id: UUID(),
        exerciseID: UUID(),
        order: 2,
        sets: 4,
        repMin: 6,
        repMax: 10,
        targetRIR: 1,
        restSeconds: 180,
        startingLoad: 62.5
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain ExercisePrescription faz round-trip Codable")
func exercisePrescriptionCodableRoundTrip() throws {
    let value = ExercisePrescription(
        exerciseID: UUID(),
        load: 42.5,
        sets: 3,
        repMin: 8,
        repMax: 12,
        targetReps: 9,
        targetRIR: 2,
        restSeconds: 120,
        note: .hold
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain SetResult faz round-trip Codable")
func setResultCodableRoundTrip() throws {
    let value = SetResult(
        load: 60,
        reps: 10,
        rir: 2,
        isWarmup: false,
        completedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain ExerciseHistoryEntry faz round-trip Codable")
func exerciseHistoryEntryCodableRoundTrip() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let set = SetResult(load: 60, reps: 10, rir: 2, completedAt: date)
    let value = ExerciseHistoryEntry(
        sessionID: UUID(),
        date: date,
        sets: [set],
        wasDeload: true
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain SessionSummary faz round-trip Codable")
func sessionSummaryCodableRoundTrip() throws {
    let value = SessionSummary(
        id: UUID(),
        programDayID: UUID(),
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date(timeIntervalSince1970: 1_700_003_600),
        status: .completed,
        primaryMusclesTrained: [.chest, .triceps],
        workingSetCount: 12
    )

    try expectCodableRoundTrip(value)
}

@Test("Domain enums fazem round-trip Codable")
func domainEnumsCodableRoundTrip() throws {
    try expectCodableRoundTrip(MuscleGroup.shoulders)
    try expectCodableRoundTrip(Equipment.dumbbell)
    try expectCodableRoundTrip(LoadUnit.plates)
    try expectCodableRoundTrip(PrescriptionNote.increase)
    try expectCodableRoundTrip(SessionStatus.abandoned)
}

@Test("Domain ExerciseTarget usa os padrões da SPEC 7.2")
func exerciseTargetUsesSpecificationDefaults() {
    let value = ExerciseTarget(exerciseID: UUID(), order: 0)

    #expect(value.sets == 3)
    #expect(value.repMin == 8)
    #expect(value.repMax == 12)
    #expect(value.targetRIR == 2)
    #expect(value.restSeconds == 120)
    #expect(value.startingLoad == nil)
}

@Test("Domain ExercisePrescription usa os padrões da SPEC 7.2")
func exercisePrescriptionUsesSpecificationDefaults() {
    let value = ExercisePrescription(exerciseID: UUID())

    #expect(value.load == nil)
    #expect(value.sets == 3)
    #expect(value.repMin == 8)
    #expect(value.repMax == 12)
    #expect(value.targetReps == 8)
    #expect(value.targetRIR == 2)
    #expect(value.restSeconds == 120)
    #expect(value.note == .calibrate)
}

@Test("P8 Load arredonda para baixo no incremento")
func loadRoundsDownToIncrement() {
    #expect(Load.round(41, toIncrement: 2.5) == 40)
    #expect(Load.round(42.5, toIncrement: 2.5) == 42.5)
}

@Test("P8 Load arredonda para cima no incremento")
func loadRoundsUpToIncrement() {
    #expect(Load.round(41, toIncrement: 2.5, rule: .up) == 42.5)
    #expect(Load.round(42.5, toIncrement: 2.5, rule: .up) == 42.5)
}

@Test("P8 Load preserva peso corporal com incremento zero")
func loadPreservesValueForZeroIncrement() {
    #expect(Load.round(0, toIncrement: 0) == 0)
}

private func expectCodableRoundTrip<T>(_ value: T) throws
where T: Codable & Equatable {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(T.self, from: data)
    #expect(decoded == value)
}
