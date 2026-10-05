import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.6, SPEC §7.15 M4, M5, M7 e M8: os textos da semana com dois planos, em tabela. pt-BR curto, sem
/// RIR, sem FC e sem frase de efeito (DESIGN §6).
@MainActor
final class PlanWeekTextTests: XCTestCase {
    private let hypertrophyID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001") ?? UUID()
    private let cardioID = UUID(uuidString: "00000000-0000-0000-0000-00000000A002") ?? UUID()

    private var goals: [UUID: ProgramGoal] {
        [hypertrophyID: .hypertrophy, cardioID: .endurance]
    }

    func testPlanWeekText_table() {
        // M5: o motivo.
        let problems: [(problem: FitProblem, twoPerDay: Bool, text: String)] = [
            (.notEnoughDays(needed: 7, available: 6), false, "São 7 sessões para 6 dias."),
            (.notEnoughDays(needed: 8, available: 1), false, "São 8 sessões para 1 dia."),
            (.notEnoughDays(needed: 13, available: 12), true, "São 13 sessões, e cabem 12 nos seus dias."),
            (.muscleRecovery, false, "Duas sessões de força com os mesmos músculos ficariam a menos de 48 h."),
            (.cardioBeforeLegs, false, "Um cardio forte cairia na véspera de pernas."),
        ]
        for row in problems {
            XCTAssertEqual(PlanWeekText.problem(row.problem, twoPerDay: row.twoPerDay), row.text)
        }
        XCTAssertNil(PlanWeekText.problemSentence([]))
        XCTAssertEqual(
            PlanWeekText.problemSentence([.muscleRecovery, .cardioBeforeLegs]),
            "Duas sessões de força com os mesmos músculos ficariam a menos de 48 h. Um cardio forte cairia na véspera de pernas.",
            "M5: sem os dois, as duas frases"
        )

        // M5: as saídas.
        let changes: [(change: FitChange, text: String)] = [
            (.addDays([.sunday]), "Treinar também no domingo"),
            (.addDays([.sunday, .tuesday]), "Treinar também na terça e no domingo"),
            (.addDays([.saturday, .monday, .wednesday]), "Treinar também na segunda, na quarta e no sábado"),
            (.allowTwoSessionsPerDay, "Aceitar 2 sessões no mesmo dia"),
            (.allowLightCardioAfterStrength, "Cardio leve depois da força"),
            (.fewerSessions(programID: cardioID, perWeek: 2), "Cardio 2 vezes por semana"),
            (.fewerSessions(programID: cardioID, perWeek: 1), "Cardio 1 vez por semana"),
            (.fewerSessions(programID: UUID(), perWeek: 2), "Este plano 2 vezes por semana"),
        ]
        for row in changes {
            XCTAssertEqual(PlanWeekText.change(row.change, goals: goals), row.text)
        }
        let alternative = FitAlternative(
            changes: [.addDays([.sunday]), .allowTwoSessionsPerDay],
            preferences: WeekPreferences.default,
            schedule: WeekSchedule.empty
        )
        XCTAssertEqual(
            PlanWeekText.changes(of: alternative, goals: goals),
            ["Treinar também no domingo", "Aceitar 2 sessões no mesmo dia"]
        )
        XCTAssertEqual(
            PlanWeekText.spokenChanges(of: alternative, goals: goals),
            "Treinar também no domingo e aceitar 2 sessões no mesmo dia"
        )

        // M4: os avisos.
        let notes: [(note: FitNote, text: String)] = [
            (.noFullRestDay, "Sem um dia de descanso completo."),
            (.strengthBeforeCardio(.tuesday), "Na terça, faça a força antes do cardio."),
            (.strengthBeforeCardio(.saturday), "No sábado, faça a força antes do cardio."),
        ]
        for row in notes {
            XCTAssertEqual(PlanWeekText.note(row.note), row.text)
        }

        // Intensidade pelo teste da fala, nunca FC.
        XCTAssertEqual(PlanWeekText.intensityWord(.light), "leve")
        XCTAssertEqual(PlanWeekText.intensityWord(.moderate), "moderado")
        XCTAssertEqual(PlanWeekText.intensityWord(.vigorous), "forte")
        XCTAssertEqual(PlanWeekText.cardioLabel(nil), "Cardio")

        // M7 e M8: as frases da folha.
        XCTAssertEqual(PlanWeekText.consequenceOrder.map { PlanWeekText.groupTitle($0) }, ["Ganha", "Fica igual", "Custa"])
        XCTAssertEqual(PlanWeekText.consequenceOrder.map { PlanWeekText.sign($0) }, ["+", "=", "−"])
        XCTAssertEqual(
            PlanWeekText.overlapWarning,
            "Os dois planos treinam quase os mesmos levantamentos. Um plano só, ou outro formato, pode bastar."
        )
        XCTAssertEqual(PlanWeekText.noAlternative, "Esses dois planos não cabem juntos na semana. Escolha um só.")
        XCTAssertEqual(PlanWeekText.addTitle(.endurance), "Adicionar Cardio ao seu plano")
        XCTAssertEqual(PlanWeekText.addConfirmTitle(.endurance), "Adicionar Cardio")
        XCTAssertEqual(PlanWeekText.alsoLeaves(.endurance), "O plano de Cardio também sai.")
        XCTAssertEqual(PlanWeekText.removeQuestion(.endurance), "Tirar o plano de Cardio?")
        XCTAssertEqual(PlanWeekText.removeMessage(kept: .hypertrophy), "O plano de Hipertrofia continua. As sessões feitas ficam no Histórico.")
    }

