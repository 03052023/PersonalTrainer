import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// SPEC RF-43 no histórico e no resumo (contrato V21 §B2): a medida vem do catálogo do seed pelo
/// `slug` do exercício gravado, a tonelagem só soma exercícios em repetições e a evolução de um
/// exercício em segundos ou passos mostra a melhor série com a unidade, sem 1RM estimado.
/// Container in-memory; tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class MeasureHistoryTests: XCTestCase {
    private let traits = ExerciseTraitsCatalog(traitsBySlug: [
        "plank": ExerciseTraits(measure: .seconds, atHome: true),
        "dumbbell-farmers-walk": ExerciseTraits(measure: .steps),
    ])

    // MARK: - MeasureText.measure(of:in:)

    func testRF43_measure_fromSeedSlug_customAndMissingStayInReps() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let plank = insertExercise(slug: "plank", name: "Prancha", into: context)
        let walk = insertExercise(slug: "dumbbell-farmers-walk", name: "Caminhada do fazendeiro", into: context)
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", into: context)
        let custom = insertExercise(slug: "custom-prancha-1234", name: "Minha prancha", isCustom: true, into: context)

        XCTAssertEqual(MeasureText.measure(of: plank, in: traits), .seconds)
        XCTAssertEqual(MeasureText.measure(of: walk, in: traits), .steps)
        XCTAssertEqual(MeasureText.measure(of: bench, in: traits), .reps, "slug fora do catálogo de medidas")
        XCTAssertEqual(MeasureText.measure(of: custom, in: traits), .reps, "SPEC RF-43: personalizado usa reps")
        XCTAssertEqual(MeasureText.measure(of: nil, in: traits), .reps, "relação anulada")
        XCTAssertEqual(MeasureText.measure(of: plank, in: .empty), .reps, "sem catálogo, tudo em repetições")
        withExtendedLifetime(container) {}
    }

    func testRF43_measure_customWithSeedSlug_staysInReps() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        // Mesmo que um personalizado tenha o slug de um exercício do seed, ele mede em repetições.
        let custom = insertExercise(slug: "plank", name: "Prancha do usuário", isCustom: true, into: context)

        XCTAssertEqual(MeasureText.measure(of: custom, in: traits), .reps)
        withExtendedLifetime(container) {}
    }

    // MARK: - Tonelagem (RF-12 com RF-43)

    func testRF12_RF43_tonnage_ofSession_skipsSecondsAndSteps() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", into: context)
        let walk = insertExercise(slug: "dumbbell-farmers-walk", name: "Caminhada do fazendeiro", into: context)
        let plank = insertExercise(slug: "plank", name: "Prancha", into: context)
        let session = insertSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [
                (bench, [(40, 12, true), (60, 10, false), (60, 8, false)]),
                (walk, [(24, 30, false), (24, 34, false)]),
                (plank, [(0, 45, false)]),
            ],
            into: context
        )
        try context.save()
        let ordered = session.exercises.sorted { $0.order < $1.order }

        XCTAssertEqual(MeasureText.tonnage(of: ordered, traits: traits), 1_080, accuracy: 0.0001, "60 × 10 + 60 × 8; aquecimento fora")
        XCTAssertEqual(
            MeasureText.tonnage(of: ordered, traits: .empty),
            2_616, // 60 × 10 + 60 × 8 + 24 × 30 + 24 × 34
            accuracy: 0.0001,
            "sem catálogo de medidas tudo conta como repetição, como antes da versão 2.1"
        )
        withExtendedLifetime(container) {}
    }

    // MARK: - Evolução do exercício

    func testRF43_progressPoints_secondsPickHighestLoadThenLongestHold() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let plank = insertExercise(slug: "plank", name: "Prancha", into: context)
        insertSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [(plank, [(0, 30, false), (0, 45, false), (0, 40, false)])],
            into: context
        )
        try context.save()
        let plankUUID = plank.uuid
        let sessionExercises = try context.fetch(FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == plankUUID }
        ))

        let points = ExerciseProgressView.points(from: sessionExercises, measure: .seconds)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.bestSetReps, 45, "sem carga, vale a sustentação mais longa")
        XCTAssertEqual(points.first?.bestSetLoad, 0)
        XCTAssertEqual(points.first?.workingSetCount, 3)
        withExtendedLifetime(container) {}
    }

    func testRF43_progressPoints_stepsPreferHeavierLoadOverMoreSteps() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let walk = insertExercise(slug: "dumbbell-farmers-walk", name: "Caminhada do fazendeiro", into: context)
        insertSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [(walk, [(20, 40, false), (24, 20, false), (24, 26, false)])],
            into: context
        )
        try context.save()
        let walkUUID = walk.uuid
        let sessionExercises = try context.fetch(FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == walkUUID }
        ))

        let points = ExerciseProgressView.points(from: sessionExercises, measure: .steps)

        XCTAssertEqual(points.first?.bestSetLoad, 24)
        XCTAssertEqual(points.first?.bestSetReps, 26, "empate na carga: mais passos")
        XCTAssertEqual(points.first?.maxLoad, 24)
        withExtendedLifetime(container) {}
    }

    func testRF43_detailLine_perMeasure() {
        let point = ExerciseProgressView.ProgressPoint(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            dayName: "Dia A",
            estimatedOneRepMax: 80,
            maxLoad: 62.5,
            bestSetLoad: 60,
            bestSetReps: 10,
            workingSetCount: 3
        )

        XCTAssertEqual(
            ExerciseProgressView.detailLine(point, loadUnit: .kilograms, measure: .reps),
            "Melhor série 60 kg × 10 · 1RM est. 80 kg · 3 séries",
            "repetições em kg: formato de sempre"
        )
        XCTAssertEqual(
            ExerciseProgressView.detailLine(point, loadUnit: .level, measure: .reps),
            "Carga máx. nível 63 · 3 séries"
        )
        XCTAssertEqual(
            ExerciseProgressView.detailLine(point, loadUnit: .kilograms, measure: .steps),
            "Melhor série 60 kg × 10 passos · 3 séries"
        )
        XCTAssertEqual(
            ExerciseProgressView.detailLine(point, loadUnit: .kilograms, measure: .seconds),
            "Melhor série 60 kg × 10 s · 3 séries"
        )
    }

    func testRF43_estimatesOneRepMax_onlyForKilogramsAndReps() {
        XCTAssertTrue(ExerciseProgressView.estimatesOneRepMax(loadUnit: .kilograms, measure: .reps))
        XCTAssertFalse(ExerciseProgressView.estimatesOneRepMax(loadUnit: .kilograms, measure: .seconds))
        XCTAssertFalse(ExerciseProgressView.estimatesOneRepMax(loadUnit: .kilograms, measure: .steps))
        XCTAssertFalse(ExerciseProgressView.estimatesOneRepMax(loadUnit: .plates, measure: .reps))
    }

    // MARK: - Fixtures

    private func insertExercise(slug: String, name: String, isCustom: Bool = false, into context: ModelContext) -> ExerciseModel {
        let exercise = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.core]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.bodyweight.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false,
            isCustom: isCustom
        )
        context.insert(exercise)
        return exercise
    }

    /// Sessão concluída com exercícios (na ordem dada) e séries: (carga, número, aquecimento).
    @discardableResult
    private func insertSession(
        startedAt: Date,
        exercises: [(ExerciseModel, [(Double, Int, Bool)])],
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)

        for (order, entry) in exercises.enumerated() {
            let (exercise, sets) = entry
            let sessionExercise = SessionExerciseModel(
                uuid: UUID(),
                order: order,
                exerciseUUID: exercise.uuid,
                exerciseName: exercise.name,
                prescribedLoad: nil,
                prescribedSets: 3,
                prescribedRepMin: 20,
                prescribedRepMax: 40,
                prescribedRIR: 2,
                restSeconds: 90,
                noteRaw: PrescriptionNote.hold.rawValue,
                wasSkipped: false,
                substitutedFromUUID: nil
            )
            context.insert(sessionExercise)
            sessionExercise.exercise = exercise
            session.exercises.append(sessionExercise)

            for (index, set) in sets.enumerated() {
                let completedAt = startedAt.addingTimeInterval(Double(order * 600 + index * 120 + 60))
                let setModel = SetLogModel(
                    uuid: UUID(),
                    index: index,
                    load: set.0,
                    reps: set.1,
                    rir: 2,
                    isWarmup: set.2,
                    completedAt: completedAt,
                    sourceRaw: "iphone",
                    updatedAt: completedAt
                )
                context.insert(setModel)
                sessionExercise.sets.append(setModel)
            }
        }
        return session
    }
}
