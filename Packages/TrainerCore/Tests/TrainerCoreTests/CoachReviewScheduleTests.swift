import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.8 ("a cada reviewIntervalWeeks (padrão 4)") and §7.11 C2 ("A cada 4 semanas").

private typealias CF = CoachFixtures

@Suite("Coach — C2 agenda da revisão")
struct CoachReviewScheduleTests {
    static let fourWeeks: TimeInterval = 28 * 86_400

    struct ScheduleCase: Sendable, CustomTestStringConvertible {
        let lastReviewAt: Date?
        let firstSessionAt: Date?
        let intervalWeeks: Int
        let due: Bool
        let label: String

        var testDescription: String { label }
    }

    static let cases: [ScheduleCase] = [
        ScheduleCase(lastReviewAt: nil, firstSessionAt: nil, intervalWeeks: 4, due: false, label: "nunca treinou"),
        ScheduleCase(
            lastReviewAt: nil,
            firstSessionAt: CoachFixtures.now.addingTimeInterval(-fourWeeks + 1),
            intervalWeeks: 4,
            due: false,
            label: "1ª sessão há 4 semanas menos 1 s"
        ),
        ScheduleCase(
            lastReviewAt: nil,
            firstSessionAt: CoachFixtures.now.addingTimeInterval(-fourWeeks),
            intervalWeeks: 4,
            due: true,
            label: "1ª sessão há 4 semanas exatas"
        ),
        ScheduleCase(
            lastReviewAt: CoachFixtures.now.addingTimeInterval(-10 * 86_400),
            firstSessionAt: CoachFixtures.now.addingTimeInterval(-100 * 86_400),
            intervalWeeks: 4,
            due: false,
            label: "última revisão há 10 dias vale mais que a 1ª sessão"
        ),
        ScheduleCase(
            lastReviewAt: CoachFixtures.now.addingTimeInterval(-fourWeeks),
            firstSessionAt: nil,
            intervalWeeks: 4,
            due: true,
            label: "última revisão há 4 semanas"
        ),
        ScheduleCase(
            lastReviewAt: CoachFixtures.now.addingTimeInterval(-14 * 86_400),
            firstSessionAt: nil,
            intervalWeeks: 2,
            due: true,
            label: "intervalo de 2 semanas"
        ),
        ScheduleCase(
            lastReviewAt: CoachFixtures.now.addingTimeInterval(-400 * 86_400),
            firstSessionAt: nil,
            intervalWeeks: 0,
            due: false,
            label: "intervalo 0 desliga"
        ),
        ScheduleCase(
            lastReviewAt: CoachFixtures.now.addingTimeInterval(-400 * 86_400),
            firstSessionAt: nil,
            intervalWeeks: -1,
            due: false,
            label: "intervalo negativo desliga"
        ),
        ScheduleCase(
            lastReviewAt: CoachFixtures.now.addingTimeInterval(86_400),
            firstSessionAt: nil,
            intervalWeeks: 4,
            due: false,
            label: "revisão com data depois de agora"
        ),
    ]

    @Test("C2 revisão vence a cada N semanas desde a última ou desde a 1ª sessão", arguments: CoachReviewScheduleTests.cases)
    func isDue(_ testCase: ScheduleCase) {
        let due = ReviewSchedule.isDue(
            lastReviewAt: testCase.lastReviewAt,
            firstSessionAt: testCase.firstSessionAt,
            now: CF.now,
            intervalWeeks: testCase.intervalWeeks
        )

        #expect(due == testCase.due)
    }

    @Test("C2 o intervalo padrão é de 4 semanas")
    func defaultIntervalIsFourWeeks() {
        let justDue = CF.now.addingTimeInterval(-Self.fourWeeks)
        let almost = CF.now.addingTimeInterval(-Self.fourWeeks + 1)

        #expect(ReviewSchedule.defaultIntervalWeeks == 4)
        #expect(ReviewSchedule.isDue(lastReviewAt: justDue, firstSessionAt: nil, now: CF.now))
        #expect(!ReviewSchedule.isDue(lastReviewAt: almost, firstSessionAt: nil, now: CF.now))
    }
}
