import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Frases da folha "Informações do exercício" (SPEC RF-47, RF-41; docs/V22-CONTRACT.md §3.2):
/// "Hoje", "Por que esta carga" e "Da última vez". Só funções puras de `ExerciseInfoText`.
@MainActor
final class ExerciseInfoTextTests: XCTestCase {

    // MARK: - "Hoje" (RF-47)

    func testRF47_today_sentencePerMeasureAndLoad() {
        let normalLoad = makeContent(note: .hold, measure: .reps, load: 62.5, sets: 3, targetReps: 3, restSeconds: 240)
        XCTAssertEqual(
            ExerciseInfoText.today(normalLoad),
            "3 séries de 3 repetições com 62,5 kg. Descanso de 4 min entre as séries."
        )

        let bodyweightHidden = makeContent(
            note: .hold, equipment: .bodyweight, load: nil, sets: 3, targetReps: 5, restSeconds: 240
        )
        XCTAssertEqual(
            ExerciseInfoText.today(bodyweightHidden),
            "3 séries de 5 repetições, com o peso do corpo. Descanso de 4 min entre as séries."
        )

        let bodyweightExtra = makeContent(
            note: .increase, equipment: .bodyweight, load: 2.5, sets: 3, targetReps: 5, restSeconds: 240
        )
        XCTAssertEqual(
            ExerciseInfoText.today(bodyweightExtra),
            "3 séries de 5 repetições com + 2,5 kg extra. Descanso de 4 min entre as séries."
        )

        let firstTimeToChoose = makeContent(
            note: .calibrate, equipment: .barbell, load: nil, sets: 4, targetReps: 6, restSeconds: 90
        )
        XCTAssertEqual(
            ExerciseInfoText.today(firstTimeToChoose),
            "4 séries de 6 repetições. A carga é opcional. Descanso de 1 min 30 s entre as séries."
        )

        let seconds = makeContent(
            note: .hold, measure: .seconds, load: 20, sets: 2, targetReps: 15, restSeconds: 60
        )
        XCTAssertEqual(
            ExerciseInfoText.today(seconds),
            "2 séries de 15 segundos com 20 kg. Descanso de 1 min entre as séries."
        )

        let steps = makeContent(
            note: .hold, measure: .steps, load: 22.5, sets: 3, targetReps: 30, restSeconds: 45
        )
        XCTAssertEqual(
            ExerciseInfoText.today(steps),
            "3 séries de 30 passos com 22,5 kg. Descanso de 45 s entre as séries."
        )
    }

    // MARK: - Título "Por que esta carga"

    func testRF47_whyTitle_namesTheLoadOnlyWhenConcrete() {
        XCTAssertEqual(ExerciseInfoText.whyTitle(makeContent(note: .hold, load: 62.5)), "Por que 62,5 kg")
        XCTAssertEqual(
            ExerciseInfoText.whyTitle(makeContent(note: .hold, equipment: .bodyweight, load: nil)),
            "Por que assim hoje"
        )
        XCTAssertEqual(
            ExerciseInfoText.whyTitle(makeContent(note: .increase, equipment: .bodyweight, load: 2.5)),
            "Por que assim hoje"
        )
        XCTAssertEqual(
            ExerciseInfoText.whyTitle(makeContent(note: .calibrate, load: nil)),
            "Por que assim hoje"
        )
    }

    // MARK: - "Por que esta carga" por nota (com histórico, SPEC P4–P9)

