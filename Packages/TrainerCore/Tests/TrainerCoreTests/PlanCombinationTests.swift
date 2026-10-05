import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.15 M7 (owner notes itens 10 a 12): a tabela de consequências de combinar dois objetivos.

/// Um par da tabela M7 com o número de frases de cada sinal (+, =, −), na ordem da SPEC.
struct PlanCombinationRow: Sendable, CustomTestStringConvertible {
    let first: ProgramGoal
    let second: ProgramGoal
    let kinds: [PlanConsequenceKind]
    let isLargeOverlap: Bool

    var testDescription: String {
        "\(first.rawValue) + \(second.rawValue)"
    }
}

let planCombinationRows: [PlanCombinationRow] = [
    PlanCombinationRow(first: .hypertrophy, second: .strength, kinds: [.neutral, .positive, .negative], isLargeOverlap: true),
    PlanCombinationRow(first: .hypertrophy, second: .combat, kinds: [.positive, .neutral, .negative], isLargeOverlap: false),
    PlanCombinationRow(first: .hypertrophy, second: .longevity, kinds: [.positive, .neutral, .negative], isLargeOverlap: false),
    PlanCombinationRow(
        first: .hypertrophy,
        second: .endurance,
        kinds: [.positive, .positive, .neutral, .negative, .negative],
        isLargeOverlap: false
    ),
    PlanCombinationRow(first: .strength, second: .combat, kinds: [.neutral, .positive, .negative], isLargeOverlap: true),
    PlanCombinationRow(first: .strength, second: .longevity, kinds: [.positive, .neutral, .negative], isLargeOverlap: false),
    PlanCombinationRow(first: .strength, second: .endurance, kinds: [.positive, .neutral, .negative], isLargeOverlap: false),
    PlanCombinationRow(first: .combat, second: .longevity, kinds: [.positive, .neutral, .negative], isLargeOverlap: false),
    PlanCombinationRow(
        first: .combat,
        second: .endurance,
        kinds: [.positive, .neutral, .negative, .negative],
        isLargeOverlap: false
    ),
    PlanCombinationRow(first: .longevity, second: .endurance, kinds: [.positive, .neutral, .negative], isLargeOverlap: false),
]

@Test("M7 os 10 pares, na ordem da SPEC e nos dois sentidos", arguments: planCombinationRows)
func planCombinationPairs(_ row: PlanCombinationRow) {
    let forward = PlanCombination.consequences(row.first, row.second)
    let backward = PlanCombination.consequences(row.second, row.first)

    #expect(forward.map(\.kind) == row.kinds)
    #expect(forward == backward, "a tabela não depende da ordem dos objetivos")
    #expect(PlanCombination.isLargeOverlap(row.first, row.second) == row.isLargeOverlap)
    #expect(PlanCombination.isLargeOverlap(row.second, row.first) == row.isLargeOverlap)
    for consequence in forward {
        #expect(!consequence.text.isEmpty)
        #expect(consequence.text.count <= 90, "\(consequence.text)")
        #expect(consequence.text.hasSuffix("."), "\(consequence.text)")
    }
}

@Test("M7 todo par de objetivos diferentes tem consequências; o mesmo objetivo não tem nenhuma")
func planCombinationCoversEveryPair() {
    let goals: [ProgramGoal] = ProgramGoal.allCases
    var pairs = 0
    for (index, first) in goals.enumerated() {
        #expect(PlanCombination.consequences(first, first).isEmpty)
        #expect(!PlanCombination.isLargeOverlap(first, first))
        for second in goals[(index + 1)...] {
            pairs += 1
            #expect(!PlanCombination.consequences(first, second).isEmpty, "\(first) + \(second)")
        }
    }
    #expect(pairs == 10)
    #expect(planCombinationRows.count == 10)
}

@Test("M7 os textos seguem a SPEC (Hipertrofia + Cardio e Força + Combate)")
func planCombinationTexts() {
    let hypertrophyCardio = PlanCombination.consequences(.endurance, .hypertrophy)
    #expect(hypertrophyCardio.map(\.text) == [
        "Coração mais forte e VO2máx maior.",
        "Recuperação mais rápida entre as séries.",
        "Ganho de músculo quase igual, com o cardio separado ou moderado.",
        "Semana mais longa e mais cansaço.",
        "Intervalos fortes na véspera de pernas atrapalham; o encaixe evita.",
    ])
    #expect(hypertrophyCardio.map(\.referenceTopic) == [
        "topic.vo2max", "topic.combination", "topic.concurrent", "topic.weekFit", "topic.concurrent",
    ])
    let strengthCombat = PlanCombination.consequences(.combat, .strength)
    #expect(strengthCombat.first?.text == "Os dois usam a mesma base de força máxima, com 3 a 6 repetições.")
    #expect(strengthCombat.first?.referenceTopic == "goal.combat")
}

@Test("M7 todo tópico do Por quê? existe no references.v1.json, com explicação")
func planCombinationTopicsExistInTheCatalog() throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        root.deleteLastPathComponent()
    }
    let url = root
        .appendingPathComponent("PersonalTrainer", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Seed", isDirectory: true)
        .appendingPathComponent("references.v1.json", isDirectory: false)
    let catalog = try JSONDecoder().decode(ReferenceCatalog.self, from: Data(contentsOf: url))

    let goals: [ProgramGoal] = ProgramGoal.allCases
    for first in goals {
        for second in goals where first != second {
            for consequence in PlanCombination.consequences(first, second) {
                let topic = consequence.referenceTopic
                #expect(!catalog.references(for: topic).isEmpty, "\(topic) sem referência")
                #expect(!(catalog.explanations[topic] ?? "").isEmpty, "\(topic) sem explicação")
            }
        }
    }
}

@Test("M7 P12 as consequências não falam de frequência cardíaca nem de RIR")
func planCombinationTextsHaveNoHeartRateNorRIR() {
    let goals: [ProgramGoal] = ProgramGoal.allCases
    let forbidden: [String] = ["fc", "bpm", "rir", "batimento", "frequência cardíaca"]
    for first in goals {
        for second in goals where first != second {
            for consequence in PlanCombination.consequences(first, second) {
                let lowercased = consequence.text.lowercased()
                let words = Set(lowercased.split { !$0.isLetter }.map { String($0) })
                for word in forbidden {
                    #expect(!words.contains(word) && !lowercased.contains(" \(word) "), "\(consequence.text)")
                }
            }
        }
    }
}
