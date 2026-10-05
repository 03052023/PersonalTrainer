import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.3: textos da tela "Metas da semana" (SPEC RF-52, §7.16 W3/W4/W6; DESIGN §9.2): o número em
/// palavras de cada meta, "sem dados" no lugar de falha e a leitura do VoiceOver. Só fatos: nada de
/// porcentagem, "faltam" nem frase de efeito.
final class WeeklyGoalsTextTests: XCTestCase {
    private func goal(
        _ kind: WeeklyGoalKind,
        done: Double?,
        target: Double,
        planGoal: ProgramGoal? = nil
    ) -> WeeklyGoal {
        WeeklyGoal(kind: kind, planGoal: planGoal, done: done, target: target, referenceTopic: "topic.test")
    }

    func testRF52_valueText_inWords() {
        XCTAssertEqual(
            WeeklyGoalsText.valueText(goal(.planSessions, done: 3, target: 4, planGoal: .hypertrophy)),
            "3 de 4 sessões"
        )
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.muscles, done: 6, target: 10)), "6 de 10 grupos 2 vezes")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.aerobic, done: 95, target: 150)), "95 de 150 min")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.steps, done: 6_200, target: 7_000)), "média de 6.200 por dia")
        XCTAssertEqual(
            WeeklyGoalsText.valueText(goal(.sleep, done: 7.0 + 20.0 / 60.0, target: 7)),
            "média de 7 h 20 min"
        )
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.balance, done: 1, target: 2)), "1 de 2 vezes")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.mobility, done: 0, target: 2)), "0 de 2 vezes")
    }

    /// SPEC W2.6, §7.17 X6 (2.4): equilíbrio e mobilidade contam as vezes registradas na semana contra 2.
    func testW26_longevityTimesText() {
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.balance, done: 0, target: 2)), "0 de 2 vezes")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.balance, done: 1, target: 2)), "1 de 2 vezes")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.mobility, done: 2, target: 2)), "2 de 2 vezes")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.mobility, done: 3, target: 2)), "3 de 2 vezes", "W3: o número real")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.balance, done: 1, target: 1)), "1 de 1 vez", "singular com meta 1")
        XCTAssertEqual(
            WeeklyGoalsText.accessibilityText(goal(.balance, done: 1, target: 2)),
            "Equilíbrio: 1 de 2 vezes nesta semana"
        )
        XCTAssertEqual(
            WeeklyGoalsText.accessibilityText(goal(.mobility, done: 2, target: 2)),
            "Mobilidade: 2 de 2 vezes nesta semana, meta cumprida"
        )
    }

    func testRF52_valueText_singularWhenTheTargetIsOne() {
        XCTAssertEqual(
            WeeklyGoalsText.valueText(goal(.planSessions, done: 0, target: 1, planGoal: .longevity)),
            "0 de 1 sessão"
        )
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.muscles, done: 0, target: 1)), "0 de 1 grupo 2 vezes")
    }

    func testRF52_valueText_overTheTargetShowsTheRealNumber() {
        // W3: passar da meta mostra o número real, com a marca cheia.
        XCTAssertEqual(
            WeeklyGoalsText.valueText(goal(.planSessions, done: 5, target: 4, planGoal: .strength)),
            "5 de 4 sessões"
        )
    }

    func testW4_noData_saysSemDadosNeverAFailure() {
        let aerobic = goal(.aerobic, done: nil, target: 150)
        XCTAssertEqual(WeeklyGoalsText.valueText(aerobic), "sem dados")
        XCTAssertEqual(WeeklyGoalsText.accessibilityText(aerobic), "Aeróbico: sem dados")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.steps, done: nil, target: 7_000)), "sem dados")
        XCTAssertEqual(WeeklyGoalsText.valueText(goal(.sleep, done: nil, target: 7)), "sem dados")
    }

    func testRF52_titles() {
        XCTAssertEqual(WeeklyGoalsText.title(goal(.planSessions, done: 0, target: 3, planGoal: .hypertrophy)), "Hipertrofia")
        XCTAssertEqual(WeeklyGoalsText.title(goal(.muscles, done: 0, target: 10)), "Músculos")
        XCTAssertEqual(WeeklyGoalsText.title(goal(.aerobic, done: 0, target: 150)), "Aeróbico")
        XCTAssertEqual(WeeklyGoalsText.title(goal(.steps, done: 0, target: 7_000)), "Passos")
        XCTAssertEqual(WeeklyGoalsText.title(goal(.sleep, done: 0, target: 7)), "Sono")
        XCTAssertEqual(WeeklyGoalsText.title(goal(.balance, done: 0, target: 1)), "Equilíbrio")
        XCTAssertEqual(WeeklyGoalsText.title(goal(.mobility, done: 0, target: 1)), "Mobilidade")
    }

    func testRF52_accessibilityText_oneElementPerRow() {
        XCTAssertEqual(
            WeeklyGoalsText.accessibilityText(goal(.planSessions, done: 3, target: 4, planGoal: .hypertrophy)),
            "Hipertrofia: 3 de 4 sessões nesta semana"
        )
        XCTAssertEqual(
            WeeklyGoalsText.accessibilityText(goal(.planSessions, done: 4, target: 4, planGoal: .hypertrophy)),
            "Hipertrofia: 4 de 4 sessões nesta semana, meta cumprida"
        )
        XCTAssertEqual(
            WeeklyGoalsText.accessibilityText(goal(.steps, done: 7_200, target: 7_000)),
            "Passos: média de 7.200 por dia, meta cumprida"
        )
        XCTAssertEqual(
            WeeklyGoalsText.accessibilityText(goal(.balance, done: 1, target: 2)),
            "Equilíbrio: 1 de 2 vezes nesta semana"
        )
    }

    func testRF52_muscleDetailText() {
        let entry = WeeklyFrequencyEntry(muscle: .chest, completed: 1, target: 2)
        XCTAssertEqual(WeeklyGoalsText.muscleDetailText(entry), "Peito 1 de 2")
    }

    func testW6_textsNeverUsePercentOrRemainingOrCheers() {
        let goals = [
            goal(.planSessions, done: 1, target: 4, planGoal: .endurance),
            goal(.muscles, done: 2, target: 10),
            goal(.aerobic, done: 40, target: 150),
            goal(.aerobic, done: nil, target: 150),
            goal(.steps, done: 3_000, target: 7_000),
            goal(.sleep, done: 6, target: 7),
            goal(.balance, done: 0, target: 2),
            goal(.mobility, done: 2, target: 2),
        ]
        for goal in goals {
            let texts = [
                WeeklyGoalsText.title(goal),
                WeeklyGoalsText.valueText(goal),
                WeeklyGoalsText.accessibilityText(goal),
            ]
            for text in texts {
                XCTAssertFalse(text.contains("%"), text)
                XCTAssertFalse(text.lowercased().contains("falta"), text)
                XCTAssertFalse(text.contains("!"), text)
            }
        }
    }
}
