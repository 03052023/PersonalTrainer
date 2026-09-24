import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.9 (CA1-7), T2.13, T2.10: formatação pt-BR do histórico, filtro de sessões em andamento,
/// mensagens de "Apagar", FC do detalhe e pontos da evolução de carga por exercício.
/// Tudo em `@MainActor` (ARCHITECTURE §10); container in-memory; sem `Task.sleep`.
@MainActor
final class HistoryTests: XCTestCase {
    // MARK: - DateFormatting.shortDate

    func testShortDate_ptBR_hasWeekdayDayMonthAndTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // 2026-09-22 é terça-feira: o exemplo da tarefa, "ter., 22 de set. · 19:40".
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 19, minute: 40))
        )

        let text = DateFormatting.shortDate(date, timeZone: timeZone)

        // As abreviações exatas ("ter.", "set.") dependem da versão do ICU do runner; as
        // asserções checam as partes que não mudam entre versões.
        XCTAssertTrue(text.lowercased().hasPrefix("ter"), text)
        XCTAssertTrue(text.contains("22"), text)
        XCTAssertTrue(text.lowercased().contains("set"), text)
        XCTAssertTrue(text.contains(" · "), text)
        XCTAssertTrue(text.hasSuffix("19:40"), text)
    }

    func testShortDate_respectsTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let saoPaulo = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        // 2026-09-22T22:40:00Z = 19:40 em São Paulo (UTC−3; o Brasil não tem horário de verão).
        let date = Date(timeIntervalSince1970: 1_790_116_800)

        XCTAssertTrue(DateFormatting.shortDate(date, timeZone: utc).hasSuffix("22:40"))
        XCTAssertTrue(DateFormatting.shortDate(date, timeZone: saoPaulo).hasSuffix("19:40"))
    }

    // MARK: - DateFormatting.duration

    func testDuration_formatsHoursWithPaddedMinutes() {
        XCTAssertEqual(DateFormatting.duration(3_900), "1 h 05 min")
        XCTAssertEqual(DateFormatting.duration(7_200), "2 h 00 min")
        XCTAssertEqual(DateFormatting.duration(5_400), "1 h 30 min")
    }

    func testDuration_belowOneHour_showsOnlyMinutes() {
        XCTAssertEqual(DateFormatting.duration(2_700), "45 min")
        XCTAssertEqual(DateFormatting.duration(59), "0 min")
        XCTAssertEqual(DateFormatting.duration(0), "0 min")
    }

    func testDuration_nil_isInProgress() {
        XCTAssertEqual(DateFormatting.duration(nil), "Em andamento")
    }

    func testDuration_negativeOrNonFinite_neverCrashes() {
        XCTAssertEqual(DateFormatting.duration(-30), "0 min")
        XCTAssertEqual(DateFormatting.duration(.infinity), "—")
        XCTAssertEqual(DateFormatting.duration(.nan), "—")
    }

    // MARK: - HistoryListView.filterVisible

    func testFilterVisible_dropsInProgressAndKeepsNewestFirst() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        insertSession(status: .completed, startedAt: base, into: context)
        insertSession(status: .inProgress, startedAt: base.addingTimeInterval(2 * 86_400), into: context)
        insertSession(status: .abandoned, startedAt: base.addingTimeInterval(86_400), into: context)
        try context.save()

        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            sortBy: [SortDescriptor(\WorkoutSessionModel.startedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        let visible = HistoryListView.filterVisible(all)

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(visible.map { $0.statusRaw }, ["abandoned", "completed"])
    }

    func testFilterVisible_keepsUnknownStatusRaw() throws {
        // Um raw desconhecido indica store corrompido; o histórico prefere mostrar a
        // sessão (sem badge) a escondê-la em silêncio.
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: "paused",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)

        XCTAssertEqual(HistoryListView.filterVisible([session]).count, 1)
    }

    // MARK: - HistoryListView.deletionMessage (T2.13)

    func testDeletionMessage_isPortuguesePerError() {
        XCTAssertEqual(
            HistoryListView.deletionMessage(for: SessionCoordinatorError.sessionNotFound(UUID())),
            "Este treino já tinha sido apagado."
        )
        XCTAssertEqual(
            HistoryListView.deletionMessage(for: SessionCoordinatorError.unsupported),
            "Apagar treinos ainda não está disponível nesta versão."
        )
        XCTAssertEqual(
            HistoryListView.deletionMessage(for: SessionCoordinatorError.setNotFound(UUID())),
            "Não foi possível apagar o treino. Tente de novo."
        )
        XCTAssertEqual(
            HistoryListView.deletionMessage(for: HistoryTestError.boom),
            "Não foi possível apagar o treino. Tente de novo."
        )
    }

    // MARK: - SessionDetailView.heartRateText (RF-14, CA2-2)

    func testHeartRateText_onlyShowsPositiveReadings() {
        XCTAssertEqual(SessionDetailView.heartRateText(average: nil, maximum: nil), "FC indisponível")
        XCTAssertEqual(SessionDetailView.heartRateText(average: 0, maximum: 0), "FC indisponível")
        XCTAssertEqual(SessionDetailView.heartRateText(average: nil, maximum: 158), "FC indisponível")
        XCTAssertEqual(SessionDetailView.heartRateText(average: 121.4, maximum: 157.6), "121 / 158 bpm")
        XCTAssertEqual(SessionDetailView.heartRateText(average: 121, maximum: nil), "121 / — bpm")
        XCTAssertEqual(SessionDetailView.heartRateText(average: 121, maximum: 0), "121 / — bpm")
    }

    // MARK: - SessionExerciseSection.noteText

    func testNoteText_isPortuguese() {
        XCTAssertEqual(SessionExerciseSection.noteText(.calibrate), "Calibrar")
        XCTAssertEqual(SessionExerciseSection.noteText(.increase), "Subir")
        XCTAssertEqual(SessionExerciseSection.noteText(.hold), "Manter")
        XCTAssertEqual(SessionExerciseSection.noteText(.retry), "Repetir")
        XCTAssertEqual(SessionExerciseSection.noteText(.decrease), "Reduzir")
        XCTAssertEqual(SessionExerciseSection.noteText(.returning), "Retorno")
        XCTAssertEqual(SessionExerciseSection.noteText(.deload), "Semana leve")
    }

    // MARK: - ExerciseProgressView (T2.10)

    func testEstimatedOneRepMax_isEpley() {
        XCTAssertEqual(ExerciseProgressView.estimatedOneRepMax(load: 60, reps: 10), 80, accuracy: 0.0001)
        XCTAssertEqual(ExerciseProgressView.estimatedOneRepMax(load: 100, reps: 0), 100, accuracy: 0.0001)
        XCTAssertEqual(ExerciseProgressView.estimatedOneRepMax(load: 57.5, reps: 10), 76.6667, accuracy: 0.001)
        XCTAssertEqual(ExerciseProgressView.roundedToTenth(76.6667), 76.7, accuracy: 0.0001)
    }

    func testProgressPoints_P1_P3_onePointPerFinishedSession_workingSetsOnly_chronological() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let squat = insertExercise(slug: "agachamento-livre", name: "Agachamento livre", into: context)
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", into: context)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Concluída: aquecimento fora; melhor série 60 × 10 → 1RM 80.
        let first = insertSession(
            status: .completed,
            startedAt: base,
            exercises: [(squat, [(40, 12, true), (60, 10, false), (60, 8, false)])],
            into: context
        )
        // Abandonada conta (SPEC P3): 57,5 × 10 (≈ 76,7) supera 62,5 × 6 (75); carga máx. 62,5.
        let third = insertSession(
            status: .abandoned,
            startedAt: base.addingTimeInterval(2 * 86_400),
            exercises: [(squat, [(62.5, 6, false), (57.5, 10, false)])],
            into: context
        )
        // O mesmo exercício duas vezes na sessão vira um ponto só: 55 × 8 (≈ 69,7) > 50 × 10 (≈ 66,7).
        let second = insertSession(
            status: .completed,
            startedAt: base.addingTimeInterval(86_400),
            exercises: [(squat, [(50, 10, false)]), (bench, [(40, 10, false)]), (squat, [(55, 8, false)])],
            into: context
        )
        // Não entram: em andamento, só aquecimento e série com 0 repetições.
        insertSession(
            status: .inProgress,
            startedAt: base.addingTimeInterval(4 * 86_400),
            exercises: [(squat, [(70, 5, false)])],
            into: context
        )
        insertSession(
            status: .completed,
            startedAt: base.addingTimeInterval(3 * 86_400),
            exercises: [(squat, [(40, 12, true), (80, 0, false)])],
            into: context
        )
        try context.save()

        // Mesmo filtro por `exerciseUUID` do `@Query` da view.
        let squatUUID = squat.uuid
        let sessionExercises = try context.fetch(FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == squatUUID }
        ))
        let points = ExerciseProgressView.points(from: sessionExercises)

        XCTAssertEqual(points.map { $0.id }, [first.uuid, second.uuid, third.uuid])

        XCTAssertEqual(points[0].estimatedOneRepMax, 80, accuracy: 0.0001)
        XCTAssertEqual(points[0].maxLoad, 60)
        XCTAssertEqual(points[0].bestSetLoad, 60)
        XCTAssertEqual(points[0].bestSetReps, 10)
        XCTAssertEqual(points[0].workingSetCount, 2, "SPEC P1: aquecimento não conta")
        XCTAssertEqual(points[0].date, base)

        XCTAssertEqual(points[1].bestSetLoad, 55)
        XCTAssertEqual(points[1].bestSetReps, 8)
        XCTAssertEqual(points[1].maxLoad, 55)
        XCTAssertEqual(points[1].workingSetCount, 2, "Só as séries do exercício pedido, somadas na sessão")

        XCTAssertEqual(points[2].bestSetLoad, 57.5)
        XCTAssertEqual(points[2].bestSetReps, 10)
        XCTAssertEqual(points[2].estimatedOneRepMax, 76.6667, accuracy: 0.001)
        XCTAssertEqual(points[2].maxLoad, 62.5)
        withExtendedLifetime(container) {}
    }

    func testProgressPoints_emptyHistory_isEmpty() {
        XCTAssertTrue(ExerciseProgressView.points(from: []).isEmpty)
    }

    // MARK: - Fixtures

    @discardableResult
    private func insertExercise(slug: String, name: String, into context: ModelContext) -> ExerciseModel {
        let exercise = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(exercise)
        return exercise
    }

    /// Sessão com exercícios (na ordem dada) e as séries de cada um: (carga, reps, aquecimento).
    @discardableResult
    private func insertSession(
        status: SessionStatus,
        startedAt: Date,
        exercises: [(ExerciseModel, [(Double, Int, Bool)])],
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia B — Inferior",
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
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
                prescribedRepMin: 8,
                prescribedRepMax: 12,
                prescribedRIR: 2,
                restSeconds: 120,
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

    private func insertSession(
        status: SessionStatus,
        startedAt: Date,
        into context: ModelContext
    ) {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)
    }
}

private enum HistoryTestError: Error {
    case boom
}
