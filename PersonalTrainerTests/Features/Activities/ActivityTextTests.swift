import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.5: textos das atividades fora do app (SPEC §7.17 X1, X2, X7, RF-49, RF-53; DESIGN §7, §9 item 8,
/// §9.1, §9.3). Só o fato ("Pilates · terça · 50 min · leve", "Também hoje: Pilates às 19h"), sem elogio,
/// "!" nem frase de efeito (decisão 20). Calendário gregoriano em UTC, fixo (SPEC P11).
final class ActivityTextTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// Segunda-feira, 2026-09-28, 00:00 UTC.
    private let mondayMidnight = Date(timeIntervalSince1970: 1_790_553_600)

    private func fixed(
        _ kind: OutsideActivityKind,
        _ weekday: PlanWeekday,
        minute: Int,
        minutes: Int = 50,
        intensity: CardioIntensity = .light
    ) -> FixedOutsideActivity {
        FixedOutsideActivity(kind: kind, weekday: weekday, startMinuteOfDay: minute, minutes: minutes, intensity: intensity)
    }

    func testRF53_textsTable() {
        // Linhas da semana (DESIGN §9.3 ponto 1): o dia em palavras, a duração e a intensidade.
        let tuesdayPilates = OutsideActivityEntry(
            kind: .pilates,
            start: mondayMidnight.addingTimeInterval(86_400 + 19 * 3_600),
            minutes: 50,
            intensity: .light
        )
        XCTAssertEqual(ActivityText.entryLine(tuesdayPilates, calendar: calendar), "Pilates · terça · 50 min · leve")
        XCTAssertEqual(ActivityText.entryDetails(tuesdayPilates, calendar: calendar), "terça · 50 min · leve")
        XCTAssertEqual(ActivityText.entrySpoken(tuesdayPilates, calendar: calendar), "Pilates, terça, 50 minutos, leve")

        let saturdayFootball = OutsideActivityEntry(
            kind: .teamSport,
            start: mondayMidnight.addingTimeInterval(5 * 86_400 + 9 * 3_600),
            minutes: 60,
            intensity: .vigorous
        )
        XCTAssertEqual(
            ActivityText.entryLine(saturdayFootball, calendar: calendar),
            "Futebol ou esporte com bola · sábado · 60 min · forte"
        )
        let sundaySwim = OutsideActivityEntry(
            kind: .swimming,
            start: mondayMidnight.addingTimeInterval(6 * 86_400 + 8 * 3_600),
            minutes: 45,
            intensity: .moderate
        )
        XCTAssertEqual(ActivityText.entryLine(sundaySwim, calendar: calendar), "Natação · domingo · 45 min · moderada")

        // Fixas (aba Plano, DESIGN §9.3 ponto 3) e "Também hoje" (tela Hoje, §9 item 8).
        let pilates = fixed(.pilates, .tuesday, minute: 19 * 60)
        XCTAssertEqual(ActivityText.fixedLine(pilates), "Pilates · terça · 19h · 50 min")
        XCTAssertEqual(ActivityText.todayFixedLine(pilates), "Pilates · 19h · 50 min")
        XCTAssertEqual(ActivityText.fixedSpoken(pilates), "Pilates, toda terça às 19h, 50 minutos, leve")
        XCTAssertEqual(ActivityText.todayFixedSpoken(pilates), "Pilates às 19h, 50 minutos")
        let earlyCross = fixed(.cross, .saturday, minute: 7 * 60 + 5, minutes: 60, intensity: .vigorous)
        XCTAssertEqual(ActivityText.fixedLine(earlyCross), "Cross ou funcional · sábado · 7h05 · 60 min")
        XCTAssertEqual(ActivityText.fixedSpoken(earlyCross), "Cross ou funcional, todo sábado às 7h05, 60 minutos, forte")

        // "Também hoje" do Início (RF-49): uma, duas e três fixas.
        let football = fixed(.teamSport, .tuesday, minute: 21 * 60, minutes: 60, intensity: .vigorous)
        let dance = fixed(.dance, .tuesday, minute: 22 * 60 + 30, minutes: 60, intensity: .moderate)
        XCTAssertNil(ActivityText.alsoTodayLine([]))
        XCTAssertEqual(ActivityText.alsoTodayLine([pilates]), "Também hoje: Pilates às 19h")
        XCTAssertEqual(
            ActivityText.alsoTodayLine([pilates, football]),
            "Também hoje: Pilates às 19h e Futebol ou esporte com bola às 21h"
        )
        XCTAssertEqual(
            ActivityText.alsoTodayLine([pilates, football, dance]),
            "Também hoje: Pilates às 19h, Futebol ou esporte com bola às 21h e Dança às 22h30"
        )
    }

    func testRF53_timeAndPrepositions() {
        XCTAssertEqual(ActivityText.timeText(minuteOfDay: 0), "0h")
        XCTAssertEqual(ActivityText.timeText(minuteOfDay: 7 * 60 + 5), "7h05")
        XCTAssertEqual(ActivityText.timeText(minuteOfDay: 19 * 60), "19h")
        XCTAssertEqual(ActivityText.timeText(minuteOfDay: 19 * 60 + 30), "19h30")
        XCTAssertEqual(ActivityText.timeText(minuteOfDay: 1_439), "23h59")
        XCTAssertEqual(ActivityText.timeText(minuteOfDay: 5_000), "23h59", "fora da faixa fica no limite")
        XCTAssertEqual(ActivityText.atTime(minuteOfDay: 60), "à 1h")
        XCTAssertEqual(ActivityText.atTime(minuteOfDay: 0), "à 0h")
        XCTAssertEqual(ActivityText.atTime(minuteOfDay: 2 * 60), "às 2h")
        XCTAssertEqual(ActivityText.everyWeekday(.tuesday), "toda terça")
        XCTAssertEqual(ActivityText.everyWeekday(.sunday), "todo domingo")
        XCTAssertEqual(ActivityText.repeatHint(weekday: .monday, minuteOfDay: 8 * 60 + 15), "Repete toda segunda às 8h15.")
    }

    func testRF53_talkTestLinesAndIntensityNames() {
        XCTAssertEqual(ActivityText.talkTestLine(.light), "Leve: a conversa é fácil")
        XCTAssertEqual(ActivityText.talkTestLine(.moderate), "Moderada: dá para conversar, mas não para cantar")
        XCTAssertEqual(ActivityText.talkTestLine(.vigorous), "Forte: só dá para dizer poucas palavras")
        XCTAssertEqual(CardioIntensity.allCases.map { ActivityText.intensityName($0) }, ["Leve", "Moderada", "Forte"])
        XCTAssertEqual(CardioIntensity.allCases.map { ActivityText.intensityWord($0) }, ["leve", "moderada", "forte"])
    }

    /// Decisão 20, itens 15 e 16: nenhum texto das atividades cobra, elogia ou fala de FC.
    func testX7_textsAreFactsOnly() {
        var texts: [String] = [
            ActivityText.sectionTitle, ActivityText.register, ActivityText.fixedTitle, ActivityText.addFixed,
            ActivityText.everyWeek, ActivityText.alsoToday, ActivityText.done, ActivityText.doneMark,
            ActivityText.delete, ActivityText.nothingThisWeek, ActivityText.noFixed, ActivityText.fixedFootnote,
            ActivityText.fixedLimitReached, ActivityText.aerobicFromActivitiesOnly, ActivityText.deleteQuestion,
            ActivityText.deleteEntryMessage, ActivityText.deleteFixedMessage, ActivityText.saveFailed,
            ActivityText.invalidMinutes, ActivityText.fixedLimit, ActivityText.futureEntry,
            ActivityText.missingEntry, ActivityText.missingFixed,
        ]
        texts.append(contentsOf: CardioIntensity.allCases.map { ActivityText.talkTestLine($0) })
        let forbidden: [String] = [
            "!", "parabéns", "ótimo", "incrível", "sequência", "dias seguidos", "faltam", "bpm", "fc ", "rir",
        ]
        for text in texts {
            for word in forbidden {
                XCTAssertFalse(text.lowercased().contains(word), "\"\(text)\" contém \"\(word)\"")
            }
        }
    }
}