    func testRF47_why_sentencePerNote() {
        let increase = makeContent(
            note: .increase, load: 62.5, repMin: 3, repMax: 5,
            lastSession: lastSession(sets: [(60, 5), (60, 5), (60, 5)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(increase),
            "Na última vez você fez 5, 5 e 5 com 60 kg, o máximo de 3 a 5. "
                + "A carga sobe 2,5 kg e as repetições recomeçam em 3."
        )

        let hold = makeContent(
            note: .hold, targetReps: 10, repMin: 8, repMax: 12,
            lastSession: lastSession(sets: [(60, 9), (60, 9), (60, 9)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(hold),
            "Na última vez você fez 9, 9 e 9 com 60 kg, dentro da faixa de 8 a 12. "
                + "A carga fica a mesma e a meta sobe para 10 repetições."
        )

        let retry = makeContent(
            note: .retry, repMin: 8,
            lastSession: lastSession(sets: [(60, 6), (60, 7), (60, 6)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(retry),
            "Na última vez você fez 6, 7 e 6 com 60 kg, abaixo do mínimo de 8. "
                + "A carga se repete para confirmar se foi só esse dia."
        )

        let decrease = makeContent(
            note: .decrease, load: 54, repMin: 8,
            lastSession: lastSession(sets: [(60, 6), (60, 6), (60, 6)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(decrease),
            "Na última vez você fez 6, 6 e 6 com 60 kg, abaixo do mínimo de 8 de novo. "
                + "A carga desce para 54 kg."
        )

        let returning = makeContent(
            note: .returning, load: 54,
            lastSession: lastSession(sets: [(60, 8), (60, 8), (60, 8)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(returning),
            "Faz mais de 3 semanas que você não faz este exercício. "
                + "A carga volta a 54 kg, um pouco abaixo dos 60 kg da última vez."
        )

        let deload = makeContent(
            note: .deload, load: 51, sets: 2,
            lastSession: lastSession(sets: [(60, 8), (60, 8)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(deload),
            "Semana leve: 2 séries com 51 kg, um pouco menos que o normal, para descansar sem perder o ganho."
        )
    }

    func testRF47_why_calibrateVariants() {
        let bodyweight = makeContent(note: .calibrate, equipment: .bodyweight, load: nil, targetReps: 8)
        XCTAssertEqual(
            ExerciseInfoText.why(bodyweight),
            "Primeira vez: faça 8 repetições com boa técnica; a próxima sessão se ajusta."
        )

        let withStartingLoad = makeContent(note: .calibrate, equipment: .barbell, load: 40)
        XCTAssertEqual(
            ExerciseInfoText.why(withStartingLoad),
            "Primeira vez com este exercício: comece com 40 kg e ajuste a partir da próxima sessão."
        )

        let toChooseReps = makeContent(
            note: .calibrate, equipment: .barbell, measure: .reps, load: nil, targetReps: 8, targetRIR: 3
        )
        XCTAssertEqual(
            ExerciseInfoText.why(toChooseReps),
            "Escolha uma carga que daria para levantar umas 11 vezes. Hoje faça 8."
        )

        let toChooseSeconds = makeContent(
            note: .calibrate, equipment: .barbell, measure: .seconds, load: nil, targetReps: 15
        )
        XCTAssertEqual(
            ExerciseInfoText.why(toChooseSeconds),
            "Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça 15 segundos."
        )
    }

    // MARK: - RF-46: peso do corpo com histórico, sem "0 kg"

    func testRF46_why_bodyweightHasNoZeroKg() {
        let noExtra = lastSession(sets: [(0, 5), (0, 5), (0, 5)])

        let hold = makeContent(
            note: .hold, equipment: .bodyweight, load: 0, targetReps: 6, repMin: 5, repMax: 8, lastSession: noExtra
        )
        XCTAssertEqual(
            ExerciseInfoText.why(hold),
            "Na última vez você fez 5, 5 e 5, dentro da faixa de 5 a 8. A meta sobe para 6 repetições."
        )

        let increase = makeContent(
            note: .increase, equipment: .bodyweight, load: 2.5, targetReps: 5, repMin: 5, repMax: 8,
            lastSession: lastSession(sets: [(0, 8), (0, 8), (0, 8)])
        )
        XCTAssertEqual(
            ExerciseInfoText.why(increase),
            "Na última vez você fez 8, 8 e 8, o máximo de 5 a 8. "
                + "Hoje entra + 2,5 kg extra e as repetições recomeçam em 5."
        )

        let returning = makeContent(
            note: .returning, equipment: .bodyweight, load: 0, targetReps: 5, repMin: 5, repMax: 8, lastSession: noExtra
        )
        XCTAssertEqual(
            ExerciseInfoText.why(returning),
            "Faz mais de 3 semanas que você não faz este exercício. Hoje a meta volta para 5 repetições, para retomar com calma."
        )

        let notes: [PrescriptionNote] = [.increase, .hold, .retry, .decrease, .returning, .deload]
        let loads: [Double?] = [nil, 0]
        for note in notes {
            for load in loads {
                let content = makeContent(
                    note: note, equipment: .bodyweight, load: load, repMin: 5, repMax: 8, lastSession: noExtra
                )
                let sentence = ExerciseInfoText.why(content)
                XCTAssertFalse(sentence.isEmpty, "\(note)")
                XCTAssertFalse(sentence.contains("kg"), "\(note) com peso do corpo não deveria citar carga: \(sentence)")
                XCTAssertFalse(sentence.contains("A carga"), "\(note) com peso do corpo sem extra: \(sentence)")
            }
        }
    }

    /// SPEC contrato §3.2: sem `lastSession`, a frase não cita números (caminho raro de defesa).
    func testRF47_why_fallsBackToQualitativeSentenceWithoutLastSession() {
        let notes: [PrescriptionNote] = [.increase, .hold, .retry, .decrease, .returning, .deload]
        for note in notes {
            let content = makeContent(note: note, lastSession: nil)
            let sentence = ExerciseInfoText.why(content)
            XCTAssertFalse(sentence.isEmpty, "\(note) deveria ter uma frase mesmo sem histórico")
            XCTAssertFalse(
                sentence.contains(where: \.isNumber),
                "\(note) sem lastSession não deveria citar números: \(sentence)"
            )
        }
    }

    // MARK: - "Da última vez" (RF-47)

    func testRF47_lastTime_formatsLoadsAndBodyweight() {
        let uniform = lastSession(sets: [(60, 5), (60, 5), (60, 5)])
        XCTAssertEqual(
            ExerciseInfoText.lastTime(uniform, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5, 5, 5 · 60 kg"
        )

        let bodyweightNoExtra = lastSession(sets: [(0, 5), (0, 5), (0, 5)])
        XCTAssertEqual(
            ExerciseInfoText.lastTime(bodyweightNoExtra, unit: .kilograms, equipment: .bodyweight, measure: .reps),
            "5, 5, 5"
        )

        let differentLoads = lastSession(sets: [(60, 5), (57.5, 4)])
        XCTAssertEqual(
            ExerciseInfoText.lastTime(differentLoads, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5 × 60 kg, 4 × 57,5 kg"
        )

        let deload = lastSession(sets: [(60, 5), (60, 5), (60, 5)], wasDeload: true)
        XCTAssertEqual(
            ExerciseInfoText.lastTime(deload, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5, 5, 5 · 60 kg (semana leve)"
        )
    }

    func testRF47_lastTimeTitle_shortPortugueseDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let session = ExerciseLastSession(sessionID: UUID(), date: date, sets: [SetResult(load: 60, reps: 5, completedAt: date)], wasDeload: false)

        XCTAssertEqual(ExerciseInfoText.lastTimeTitle(session, calendar: calendar), "Da última vez · qua, 23 set")
    }

    // MARK: - RF-41: nada de RIR na interface

    func testRF41_texts_haveNoRIR() {
        let notes: [PrescriptionNote] = [.calibrate, .increase, .hold, .retry, .decrease, .returning, .deload]
        let measures: [ExerciseMeasure] = [.reps, .seconds, .steps]
        let equipments: [Equipment?] = [.barbell, .bodyweight, .machine]
        let history = lastSession(sets: [(60, 6), (57.5, 5)])
        let loads: [Double?] = [nil, 40]
        let sessions: [ExerciseLastSession?] = [nil, history]

        var sentences: [String] = []
        for note in notes {
            for measure in measures {
                for equipment in equipments {
                    for load in loads {
                        for session in sessions {
                            let content = makeContent(
                                note: note, equipment: equipment, measure: measure, load: load,
                                lastSession: session
                            )
                            sentences.append(ExerciseInfoText.today(content))
                            sentences.append(ExerciseInfoText.whyTitle(content))
                            sentences.append(ExerciseInfoText.why(content))
                        }
                    }
                }
            }
        }
        sentences.append(ExerciseInfoText.lastTimeTitle(history))
        sentences.append(ExerciseInfoText.lastTime(history, unit: .kilograms, equipment: .barbell, measure: .reps))

        for sentence in sentences {
            let lowercased = sentence.lowercased()
            XCTAssertFalse(lowercased.contains("rir"), "Frase menciona RIR: \(sentence)")
            XCTAssertFalse(lowercased.contains("sobrando"), "Frase menciona 'sobrando': \(sentence)")
            XCTAssertFalse(lowercased.contains("antes do limite"), "Frase menciona 'antes do limite': \(sentence)")
        }
    }

    // MARK: - SPEC §7.14 F1 e F2: aeróbico na folha

    func testF1_infoTodayForCardio() {
        let walk = makeContent(
            note: .hold, equipment: .bodyweight, measure: .minutes, load: nil, sets: 1, targetReps: 30,
            repMin: 30, repMax: 45, restSeconds: 60, slug: "brisk-walk", pattern: .cardio
        )
        XCTAssertEqual(ExerciseInfoText.today(walk), "30 minutos, moderado: dá para conversar, mas não para cantar.")

        let intervals = makeContent(
            note: .hold, equipment: .bodyweight, measure: .minutes, load: nil, sets: 4, targetReps: 3,
            repMin: 3, repMax: 4, restSeconds: 180, slug: "run-intervals", pattern: .cardio
        )
        XCTAssertEqual(
            ExerciseInfoText.today(intervals),
            "4 séries de 3 minutos, forte: só dá para dizer poucas palavras. "
                + "Recuperação andando de 3 min entre as séries. Antes, aqueça 10 minutos andando devagar. "
                + "Cada bloco sobe 1 min por sessão até 4 min. No topo, entra mais um bloco, até 5."
        )

        let bikeWithLevel = makeContent(
            note: .hold, equipment: .machine, measure: .minutes, load: 7, unit: .level, sets: 1, targetReps: 50,
            repMin: 45, repMax: 75, restSeconds: 60, slug: "stationary-bike", pattern: .cardio
        )
        XCTAssertEqual(ExerciseInfoText.today(bikeWithLevel), "50 minutos, leve: a conversa é fácil. No nível 7.")

        let bikeWithoutLevel = makeContent(
            note: .calibrate, equipment: .machine, measure: .minutes, load: nil, unit: .level, sets: 1, targetReps: 45,
            repMin: 45, repMax: 75, restSeconds: 60, slug: "stationary-bike", pattern: .cardio
        )
        XCTAssertEqual(ExerciseInfoText.today(bikeWithoutLevel), "45 minutos, leve: a conversa é fácil.")
        XCTAssertEqual(
            ExerciseInfoText.why(bikeWithoutLevel),
            "Primeira vez: faça 45 minutos no ritmo em que a conversa é fácil; a próxima sessão se ajusta. "
                + "O nível da máquina é opcional."
        )
        XCTAssertEqual(ExerciseInfoText.whyTitle(bikeWithoutLevel), "Por que assim hoje", "sem nível, nada de \"escolha a carga\"")
    }

    /// SPEC RF-47 e §7.14 F6 (2.4; achado B10 da 2.3): nos intervalos do Cardio, a seção "Hoje" explica a
    /// progressão (cada bloco sobe 1 min até o topo; no topo, mais um bloco, até 5), e o "Por que" da nota
    /// `increase` fala do bloco novo. Com um nível registrado vale F3; o aeróbico de uma série não muda.
    func testRF47_intervalsProgressionText() {
        XCTAssertEqual(
            CardioText.intervalsProgression(repMax: 4, hasLevel: false),
            "Cada bloco sobe 1 min por sessão até 4 min. No topo, entra mais um bloco, até 5."
        )
        XCTAssertEqual(
            CardioText.intervalsProgression(repMax: 4, hasLevel: true),
            "Cada bloco sobe 1 min por sessão até 4 min. No topo, sobe 1 nível e os minutos recomeçam."
        )
        XCTAssertEqual(
            CardioText.intervalsProgression(repMax: 4, hasLevel: true, loadUnit: .kilograms),
            "Cada bloco sobe 1 min por sessão até 4 min. No topo, a carga sobe e os minutos recomeçam."
        )
        XCTAssertEqual(CardioText.maxIntervalBlocks, 5)

        // O Dia B depois de um bloco a mais: 5 × 3 min, com a nota `increase`.
        let fiveBlocks = makeContent(
            note: .increase, equipment: .bodyweight, measure: .minutes, load: nil, sets: 5, targetReps: 3,
            repMin: 3, repMax: 4, restSeconds: 180,
            lastSession: lastSession(sets: [(0, 4), (0, 4), (0, 4), (0, 4)]),
            slug: "run-intervals", pattern: .cardio
        )
        XCTAssertEqual(
            ExerciseInfoText.today(fiveBlocks),
            "5 séries de 3 minutos, forte: só dá para dizer poucas palavras. "
                + "Recuperação andando de 3 min entre as séries. Antes, aqueça 10 minutos andando devagar. "
                + "Cada bloco sobe 1 min por sessão até 4 min. No topo, entra mais um bloco, até 5."
        )
        XCTAssertEqual(fiveBlocks.badgeText, "Mais um bloco", "o mesmo selo da ficha")
        XCTAssertEqual(
            ExerciseInfoText.why(fiveBlocks),
            "Na última vez você fez 4 min, 4 min, 4 min e 4 min, o máximo de 3 a 4. "
                + "Hoje entra mais um bloco e a meta volta para 3 minutos."
        )

        // Bicicleta em intervalos com nível: F3, sem blocos novos.
        let bikeWithLevel = makeContent(
            note: .increase, equipment: .machine, measure: .minutes, load: 8, unit: .level, sets: 4, targetReps: 3,
            repMin: 3, repMax: 4, restSeconds: 180, slug: "bike-intervals", pattern: .cardio
        )
        XCTAssertTrue(ExerciseInfoText.today(bikeWithLevel).hasSuffix("No topo, sobe 1 nível e os minutos recomeçam."))
        XCTAssertEqual(bikeWithLevel.badgeText, "Nível maior")

        // Uma série só (caminhada): nada de blocos.
        let walk = makeContent(
            note: .hold, equipment: .bodyweight, measure: .minutes, load: nil, sets: 1, targetReps: 30,
            repMin: 30, repMax: 45, restSeconds: 60, slug: "brisk-walk", pattern: .cardio
        )
        XCTAssertFalse(ExerciseInfoText.today(walk).contains("bloco"))

        // Força: o selo de sempre.
        let squat = makeContent(note: .increase)
        XCTAssertEqual(squat.badgeText, "Carga maior")
    }

    /// SPEC RF-46 (D3): 0 num exercício com equipamento é "sem carga externa", nunca "0 kg".
    func testRF46_noLoadOnEquipment_neverSaysZeroKg() {
        let noLoad = lastSession(sets: [(0, 12), (0, 12), (0, 12)])
        let hold = makeContent(
            note: .hold, equipment: .machine, load: 0, targetReps: 12, repMin: 8, repMax: 12, lastSession: noLoad
        )
        XCTAssertEqual(
            ExerciseInfoText.why(hold),
            "Na última vez você fez 12, 12 e 12, dentro da faixa de 8 a 12. A meta sobe para 12 repetições."
        )
        XCTAssertEqual(
            ExerciseInfoText.today(hold),
            "3 séries de 12 repetições. A carga é opcional. Descanso de 4 min entre as séries."
        )
        XCTAssertEqual(ExerciseInfoText.whyTitle(hold), "Por que assim hoje")
        XCTAssertEqual(hold.loadDisplay, .toChoose)
    }

    // MARK: - Fixtures

    private func makeContent(
        note: PrescriptionNote,
        equipment: Equipment? = .barbell,
        measure: ExerciseMeasure = .reps,
        load: Double? = 62.5,
        unit: LoadUnit = .kilograms,
        sets: Int = 3,
        targetReps: Int = 3,
        repMin: Int = 3,
        repMax: Int = 5,
        targetRIR: Int = 2,
        restSeconds: Int = 240,
        machineNotes: String? = nil,
        lastSession: ExerciseLastSession? = nil,
        slug: String? = nil,
        pattern: MovementPattern? = nil
    ) -> ExerciseInfoContent {
        ExerciseInfoContent(
            id: UUID(),
            exerciseID: UUID(),
            name: "Exercício",
            equipment: equipment,
            loadUnit: unit,
            measure: measure,
            machineNotes: machineNotes,
            sets: sets,
            targetReps: targetReps,
            repMin: repMin,
            repMax: repMax,
            targetRIR: targetRIR,
            load: load,
            restSeconds: restSeconds,
            note: note,
            lastSession: lastSession,
            slug: slug,
            movementPattern: pattern
        )
    }

    /// `sets`: pares (carga, repetições), na ordem em que teriam sido feitas.
    private func lastSession(sets: [(Double, Int)], wasDeload: Bool = false) -> ExerciseLastSession {
        let now = Date(timeIntervalSince1970: 1_695_400_000)
        return ExerciseLastSession(
            sessionID: UUID(),
            date: now,
            sets: sets.map { load, reps in SetResult(load: load, reps: reps, completedAt: now) },
            wasDeload: wasDeload
        )
    }
}