    /// M4: Seg a Dom, a força pelo nome do dia, o aeróbico pela intensidade e "descanso" nos livres.
    func testPlanWeekText_weekRows() throws {
        let schedule = WeekSchedule(
            slots: [
                PlannedSlot(weekday: .thursday, programID: cardioID, indexInWeek: 1, kind: .cardio, orderInDay: 1, dayName: "Dia B — Intervalos 4 × 4", cardioIntensity: .vigorous),
                PlannedSlot(weekday: .monday, programID: hypertrophyID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
                PlannedSlot(weekday: .tuesday, programID: cardioID, indexInWeek: 0, kind: .cardio, orderInDay: 0, dayName: "Dia A — Base contínua", cardioIntensity: .moderate),
                PlannedSlot(weekday: .thursday, programID: hypertrophyID, indexInWeek: 1, kind: .strength, orderInDay: 0, dayName: "Dia C — Superior"),
                PlannedSlot(weekday: .saturday, programID: hypertrophyID, indexInWeek: 2, kind: .strength, orderInDay: 0),
            ],
            notes: [.strengthBeforeCardio(.thursday)]
        )

        let rows = PlanWeekText.weekRows(schedule, goals: goals)

        XCTAssertEqual(rows.map(\.text), [
            "Seg · Dia A — Superior",
            "Ter · Cardio moderado",
            "Qua · descanso",
            "Qui · Dia C — Superior + Cardio forte",
            "Sex · descanso",
            "Sáb · Hipertrofia",
            "Dom · descanso",
        ])
        XCTAssertEqual(rows.map(\.isRest), [false, false, true, false, true, false, true])
        let thursday = try XCTUnwrap(rows.first { $0.day == .thursday })
        XCTAssertEqual(thursday.goals, [.hypertrophy, .endurance], "Na ordem do dia: a força antes")
        XCTAssertEqual(thursday.spokenText, "quinta: Dia C — Superior e Cardio forte")
        XCTAssertEqual(PlanWeekText.notes(schedule), ["Na quinta, faça a força antes do cardio."])
    }

    /// DESIGN §6 e §7: nenhum texto fala em RIR, FC ou usa exclamação.
    func testPlanWeekText_noJargon() {
        let texts: [String] = [
            PlanWeekText.overlapWarning,
            PlanWeekText.noAlternative,
            PlanWeekText.twoSessionsHint,
            PlanWeekText.lightCardioHint,
            PlanWeekText.notFitInPlanTab,
            PlanWeekText.fitsText,
            TodayPlansText.notFitBanner,
            TodayPlansText.restDay,
            PlanWeekText.problem(.muscleRecovery),
            PlanWeekText.problem(.cardioBeforeLegs),
        ]
        for text in texts {
            XCTAssertFalse(text.contains("RIR"), text)
            XCTAssertFalse(text.contains("!"), text)
            XCTAssertFalse(text.lowercased().contains("bpm"), text)
            XCTAssertFalse(text.lowercased().contains("frequência cardíaca"), text)
        }
    }
}
