import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.10 A1: FCmáx (Tanaka), limiares ACSM por % da FCmáx e por % da FC de reserva (Karvonen).
// Datas e calendário fixos (SPEC P11): nada aqui lê o relógio.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// MARK: - FCmáx

@Test(
    "A1 Tanaka: FCmáx = 208 − 0,7 × idade",
    arguments: [(20, 194.0), (25, 190.5), (30, 187.0), (40, 180.0), (60, 166.0), (80, 152.0)]
)
func tanakaMaxHeartRate(age: Int, expected: Double) {
    #expect(HeartRateZones.tanakaMaxHeartRate(ageYears: age) == expected)
}

@Test("A1 FCmáx vem da idade em now quando não há valor informado")
func maxHeartRateFromBirthDate() {
    let physiology = UserPhysiology(birthDate: at(1984, 1, 3))
    #expect(HeartRateZones.maxHeartRate(physiology: physiology, now: at(2024, 1, 3, 12), calendar: utc) == 180)
    // Um dia antes do aniversário ainda tem 39 anos: 208 − 27,3 = 180,7.
    let dayBefore = HeartRateZones.maxHeartRate(physiology: physiology, now: at(2024, 1, 2, 23, 59), calendar: utc)
    #expect(abs((dayBefore ?? 0) - 180.7) < 1e-9)
}

@Test("A1 FCmáx informada pelo usuário prevalece sobre Tanaka")
func maxHeartRateOverrideWins() {
    let physiology = UserPhysiology(birthDate: at(1984, 1, 1), maxHeartRateOverride: 200)
    #expect(HeartRateZones.maxHeartRate(physiology: physiology, now: at(2024, 6, 1), calendar: utc) == 200)
}

@Test("A1 FCmáx informada zero ou negativa é ignorada")
func maxHeartRateInvalidOverrideIgnored() {
    let withAge = UserPhysiology(birthDate: at(1984, 1, 1), maxHeartRateOverride: 0)
    #expect(HeartRateZones.maxHeartRate(physiology: withAge, now: at(2024, 6, 1), calendar: utc) == 180)
    let withoutAge = UserPhysiology(maxHeartRateOverride: -5)
    #expect(HeartRateZones.maxHeartRate(physiology: withoutAge, now: at(2024, 6, 1), calendar: utc) == nil)
}

@Test("A1 sem idade e sem FCmáx informada não há zonas")
func noAgeNoOverrideNoZones() {
    #expect(HeartRateZones.make(physiology: UserPhysiology(), restingHeartRate: 60, now: at(2024, 6, 1), calendar: utc) == nil)
}

@Test("A1 data de nascimento no futuro não gera idade")
func futureBirthDateHasNoAge() {
    let physiology = UserPhysiology(birthDate: at(2030, 1, 1))
    #expect(physiology.ageYears(at: at(2024, 6, 1), calendar: utc) == nil)
}

// MARK: - % da FCmáx (sem FC de repouso)

@Test(
    "A1 % FCmáx: leve < 64 % ≤ moderado < 77 % ≤ vigoroso (FCmáx 200)",
    arguments: [
        (100.0, AerobicIntensity.light),
        (127.0, .light),       // 63,5 %
        (128.0, .moderate),    // 64 % exato: início inclusivo
        (140.0, .moderate),    // 70 %
        (153.0, .moderate),    // 76,5 %: "64–76 %" vai até antes de 77 %
        (154.0, .vigorous),    // 77 % exato
        (170.0, .vigorous),    // 85 %
        (210.0, .vigorous),    // acima da FCmáx continua vigoroso
    ]
)
func percentOfMaxClassification(heartRate: Double, expected: AerobicIntensity) {
    let zones = HeartRateZones(maxHeartRate: 200)
    #expect(!zones.usesHeartRateReserve)
    #expect(zones.intensity(forHeartRate: heartRate) == expected)
}

@Test("A1 limiares exatos com FCmáx de Tanaka não caem do lado errado por arredondamento binário")
func thresholdsExactWithTanaka() {
    let zones = HeartRateZones(maxHeartRate: 180)
    #expect(zones.intensity(forHeartRate: 180 * 0.64) == .moderate)
    #expect(zones.intensity(forHeartRate: 180 * 0.77) == .vigorous)
    #expect(zones.intensity(forHeartRate: 126) == .moderate)  // 70 % (CA5-1)
    #expect(zones.intensity(forHeartRate: 153) == .vigorous)  // 85 % (CA5-1)
}

// MARK: - % da FC de reserva (Karvonen)

