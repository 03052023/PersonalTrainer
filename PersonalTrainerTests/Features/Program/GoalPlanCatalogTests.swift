import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T7.4, SPEC RF-45 e RF-35: objetivo = plano. O `GoalPlanCatalog` é puro: recebe a lista do
/// repositório e diz, por objetivo, qual programa vale e quais são os formatos da Hipertrofia.
@MainActor
final class GoalPlanCatalogTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms

    func testRF45_catalog_goalsInPetalOrder() {
        let catalog = GoalPlanCatalog(programs: Programs.seed())

        XCTAssertEqual(catalog.entries.map(\.goal), [.longevity, .hypertrophy, .strength, .combat, .endurance])
        XCTAssertEqual(GoalPlanCatalog.orderedGoals, [.longevity, .hypertrophy, .strength, .combat, .endurance])
    }

    func testRF45_catalog_eachGoalResolvesToSeed() throws {
        let catalog = GoalPlanCatalog(programs: Programs.seed())

        XCTAssertEqual(catalog.entry(for: .strength)?.defaultProgramID, GoalPlanCatalog.strengthID)
        XCTAssertEqual(catalog.entry(for: .endurance)?.defaultProgramID, GoalPlanCatalog.enduranceID)
        XCTAssertEqual(catalog.entry(for: .longevity)?.defaultProgramID, GoalPlanCatalog.longevityID)
        XCTAssertEqual(catalog.entry(for: .combat)?.defaultProgramID, GoalPlanCatalog.combatID)

        let hypertrophy = try XCTUnwrap(catalog.entry(for: .hypertrophy))
        XCTAssertEqual(hypertrophy.formats.map(\.id), [
            GoalPlanCatalog.hypertrophyFullBodyID,
            GoalPlanCatalog.hypertrophyLowerFocusID,
            GoalPlanCatalog.hypertrophyUpperFocusID,
        ])
        XCTAssertEqual(hypertrophy.formats.map(\.title), ["Corpo todo", "Mais pernas e glúteos", "Mais tronco e braços"])
        XCTAssertEqual(hypertrophy.formats.map(\.dayCount), [3, 4, 4])
        XCTAssertEqual(hypertrophy.defaultProgramID, GoalPlanCatalog.hypertrophyFullBodyID, "O ativo")
        XCTAssertEqual(hypertrophy.dayCountText, "3 ou 4 dias")
        XCTAssertTrue(hypertrophy.isCurrent)

        for goal in [ProgramGoal.strength, .endurance, .longevity, .combat] {
            let entry = try XCTUnwrap(catalog.entry(for: goal))
            XCTAssertTrue(entry.formats.isEmpty, "\(goal) não tem formatos")
            XCTAssertEqual(entry.dayCountText, "3 dias", "\(goal)")
            XCTAssertFalse(entry.isCurrent, "\(goal)")
            XCTAssertTrue(entry.isAvailable, "\(goal)")
        }
        XCTAssertEqual(catalog.activeGoal, .hypertrophy)
        XCTAssertEqual(catalog.activeFormat?.isExtra, false)
        XCTAssertEqual(catalog.activeFormat?.title, "Corpo todo")
    }

    func testRF45_catalog_otherGoalActive_hypertrophyStartsAtFirstFormat() throws {
        let catalog = GoalPlanCatalog(programs: Programs.seed(activeID: GoalPlanCatalog.combatID))

        let combat = try XCTUnwrap(catalog.entry(for: .combat))
        XCTAssertTrue(combat.isCurrent)
        XCTAssertEqual(combat.defaultProgramID, GoalPlanCatalog.combatID)
        let hypertrophy = try XCTUnwrap(catalog.entry(for: .hypertrophy))
        XCTAssertFalse(hypertrophy.isCurrent)
        XCTAssertEqual(hypertrophy.defaultProgramID, GoalPlanCatalog.hypertrophyFullBodyID)
        XCTAssertNil(catalog.activeFormat, "Combate não tem formatos")
    }

    func testRF45_catalog_activeCopyAppearsAsExtraFormat() throws {
        let copyID = UUID()
        var programs = Programs.seed(activeID: nil)
        programs.append(Programs.program(id: copyID, name: "Meu corpo todo", goal: .hypertrophy, dayCount: 5, isActive: true))
        let catalog = GoalPlanCatalog(programs: programs)

        let hypertrophy = try XCTUnwrap(catalog.entry(for: .hypertrophy))
        XCTAssertEqual(hypertrophy.formats.map(\.id), [
            GoalPlanCatalog.hypertrophyFullBodyID,
            GoalPlanCatalog.hypertrophyLowerFocusID,
            GoalPlanCatalog.hypertrophyUpperFocusID,
            copyID,
        ])
        let extra = try XCTUnwrap(hypertrophy.formats.last)
        XCTAssertEqual(extra.title, "Meu corpo todo", "Com o próprio nome")
        XCTAssertTrue(extra.isExtra)
        XCTAssertTrue(extra.isActive)
        XCTAssertEqual(hypertrophy.defaultProgramID, copyID, "Marcado como atual")
        XCTAssertEqual(hypertrophy.dayCountText, "3 a 5 dias")
        XCTAssertEqual(catalog.activeFormat?.id, copyID)

        // Inativa, a cópia some da tela (continua no banco).
        programs.removeLast()
        programs.append(Programs.program(id: copyID, name: "Meu corpo todo", goal: .hypertrophy, dayCount: 5, isActive: false))
        let hidden = GoalPlanCatalog(programs: programs)
        XCTAssertFalse(hidden.entry(for: .hypertrophy)?.programIDs.contains(copyID) ?? true)
    }

    func testRF45_catalog_activeCopyOfGoalWithoutFormats_isThePlan() {
        let copyID = UUID()
        var programs = Programs.seed(activeID: nil)
        programs.append(Programs.program(id: copyID, name: "Força (cópia)", goal: .strength, isActive: true))
        let catalog = GoalPlanCatalog(programs: programs)

        XCTAssertEqual(catalog.entry(for: .strength)?.defaultProgramID, copyID, "RF-45: o ativo, se tiver o objetivo")
        XCTAssertEqual(catalog.entry(for: .strength)?.isCurrent, true)
        XCTAssertEqual(catalog.entry(for: .hypertrophy)?.isCurrent, false)
    }

    func testRF45_catalog_legacyHiddenUnlessActive() throws {
        let hidden = GoalPlanCatalog(programs: Programs.seed())
        for entry in hidden.entries {
            XCTAssertFalse(entry.programIDs.contains(GoalPlanCatalog.legacyPushLegsPullID), "\(entry.goal)")
        }

        let active = GoalPlanCatalog(programs: Programs.seed(activeID: GoalPlanCatalog.legacyPushLegsPullID))
        let hypertrophy = try XCTUnwrap(active.entry(for: .hypertrophy))
        XCTAssertEqual(hypertrophy.formats.count, 4)
        XCTAssertEqual(hypertrophy.formats.last?.id, GoalPlanCatalog.legacyPushLegsPullID)
        XCTAssertEqual(hypertrophy.formats.last?.title, "Hipertrofia — Empurrar/Inferior/Puxar")
        XCTAssertEqual(hypertrophy.formats.last?.isExtra, true)
        XCTAssertEqual(hypertrophy.defaultProgramID, GoalPlanCatalog.legacyPushLegsPullID)
    }

    func testRF45_catalog_missingSeedFallsBackToFirstByGoal() throws {
        let firstStrength = UUID()
        let secondStrength = UUID()
        var programs = Programs.seed().filter { $0.id != GoalPlanCatalog.strengthID && $0.id != GoalPlanCatalog.enduranceID }
        programs.append(Programs.program(id: firstStrength, name: "Força A", goal: .strength, dayCount: 2))
        programs.append(Programs.program(id: secondStrength, name: "Força B", goal: .strength, dayCount: 4))
        let catalog = GoalPlanCatalog(programs: programs)

        let strength = try XCTUnwrap(catalog.entry(for: .strength))
        XCTAssertEqual(strength.defaultProgramID, firstStrength, "O primeiro com aquele objetivo, na ordem recebida")
        XCTAssertEqual(strength.dayCountText, "2 dias")

        let endurance = try XCTUnwrap(catalog.entry(for: .endurance))
        XCTAssertNil(endurance.defaultProgramID)
        XCTAssertFalse(endurance.isAvailable)
        XCTAssertEqual(endurance.dayCountText, "Sem plano pronto")
        XCTAssertTrue(endurance.programIDs.isEmpty)
    }

    func testRF45_catalog_seedWithAnotherGoal_isNotThePlan() throws {
        // O seletor antigo permitia trocar o objetivo de um programa (ex.: o Combate do seed virar
        // Força). Ele deixa de ser o plano do Combate e não passa na frente do Força do seed.
        let programs = Programs.seed().map { program -> ProgramTemplate in
            guard program.id == GoalPlanCatalog.combatID else { return program }
            return ProgramTemplate(id: program.id, name: program.name, days: program.days, isActive: false, goal: .strength)
        }
        let catalog = GoalPlanCatalog(programs: programs)

        XCTAssertEqual(catalog.entry(for: .strength)?.defaultProgramID, GoalPlanCatalog.strengthID)
        XCTAssertEqual(catalog.entry(for: .combat)?.isAvailable, false)
    }

    func testRF45_catalog_noSeedFormats_firstHypertrophyIsTheOnlyFormat() throws {
        let legacyV1 = UUID()
        let programs = [
            Programs.program(id: legacyV1, name: "Meu ABC", goal: nil, dayCount: 3),
            Programs.program(id: GoalPlanCatalog.combatID, name: "Combate", goal: .combat, isActive: true),
        ]
        let catalog = GoalPlanCatalog(programs: programs)

        let hypertrophy = try XCTUnwrap(catalog.entry(for: .hypertrophy))
        XCTAssertEqual(hypertrophy.formats.map(\.id), [legacyV1], "Sem objetivo (v1) = hipertrofia")
        XCTAssertEqual(hypertrophy.formats.first?.title, "Meu ABC")
        XCTAssertEqual(hypertrophy.defaultProgramID, legacyV1)
        XCTAssertEqual(hypertrophy.dayCountText, "3 dias")
    }

    func testRF45_catalog_emptyList_hasNoPlans() {
        let catalog = GoalPlanCatalog(programs: [])

        XCTAssertEqual(catalog.entries.count, 5)
        XCTAssertTrue(catalog.entries.allSatisfy { !$0.isAvailable && !$0.isCurrent })
        XCTAssertNil(catalog.activeProgram)
        XCTAssertNil(catalog.activeGoal)
    }

    func testCatalog_texts() {
        XCTAssertEqual(GoalPlanCatalog.dayCountText(1), "1 dia")
        XCTAssertEqual(GoalPlanCatalog.dayCountText(3), "3 dias")
        XCTAssertEqual(GoalPlanCatalog.dayRangeText(min: 3, max: 3), "3 dias")
        XCTAssertEqual(GoalPlanCatalog.dayRangeText(min: 3, max: 4), "3 ou 4 dias")
        XCTAssertEqual(GoalPlanCatalog.dayRangeText(min: 2, max: 5), "2 a 5 dias")
        XCTAssertEqual(GoalPlanCatalog.weeklyText(3), "3 dias por semana")
        XCTAssertEqual(GoalPlanCatalog.weeklyText(1), "1 dia por semana")
        XCTAssertEqual(GoalPlanCatalog.shortDayName("Dia A — Corpo todo"), "Dia A")
        XCTAssertEqual(GoalPlanCatalog.shortDayName("Pernas"), "Pernas")
        let format = GoalPlanCatalog.Format(id: UUID(), title: "Mais pernas e glúteos", dayCount: 4, isActive: false, isExtra: false)
        XCTAssertEqual(GoalPlanCatalog.chipText(format), "Mais pernas e glúteos · 4 dias")
        XCTAssertEqual(GoalPlanCatalog.spokenChipText(format), "Mais pernas e glúteos, 4 dias")
    }
}
