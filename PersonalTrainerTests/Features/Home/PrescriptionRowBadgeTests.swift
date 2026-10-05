import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Teste cruzado da integração (2.4, docs/V24-CONTRACT.md §5 item 4): a linha da tela Hoje usa o selo novo
/// dos intervalos (SPEC §7.14 F6, RF-47), o mesmo da ficha, das informações e do Histórico. Nos outros
/// exercícios e nas outras notas, o selo de sempre.
@MainActor
final class PrescriptionRowBadgeTests: XCTestCase {
    func testF6_todayRowBadgeMoreBlocks() {
        let intervals = makePlanned(pattern: .cardio, sets: 5, load: nil, loadUnit: .kilograms, note: .increase)
        XCTAssertEqual(PrescriptionRow.badgeText(for: intervals), "Mais um bloco", "F6: sem nível, mais um bloco")

        let unloaded = makePlanned(pattern: .cardio, sets: 5, load: 0, loadUnit: .kilograms, note: .increase)
        XCTAssertEqual(PrescriptionRow.badgeText(for: unloaded), "Mais um bloco", "carga 0 é sem nível")

        let withLevel = makePlanned(pattern: .cardio, sets: 1, load: 6, loadUnit: .level, note: .increase)
        XCTAssertEqual(PrescriptionRow.badgeText(for: withLevel), "Nível maior", "F3: com nível, sobe o nível")

        let strength = makePlanned(pattern: .horizontalPush, sets: 3, load: 42.5, loadUnit: .kilograms, note: .increase)
        XCTAssertEqual(PrescriptionRow.badgeText(for: strength), "Carga maior")

        let hold = makePlanned(pattern: .cardio, sets: 4, load: nil, loadUnit: .kilograms, note: .hold)
        XCTAssertNil(PrescriptionRow.badgeText(for: hold), "manter não tem selo")

        let deload = makePlanned(pattern: .cardio, sets: 3, load: nil, loadUnit: .kilograms, note: .deload)
        XCTAssertEqual(PrescriptionRow.badgeText(for: deload), "Semana leve")
    }

    // MARK: - Fixture

    private func makePlanned(
        pattern: MovementPattern,
        sets: Int,
        load: Double?,
        loadUnit: LoadUnit,
        note: PrescriptionNote
    ) -> PlannedExercise {
        let exercise = ExerciseDefinition(
            slug: "fixture",
            name: "Exercício fixture",
            primaryMuscles: [.quads],
            equipment: .bodyweight,
            loadUnit: loadUnit,
            loadIncrement: 1,
            movementPattern: pattern
        )
        return PlannedExercise(
            id: UUID(),
            exercise: exercise,
            target: ExerciseTarget(exerciseID: exercise.id, order: 0, sets: sets, repMin: 3, repMax: 4),
            prescription: ExercisePrescription(
                exerciseID: exercise.id,
                load: load,
                sets: sets,
                repMin: 3,
                repMax: 4,
                targetReps: 3,
                targetRIR: 2,
                restSeconds: 120,
                note: note
            )
        )
    }
}
