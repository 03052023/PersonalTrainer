import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.6, SPEC §7.15 M4, M5, M7, M8 e M9: o fluxo "O que muda" → "Seus dias" → "Sua semana" que
/// adiciona um segundo plano, e o "Seus dias" da aba Plano. O planejador de teste devolve `FitResult`
/// prontos; o repositório de teste registra as escritas. A tabela de consequências entra por fechamento,
/// para o teste não depender do conteúdo de `PlanCombination`.
@MainActor
final class PlanFitFlowModelTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let balancedID = GoalPlanCatalog.hypertrophyBalancedID
    private let cardioID = GoalPlanCatalog.enduranceCardioID

    // MARK: - Adicionar (M8)

    func testM8_addFlow_fits_addsPlanAndSavesPreferences() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let planner = GoalPlanTestPlanner()
        let schedule = WeekSchedule(
            slots: [
                PlannedSlot(weekday: .monday, programID: balancedID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
                PlannedSlot(weekday: .tuesday, programID: cardioID, indexInWeek: 0, kind: .cardio, orderInDay: 0, dayName: "Dia A — Base contínua", cardioIntensity: .moderate),
            ],
            notes: [.noFullRestDay]
        )
        planner.fitResult = FitResult(schedule: schedule)
        let sheet = makeSheet(repository, planner: planner)
        sheet.load()

        // Um plano ativo e outro objetivo tocado: os dois botões.
        sheet.select(.endurance)
        XCTAssertEqual(sheet.confirmTitle, "Trocar para Cardio")
        XCTAssertTrue(sheet.showsAddButton)
        XCTAssertEqual(sheet.addTitle, "Adicionar Cardio ao seu plano")
        let flow = try XCTUnwrap(sheet.makeAddFlow())

        // (a) O que muda.
        XCTAssertEqual(flow.page, .consequences)
        XCTAssertTrue(flow.isFirstPage)
        XCTAssertEqual(flow.title, "O que muda")
        XCTAssertEqual(flow.goals, [.hypertrophy, .endurance], "O principal primeiro (M1)")
        flow.next()

        // (b) Seus dias, a partir de `weekPreferences()`.
        XCTAssertEqual(flow.page, .days)
        XCTAssertEqual(flow.preferences, WeekPreferences.default)
        XCTAssertFalse(flow.isAvailable(.sunday), "Padrão: segunda a sábado")
        flow.toggle(.sunday)
        flow.allowsTwoSessionsPerDay = true
        XCTAssertTrue(flow.isAvailable(.sunday))
        XCTAssertTrue(planner.fitCheckedIDs.isEmpty, "Só confere ao chegar na semana")
        flow.next()

        // (c) Sua semana.
        XCTAssertEqual(flow.page, .week)
        XCTAssertEqual(planner.fitCheckedIDs, [[balancedID, cardioID]])
        XCTAssertEqual(planner.fitCheckedDates, [now], "Relógio injetado (SPEC P11)")
        var expected = WeekPreferences.default
        expected.availableDays.insert(.sunday)
        expected.allowsTwoSessionsPerDay = true
        XCTAssertEqual(planner.fitCheckedPreferences, [expected])
        XCTAssertTrue(flow.fits)
        XCTAssertEqual(flow.weekRows.first?.text, "Seg · Dia A — Superior")
        XCTAssertEqual(flow.weekRows.map(\.day), PlanWeekday.allCases)
        XCTAssertEqual(flow.weekNotes, ["Sem um dia de descanso completo."])
        XCTAssertNil(flow.problemText)
        XCTAssertEqual(flow.confirmTitle, "Adicionar Cardio")
        XCTAssertTrue(repository.calls.isEmpty, "Nada gravado antes de confirmar")

        XCTAssertEqual(flow.confirm(), .saved)
        XCTAssertEqual(planner.savedPreferences, [expected])
        XCTAssertEqual(repository.calls, [.addActivePlan(cardioID)])
        XCTAssertEqual(repository.activeIDs, [balancedID, cardioID])

        // Toques repetidos não gravam de novo.
        XCTAssertEqual(flow.confirm(), .refused)
        XCTAssertEqual(repository.calls, [.addActivePlan(cardioID)])
        sheet.finishAfterAdd()
        XCTAssertTrue(sheet.hasFinished)
    }

    func testM8_addFlow_doesNotFit_showsAlternatives_choosingOneAdds() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let planner = GoalPlanTestPlanner()
        let everyDay = WeekPreferences(availableDays: Set(PlanWeekday.allCases))
        let twoPerDay = WeekPreferences(allowsTwoSessionsPerDay: true)
        let firstWeek = WeekSchedule(slots: [
            PlannedSlot(weekday: .sunday, programID: cardioID, indexInWeek: 2, kind: .cardio, orderInDay: 0, cardioIntensity: .light),
        ])
        let secondWeek = WeekSchedule(slots: [
            PlannedSlot(weekday: .monday, programID: balancedID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
            PlannedSlot(weekday: .monday, programID: cardioID, indexInWeek: 0, kind: .cardio, orderInDay: 1, cardioIntensity: .moderate),
        ])
        let addSunday = FitAlternative(changes: [.addDays([.sunday])], preferences: everyDay, schedule: firstWeek)
        let allowTwo = FitAlternative(changes: [.allowTwoSessionsPerDay], preferences: twoPerDay, schedule: secondWeek)
        planner.fitResult = FitResult(
            schedule: nil,
            problems: [.notEnoughDays(needed: 7, available: 6)],
            alternatives: [addSunday, allowTwo]
        )
        let flow = try makeAddFlow(repository, planner: planner, candidate: .endurance)
        flow.next()
        flow.next()

        XCTAssertEqual(flow.page, .week)
        XCTAssertFalse(flow.fits)
        XCTAssertNil(flow.schedule)
        XCTAssertTrue(flow.weekRows.isEmpty)
        XCTAssertEqual(flow.problemText, "São 7 sessões para 6 dias.")
        XCTAssertEqual(flow.alternatives, [addSunday, allowTwo], "Na ordem de M5, cada uma com a semana dela")
        XCTAssertFalse(flow.showsNoAlternative)
        XCTAssertFalse(flow.canConfirm)
        XCTAssertEqual(flow.confirm(), .refused, "Sem semana que cabe, o botão principal não grava")
        XCTAssertTrue(repository.calls.isEmpty)

        // Uma saída que não é desta semana não vale.
        let stranger = FitAlternative(changes: [.allowLightCardioAfterStrength], preferences: twoPerDay, schedule: secondWeek)
        XCTAssertEqual(flow.choose(stranger), .refused)

        XCTAssertEqual(flow.choose(allowTwo), .saved)
        XCTAssertEqual(planner.savedPreferences, [twoPerDay], "Grava as preferências da saída escolhida")
        XCTAssertEqual(repository.calls, [.addActivePlan(cardioID)])
        XCTAssertEqual(flow.choose(addSunday), .refused, "Depois de gravar, nada mais")
    }

    func testM8_addFlow_noAlternative() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let planner = GoalPlanTestPlanner()
        planner.fitResult = FitResult(schedule: nil, problems: [.muscleRecovery], alternatives: [])
        let flow = try makeAddFlow(repository, planner: planner, candidate: .strength)
        flow.next()
        flow.next()

        XCTAssertFalse(flow.fits)
        XCTAssertTrue(flow.showsNoAlternative)
        XCTAssertEqual(flow.problemText, "Duas sessões de força com os mesmos músculos ficariam a menos de 48 h.")
        XCTAssertTrue(flow.alternatives.isEmpty)
        XCTAssertEqual(PlanWeekText.noAlternative, "Esses dois planos não cabem juntos na semana. Escolha um só.")
        XCTAssertEqual(flow.confirm(), .refused)
        XCTAssertTrue(planner.savedPreferences.isEmpty)
        XCTAssertTrue(repository.calls.isEmpty)
    }

    func testM8_addFlow_blockedDuringSession() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let planner = GoalPlanTestPlanner()
        let sheet = makeSheet(repository, planner: planner, isSessionInProgress: true)
        sheet.load()
        sheet.select(.endurance)

        XCTAssertTrue(sheet.showsAddButton, "O botão aparece, desabilitado")
        XCTAssertFalse(sheet.canAdd)
        XCTAssertNil(sheet.makeAddFlow())

        // A sessão começou com o fluxo aberto: a semana ainda aparece, mas nada é gravado.
        let current = try XCTUnwrap(repository.programs.first { $0.id == balancedID })
        let candidate = try XCTUnwrap(repository.programs.first { $0.id == cardioID })
        let flow = PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: candidate),
            programs: repository,
            planner: planner,
            now: clock,
            isSessionInProgress: false
        )
        flow.next()
        flow.next()
        flow.isSessionInProgress = true
        XCTAssertFalse(flow.canConfirm)
        XCTAssertEqual(flow.confirm(), .refused)
        XCTAssertTrue(repository.calls.isEmpty)
    }

    func testM8_addFlow_failures_showMessage() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let planner = GoalPlanTestPlanner()
        planner.fitError = GoalPlanTestError.boom
        let flow = try makeAddFlow(repository, planner: planner, candidate: .endurance)
        flow.next()
        flow.next()

        XCTAssertTrue(flow.didFailToCheck)
        XCTAssertFalse(flow.fits)
        XCTAssertNil(flow.errorMessage, "A falha da conferência fica na página, sem alerta")

        planner.fitError = nil
        flow.checkFit()
        XCTAssertFalse(flow.didFailToCheck)
        XCTAssertTrue(flow.fits)

        repository.writeError = GoalPlanTestError.boom
        XCTAssertEqual(flow.confirm(), .failed)
        XCTAssertEqual(flow.errorMessage, "Não foi possível adicionar o plano. Tente de novo.")
        XCTAssertFalse(flow.hasFinished, "Dá para tentar de novo")
    }

    func testM8_addFlow_backGoesPageByPage() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let flow = try makeAddFlow(repository, planner: GoalPlanTestPlanner(), candidate: .endurance)

        XCTAssertFalse(flow.back(), "Na primeira página, quem apresenta volta à lista")
        flow.next()
        flow.next()
        XCTAssertEqual(flow.page, .week)
        XCTAssertTrue(flow.back())
        XCTAssertEqual(flow.page, .days)

        // Sem nenhum dia, não dá para seguir.
        for day in PlanWeekday.allCases where flow.isAvailable(day) {
            flow.toggle(day)
        }
        XCTAssertFalse(flow.canContinue)
        flow.next()
        XCTAssertEqual(flow.page, .days)
    }

    // MARK: - O que muda (M7)

    func testM7_overlapWarning() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let current = try XCTUnwrap(repository.programs.first { $0.id == balancedID })
        let strength = try XCTUnwrap(repository.programs.first { $0.id == GoalPlanCatalog.strengthID })
        let cardio = try XCTUnwrap(repository.programs.first { $0.id == cardioID })
        let table: (ProgramGoal, ProgramGoal) -> [PlanConsequence] = { _, _ in
            [
                PlanConsequence(kind: .negative, text: "Mais séries para os mesmos músculos.", referenceTopic: "topic.volume"),
                PlanConsequence(kind: .positive, text: "Força máxima e massa muscular juntas.", referenceTopic: "topic.load"),
                PlanConsequence(kind: .neutral, text: "Os dois treinam quase os mesmos levantamentos.", referenceTopic: "topic.combination"),
            ]
        }
        let overlap: (ProgramGoal, ProgramGoal) -> Bool = { first, second in
            Set([first, second]) == Set([ProgramGoal.hypertrophy, .strength])
        }

        let withStrength = PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: strength),
            programs: repository,
            planner: GoalPlanTestPlanner(),
            now: clock,
            consequences: table,
            isLargeOverlap: overlap
        )
        XCTAssertTrue(withStrength.showsOverlapWarning)
        XCTAssertEqual(withStrength.consequenceGroups.map(\.kind), [.positive, .neutral, .negative], "Ganha, Fica igual, Custa")
        XCTAssertEqual(withStrength.consequenceGroups.map(\.title), ["Ganha", "Fica igual", "Custa"])
        XCTAssertEqual(withStrength.consequenceGroups.first?.items.first?.referenceTopic, "topic.load")

        let withCardio = PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: cardio),
            programs: repository,
            planner: GoalPlanTestPlanner(),
            now: clock,
            consequences: { _, _ in [] },
            isLargeOverlap: overlap
        )
        XCTAssertFalse(withCardio.showsOverlapWarning)
        XCTAssertTrue(withCardio.consequenceGroups.isEmpty, "Grupo vazio não aparece")

        // Sem fechamento, vale a tabela do TrainerCore.
        let wired = PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: strength),
            programs: repository,
            planner: GoalPlanTestPlanner(),
            now: clock
        )
        XCTAssertEqual(wired.showsOverlapWarning, PlanCombination.isLargeOverlap(.hypertrophy, .strength))
        XCTAssertEqual(
            wired.consequenceGroups.flatMap(\.items).count,
            PlanCombination.consequences(.hypertrophy, .strength).count
        )
    }

    // MARK: - Seus dias (M9)

    func testM9_editDays_checksFitBeforeSaving() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let planner = GoalPlanTestPlanner()
        planner.fitResult = FitResult(schedule: WeekSchedule(slots: [
            PlannedSlot(weekday: .wednesday, programID: cardioID, indexInWeek: 0, kind: .cardio, orderInDay: 0, cardioIntensity: .vigorous),
        ]))
        let plans = PlanTabModel(
            programs: repository,
            catalog: GoalPlanTestCatalog(),
            planner: planner,
            coordinator: nil,
            now: clock
        )
        plans.refresh()
        let flow = try XCTUnwrap(plans.makeDaysFlow())

        XCTAssertEqual(flow.pages, [.days, .week], "Sem \"O que muda\"")
        XCTAssertEqual(flow.page, .days)
        XCTAssertFalse(flow.back())
        flow.toggle(.saturday)
        flow.allowsLightCardioAfterStrength = true
        flow.next()

        XCTAssertEqual(planner.fitCheckedIDs, [[balancedID, cardioID]])
        XCTAssertEqual(flow.weekRows.first { $0.day == .wednesday }?.text, "Qua · Cardio forte")
        XCTAssertEqual(flow.confirmTitle, "Salvar os dias")
        XCTAssertEqual(flow.confirm(), .saved)
        var expected = WeekPreferences.default
        expected.availableDays.remove(.saturday)
        expected.allowsLightCardioAfterStrength = true
        XCTAssertEqual(planner.savedPreferences, [expected])
        XCTAssertTrue(repository.calls.isEmpty, "Mudar os dias não mexe nos planos")
    }

    // MARK: - Fábricas

    /// O relógio fixo dos testes (SPEC P11).
    private var clock: () -> Date {
        let fixedNow = now
        return { fixedNow }
    }

    private func makeSheet(
        _ repository: GoalPlanTestRepository,
        planner: GoalPlanTestPlanner?,
        mode: GoalSheet.Mode = .change,
        isSessionInProgress: Bool = false
    ) -> GoalSheetModel {
        let fixedNow = now
        return GoalSheetModel(
            programs: repository,
            catalog: nil,
            mode: mode,
            isSessionInProgress: isSessionInProgress,
            planner: planner,
            now: { fixedNow }
        )
    }

    /// O fluxo de adicionar `candidate` ao Equilibrado, aberto pela folha no modo de adicionar.
    private func makeAddFlow(
        _ repository: GoalPlanTestRepository,
        planner: GoalPlanTestPlanner,
        candidate: ProgramGoal
    ) throws -> PlanFitFlowModel {
        let sheet = makeSheet(repository, planner: planner, mode: .add)
        sheet.load()
        sheet.select(candidate)
        XCTAssertTrue(sheet.canAdd)
        return try XCTUnwrap(sheet.makeAddFlow())
    }
}
