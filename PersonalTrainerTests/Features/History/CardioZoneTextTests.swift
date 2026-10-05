import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// SPEC §7.14 F7 (2.4): a seção "Coração" do detalhe de uma sessão de aeróbico no Histórico. Cada minuto
/// pela `HeartRateZones.intensity(forHeartRate:)` (as zonas de A1), o VO2máx com a faixa (A3) e, sem FC e
/// sem VO2máx, nenhuma seção. Só funções puras; tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class CardioZoneTextTests: XCTestCase {
    private struct ZoneCase {
        let name: String
        let zones: HeartRateZones
        let heartRates: [Double]
        let expected: CardioZoneText.ZoneMinutes
    }

    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    func testF7_zoneMinutesTable() {
        // FCmáx 200 sem repouso: moderado a partir de 128 (64 %), forte a partir de 154 (77 %).
        let byMax = HeartRateZones(maxHeartRate: 200)
        // Com repouso 60: reserva 140; moderado a partir de 116 (40 %), forte a partir de 144 (60 %).
        let byReserve = HeartRateZones(maxHeartRate: 200, restingHeartRate: 60)
        let cases: [ZoneCase] = [
            ZoneCase(
                name: "% da FCmáx, um minuto por leitura",
                zones: byMax,
                heartRates: [100, 120, 130, 150, 160, 170],
                expected: CardioZoneText.ZoneMinutes(light: 2, moderate: 2, vigorous: 2)
            ),
            ZoneCase(
                name: "minuto sem leitura fica fora (0, negativo, não finito)",
                zones: byMax,
                heartRates: [0, -5, .nan, .infinity, 130],
                expected: CardioZoneText.ZoneMinutes(light: 0, moderate: 1, vigorous: 0)
            ),
            ZoneCase(
                name: "limites inclusivos no começo de cada faixa",
                zones: byMax,
                heartRates: [127, 128, 153, 154],
                expected: CardioZoneText.ZoneMinutes(light: 1, moderate: 2, vigorous: 1)
            ),
            ZoneCase(
                name: "% da FC de reserva com repouso",
                zones: byReserve,
                heartRates: [110, 116, 143, 144],
                expected: CardioZoneText.ZoneMinutes(light: 1, moderate: 2, vigorous: 1)
            ),
            ZoneCase(
                name: "sem leitura nenhuma",
                zones: byMax,
                heartRates: [],
                expected: CardioZoneText.ZoneMinutes(light: 0, moderate: 0, vigorous: 0)
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                CardioZoneText.zoneMinutes(heartRates: testCase.heartRates, zones: testCase.zones),
                testCase.expected,
                testCase.name
            )
        }

        // A frase do contrato e as intensidades sem minuto fora dela.
        XCTAssertEqual(
            CardioZoneText.zonesLine(CardioZoneText.ZoneMinutes(light: 6, moderate: 22, vigorous: 12)),
            "Leve 6 min · Moderada 22 min · Forte 12 min"
        )
        XCTAssertEqual(
            CardioZoneText.zonesLine(CardioZoneText.ZoneMinutes(light: 0, moderate: 30, vigorous: 0)),
            "Moderada 30 min"
        )
        XCTAssertNil(CardioZoneText.zonesLine(CardioZoneText.ZoneMinutes(light: 0, moderate: 0, vigorous: 0)))
        XCTAssertEqual(
            CardioZoneText.spokenZones(CardioZoneText.ZoneMinutes(light: 6, moderate: 22, vigorous: 1)),
            "Leve 6 minutos, moderada 22 minutos, forte 1 minuto"
        )

        // VO2máx com a faixa, em minúsculas; sem faixa, só o número.
        XCTAssertEqual(
            CardioZoneText.vo2MaxLine(Vo2MaxSummary(latest: 42.14, latestDate: date, change90Days: nil, band: .good, ageYears: 40)),
            "VO2máx: 42,1 (bom)"
        )
        XCTAssertEqual(
            CardioZoneText.vo2MaxLine(Vo2MaxSummary(latest: 44, latestDate: date, change90Days: 1, band: .excellent, ageYears: 35)),
            "VO2máx: 44 (excelente)"
        )
        XCTAssertEqual(
            CardioZoneText.vo2MaxLine(Vo2MaxSummary(latest: 38.5, latestDate: date, change90Days: nil, band: nil, ageYears: nil)),
            "VO2máx: 38,5"
        )

        // Só uma sessão em que todo exercício com série é aeróbico.
        XCTAssertTrue(CardioZoneText.isAerobicSession([.cardio]))
        XCTAssertTrue(CardioZoneText.isAerobicSession([.cardio, .cardio]))
        XCTAssertFalse(CardioZoneText.isAerobicSession([.cardio, .squat]), "sessão mista não tem a seção")
        XCTAssertFalse(CardioZoneText.isAerobicSession([nil]), "sem catálogo, não é aeróbico")
        XCTAssertFalse(CardioZoneText.isAerobicSession([]), "sem nenhuma série, nada")

        // Com FC e zonas: os minutos; o VO2máx junto quando existe.
        let content = CardioZoneText.content(
            heartRates: [100, 130, 160],
            zones: byMax,
            vo2Max: Vo2MaxSummary(latest: 42.14, latestDate: date, change90Days: nil, band: .good, ageYears: 40)
        )
        XCTAssertEqual(content?.zones, CardioZoneText.ZoneMinutes(light: 1, moderate: 1, vigorous: 1))
        XCTAssertEqual(content?.vo2MaxLine, "VO2máx: 42,1 (bom)")
    }

    func testF7_noHeartRateNoSection() async {
        let zones = HeartRateZones(maxHeartRate: 190)
        let vo2Max = Vo2MaxSummary(latest: 42.14, latestDate: date, change90Days: nil, band: .good, ageYears: 40)

        XCTAssertNil(CardioZoneText.content(heartRates: [], zones: zones, vo2Max: nil), "sem FC e sem VO2máx")
        XCTAssertNil(CardioZoneText.content(heartRates: [150, 160], zones: nil, vo2Max: nil), "sem zonas (sem idade), não há conta")
        XCTAssertNil(CardioZoneText.content(heartRates: [0, .nan], zones: zones, vo2Max: nil), "nenhum minuto com leitura")

        let onlyVo2 = CardioZoneText.content(heartRates: [], zones: zones, vo2Max: vo2Max)
        XCTAssertNil(onlyVo2?.zones, "sem FC, só o VO2máx")
        XCTAssertEqual(onlyVo2?.vo2MaxLine, "VO2máx: 42,1 (bom)")

        // Sem injeção na raiz, o padrão não lê nada: a seção não aparece.
        let lookup = CardioHeartRateLookup.none
        let rates = await lookup.minuteHeartRates(date, date.addingTimeInterval(1_800))
        XCTAssertTrue(rates.isEmpty)
        XCTAssertNil(lookup.zones())
        XCTAssertNil(lookup.latestVo2Max())
        XCTAssertNil(CardioZoneText.content(heartRates: rates, zones: lookup.zones(), vo2Max: lookup.latestVo2Max()))

        // O que o integrador passa: três fechos.
        let injected = CardioHeartRateLookup(
            minuteHeartRates: { _, _ in [100, 130, 160] },
            zones: { zones },
            latestVo2Max: { nil }
        )
        let injectedRates = await injected.minuteHeartRates(date, date.addingTimeInterval(180))
        let injectedContent = CardioZoneText.content(
            heartRates: injectedRates,
            zones: injected.zones(),
            vo2Max: injected.latestVo2Max()
        )
        XCTAssertEqual(injectedContent?.zones?.total, 3)
        XCTAssertNil(injectedContent?.vo2MaxLine)
    }
}