@Test(
    "A1 Karvonen: leve < 40 % ≤ moderado < 60 % ≤ vigoroso da FC de reserva (FCmáx 200, repouso 50)",
    arguments: [
        (109.0, AerobicIntensity.light),  // 39,3 %
        (110.0, .moderate),               // 40 % exato
        (138.5, .moderate),               // 59 %
        (140.0, .vigorous),               // 60 % exato
        (185.0, .vigorous),               // 90 %
    ]
)
func heartRateReserveClassification(heartRate: Double, expected: AerobicIntensity) {
    let zones = HeartRateZones(maxHeartRate: 200, restingHeartRate: 50)
    #expect(zones.usesHeartRateReserve)
    #expect(zones.intensity(forHeartRate: heartRate) == expected)
}

@Test("A1 a FC de repouso muda a classificação: 110 bpm é leve por % FCmáx e moderado por reserva")
func reserveChangesClassification() {
    let byMax = HeartRateZones(maxHeartRate: 180)
    let byReserve = HeartRateZones(maxHeartRate: 180, restingHeartRate: 60)
    #expect(byMax.intensity(forHeartRate: 110) == .light)        // 61 % da FCmáx
    #expect(byReserve.intensity(forHeartRate: 110) == .moderate) // 41,7 % da reserva
    #expect(byMax.intensity(forHeartRate: 135) == .moderate)     // 75 % da FCmáx
    #expect(byReserve.intensity(forHeartRate: 135) == .vigorous) // 62,5 % da reserva
}

@Test("A1 FC de repouso inválida (zero, negativa, ≥ FCmáx, NaN) cai para % da FCmáx")
func invalidRestingFallsBackToPercentOfMax() {
    for resting in [0.0, -10, 200, 250, .nan] {
        let zones = HeartRateZones(maxHeartRate: 200, restingHeartRate: resting)
        #expect(zones.restingHeartRate == nil)
        #expect(zones.intensity(forHeartRate: 128) == .moderate)
    }
}

@Test("A1 leitura de FC inválida não é classificada (o minuto usa a intensidade padrão)")
func invalidHeartRateReading() {
    let zones = HeartRateZones(maxHeartRate: 200)
    #expect(zones.intensity(forHeartRate: 0) == nil)
    #expect(zones.intensity(forHeartRate: -1) == nil)
    #expect(zones.intensity(forHeartRate: .nan) == nil)
    #expect(zones.intensity(forHeartRate: .infinity) == nil)
}

// MARK: - Intensidade padrão por tipo de treino

@Test(
    "A1 intensidade padrão por tipo: corrida, HIIT e escada vigorosos; o resto moderado",
    arguments: [
        (AerobicActivity.walking, AerobicIntensity.moderate),
        (.running, .vigorous),
        (.cycling, .moderate),
        (.swimming, .moderate),
        (.rowing, .moderate),
        (.elliptical, .moderate),
        (.hiking, .moderate),
        (.stairs, .vigorous),
        (.hiit, .vigorous),
        (.dance, .moderate),
        (.other, .moderate),
    ]
)
func defaultIntensityPerActivity(activity: AerobicActivity, expected: AerobicIntensity) {
    #expect(activity.defaultIntensity == expected)
    #expect(!activity.displayName.isEmpty)
}

@Test("Raw values persistidos são estáveis")
func stableRawValues() {
    #expect(AerobicActivity.allCases.map(\.rawValue) == [
        "walking", "running", "cycling", "swimming", "rowing", "elliptical", "hiking", "stairs", "hiit", "dance", "other",
    ])
    #expect(AerobicIntensity.allCases.map(\.rawValue) == ["light", "moderate", "vigorous"])
    #expect(BiologicalSexValue.allCases.map(\.rawValue) == ["female", "male", "other"])
    #expect(FitnessBand.allCases.map(\.rawValue) == ["veryPoor", "poor", "fair", "good", "excellent", "superior"])
    #expect(RecoveryAlert.allCases.map(\.rawValue) == ["hrvDrop", "restingHeartRateRise", "lowSleep"])
    #expect(HealthSuggestionKind.allCases.map(\.rawValue) == [
        "wearWatchAtNight", "updateVo2Max", "aerobicDeficit", "lowSleep", "recoveryAlert", "lowSteps",
    ])
    #expect(FitnessBand.allCases.map(\.displayName) == ["Muito baixo", "Baixo", "Regular", "Bom", "Excelente", "Superior"])
}

@Test("HealthTargets: padrões OMS 150 min, 7.000 passos e 7 h de sono")
func healthTargetDefaults() {
    let targets = HealthTargets()
    #expect(targets.weeklyModerateEquivalentMinutes == 150)
    #expect(targets.dailySteps == 7000)
    #expect(targets.sleepHours == 7)
}
