import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Cardio na ficha e na tela Hoje (SPEC §7.14 F1 e F2, RF-43; docs/V23-UI-CONTRACT.md §4.4 item 3): "30 min" ou
/// "4 × 3 min", nunca "1 série de 30 min"; a intensidade pelo teste da fala no lugar da carga; a recuperação
/// andando dos intervalos e a linha fixa de aquecimento. Nada de FC, zonas ou ritmo em números.
final class CardioTextTests: XCTestCase {
    private struct RowCase {
        let sets: Int
        let minutes: Int
        let load: TodayTargetText.LoadDisplay
        let row: String
        let spoken: String
    }

    func testF1_cardioRowTexts() {
        let rows: [RowCase] = [
            RowCase(sets: 1, minutes: 30, load: .hidden, row: "30 min", spoken: "30 minutos"),
            RowCase(sets: 1, minutes: 1, load: .hidden, row: "1 min", spoken: "1 minuto"),
            RowCase(sets: 4, minutes: 3, load: .hidden, row: "4 × 3 min", spoken: "4 vezes 3 minutos"),
            RowCase(sets: 1, minutes: 45, load: .toChoose, row: "45 min", spoken: "45 minutos"),
            RowCase(sets: 1, minutes: 45, load: .load("nível 7"), row: "45 min · nível 7", spoken: "45 minutos, nível 7"),
        ]
        for testCase in rows {
            XCTAssertEqual(
                TodayTargetText.row(sets: testCase.sets, goal: testCase.minutes, measure: .minutes, load: testCase.load),
                testCase.row
            )
            XCTAssertEqual(
                TodayTargetText.spokenRow(sets: testCase.sets, goal: testCase.minutes, measure: .minutes, load: testCase.load),
                testCase.spoken
            )
            XCTAssertEqual(
                TodayTargetText.headline(goal: testCase.minutes, measure: .minutes, load: testCase.load, sets: testCase.sets),
                testCase.row
            )
            XCTAssertFalse(testCase.row.contains("série"), "nunca \"1 série de 30 min\": \(testCase.row)")
        }
        XCTAssertEqual(TodayTargetText.headline(goal: 30, measure: .minutes, load: .hidden), "30 min", "sem `sets`, uma série")

        // A intensidade pelo teste da fala (SPEC F2, `CardioIntensity.classify`).
        XCTAssertEqual(CardioText.intensityLine(.light), "Leve: a conversa é fácil")
        XCTAssertEqual(CardioText.intensityLine(.moderate), "Moderado: dá para conversar, mas não para cantar")
        XCTAssertEqual(CardioText.intensityLine(.vigorous), "Forte: só dá para dizer poucas palavras")
        XCTAssertEqual(CardioText.intensity(pattern: .cardio, slug: "brisk-walk", sets: 1, repMax: 45), .moderate)
        XCTAssertEqual(CardioText.intensity(pattern: .cardio, slug: "run-intervals", sets: 4, repMax: 4), .vigorous)
        XCTAssertEqual(CardioText.intensity(pattern: .cardio, slug: "stationary-bike", sets: 1, repMax: 75), .light)
        XCTAssertNil(CardioText.intensity(pattern: .squat, slug: "barbell-back-squat", sets: 3, repMax: 10), "força não tem intensidade de cardio")
        XCTAssertNil(CardioText.intensity(pattern: nil, slug: "brisk-walk", sets: 1, repMax: 45))

        // Os intervalos: recuperação andando e a linha de aquecimento.
        XCTAssertEqual(CardioText.detail(sets: 4, restSeconds: 180), "4 séries · recuperação andando 3 min")
        XCTAssertNil(CardioText.detail(sets: 1, restSeconds: 60), "uma série não tem descanso a mostrar")
        XCTAssertEqual(CardioText.recoveryTitle, "Recuperação andando")
        XCTAssertEqual(CardioText.intervalsWarmup, "Antes, aqueça 10 minutos andando devagar.")

        // As medidas de força não mudam.
        XCTAssertEqual(TodayTargetText.row(sets: 3, goal: 10, measure: .reps, load: .load("60 kg")), "3 séries de 10 · 60 kg")
        XCTAssertEqual(TodayTargetText.row(sets: 4, goal: 6, measure: .reps, load: .toChoose), "4 séries de 6 · escolha a carga")
    }

    /// SPEC P12 e §7.6: nenhum texto do cardio fala de frequência cardíaca, zonas ou ritmo em números.
    func testF2_cardioTextsHaveNoHeartRate() {
        let intensities: [CardioIntensity] = [.light, .moderate, .vigorous]
        var texts: [String] = [CardioText.recoveryTitle, CardioText.intervalsWarmup]
        for intensity in intensities {
            texts.append(CardioText.intensityLine(intensity))
            texts.append(CardioText.talkTest(intensity))
        }
        for text in texts {
            let lowercased = text.lowercased()
            XCTAssertFalse(lowercased.contains("bpm"), text)
            XCTAssertFalse(lowercased.contains("frequência"), text)
            XCTAssertFalse(lowercased.contains("zona"), text)
            XCTAssertFalse(lowercased.contains("rir"), text)
        }
    }
}
