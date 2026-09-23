import Foundation
import Testing
@testable import TrainerCore

struct ExerciseSubstitutionTests {
    // MARK: - Filtering

    @Test("RF-34 exercício sem padrão de movimento não tem substitutos")
    func exerciseWithoutPatternHasNoCandidates() {
        let benchWithoutPattern = SubstitutionFixture.exercise(1, "Supino reto com barra", pattern: nil)
        let catalog = SubstitutionFixture.chestCatalog + [
            SubstitutionFixture.exercise(90, "Supino sem padrão", equipment: .dumbbell, pattern: nil),
        ]

        #expect(ExerciseSubstitution.candidates(for: benchWithoutPattern, in: catalog).isEmpty)
    }

    @Test("RF-34 só entram candidatos com o mesmo padrão de movimento")
    func onlySamePatternCandidates() {
        let result = ExerciseSubstitution.candidates(
            for: SubstitutionFixture.barbellBench,
            in: SubstitutionFixture.chestCatalog,
            limit: 20
        )

        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.movementPattern == .horizontalPush })
        #expect(!result.contains(SubstitutionFixture.dumbbellFly))
        #expect(!result.contains(SubstitutionFixture.overheadPress))
        #expect(!result.contains(SubstitutionFixture.benchWithoutPattern))
    }

    @Test("RF-34 exercício nunca é substituto de si mesmo")
    func exerciseIsNotItsOwnSubstitute() {
        let bench = SubstitutionFixture.barbellBench
        let renamedCopy = SubstitutionFixture.exercise(1, "Supino reto com barra (cópia)")

        let result = ExerciseSubstitution.candidates(
            for: bench,
            in: SubstitutionFixture.chestCatalog + [renamedCopy, bench],
            limit: 20
        )

        #expect(!result.map(\.id).contains(bench.id))
        #expect(ExerciseSubstitution.candidates(for: bench, in: [bench]).isEmpty)
    }

    @Test("RF-34 ids em excluding não aparecem e o resto mantém a ordem")
    func excludedIDsAreSkipped() {
        let bench = SubstitutionFixture.barbellBench
        let excluded: Set<UUID> = [SubstitutionFixture.dumbbellBench.id, SubstitutionFixture.pushUp.id]

        let result = ExerciseSubstitution.candidates(
            for: bench,
            in: SubstitutionFixture.chestCatalog,
            excluding: excluded
        )

        #expect(result == [SubstitutionFixture.smithIncline, SubstitutionFixture.chestPress])
    }

    @Test("RF-34 id repetido no catálogo aparece uma vez só")
    func duplicateIDsAppearOnce() {
        let bench = SubstitutionFixture.barbellBench
        let catalog = SubstitutionFixture.chestCatalog + [SubstitutionFixture.dumbbellBench]

        let result = ExerciseSubstitution.candidates(for: bench, in: catalog, limit: 20)

        #expect(result.filter { $0.id == SubstitutionFixture.dumbbellBench.id }.count == 1)
    }

    // MARK: - Ranking

    @Test("RF-34 supino com barra sugere halteres, depois máquinas guiadas, e flexão por último")
    func barbellBenchRanksDumbbellBeforePushUp() throws {
        let result = ExerciseSubstitution.candidates(
            for: SubstitutionFixture.barbellBench,
            in: SubstitutionFixture.chestCatalog
        )

        #expect(result == [
            SubstitutionFixture.dumbbellBench,
            SubstitutionFixture.smithIncline,
            SubstitutionFixture.chestPress,
            SubstitutionFixture.pushUp,
        ])
        let dumbbellIndex = try #require(result.firstIndex(of: SubstitutionFixture.dumbbellBench))
        let pushUpIndex = try #require(result.firstIndex(of: SubstitutionFixture.pushUp))
        #expect(dumbbellIndex < pushUpIndex)
    }

    @Test("RF-34 mesmo equipamento vem antes de equipamento parecido")
    func sameEquipmentComesFirst() {
        let declineBench = SubstitutionFixture.exercise(20, "Supino declinado com barra")

        let result = ExerciseSubstitution.candidates(
            for: SubstitutionFixture.barbellBench,
            in: SubstitutionFixture.chestCatalog + [declineBench]
        )

        #expect(result.first == declineBench)
        #expect(result.dropFirst().first == SubstitutionFixture.dumbbellBench)
    }

    @Test("RF-34 pontuação vence a afinidade de equipamento")
    func scoreOutranksEquipmentAffinity() {
        let bench = SubstitutionFixture.exercise(30, "Supino com barra", primary: [.chest, .triceps])
        let pushUp = SubstitutionFixture.exercise(
            31, "Flexão de braço", primary: [.chest, .triceps], equipment: .bodyweight
        )
        let dumbbell = SubstitutionFixture.exercise(32, "Supino com halteres", equipment: .dumbbell)

        // pushUp: 3 + 1 + 0 + 1 + 1 = 6, affinity 0; dumbbell: 3 + 0 + 0 + 1 + 1 = 5, affinity 2.
        let result = ExerciseSubstitution.candidates(for: bench, in: [dumbbell, pushUp])

        #expect(result == [pushUp, dumbbell])
    }

    @Test("RF-34 pontuação soma grupo principal, grupos extras, equipamento, lateralidade e unidade")
    func scoreTable() {
        let bench = SubstitutionFixture.exercise(1, "Supino reto com barra")
        let squat = SubstitutionFixture.exercise(40, "Agachamento", primary: [.quads, .glutes], pattern: .squat)
        let rows: [(label: String, exercise: ExerciseDefinition, candidate: ExerciseDefinition, score: Int)] = [
            ("tudo igual", bench, SubstitutionFixture.exercise(2, "A"), 7),
            ("equipamento diferente", bench, SubstitutionFixture.exercise(2, "A", equipment: .dumbbell), 5),
            ("unilateral diferente", bench, SubstitutionFixture.exercise(2, "A", unilateral: true), 6),
            ("unidade diferente", bench, SubstitutionFixture.exercise(2, "A", loadUnit: .plates), 6),
            ("sem grupo em comum", bench, SubstitutionFixture.exercise(2, "A", primary: [.back]), 4),
            ("grupo repetido conta uma vez", bench, SubstitutionFixture.exercise(2, "A", primary: [.chest, .chest]), 7),
            ("principal + extra", squat, SubstitutionFixture.exercise(2, "A", primary: [.glutes, .quads]), 8),
            ("só o secundário do exercício", squat, SubstitutionFixture.exercise(2, "A", primary: [.glutes]), 5),
            ("grupo extra do candidato não pontua", squat,
             SubstitutionFixture.exercise(2, "A", primary: [.quads, .glutes, .hamstrings]), 8),
            ("exercício sem grupo primário", SubstitutionFixture.exercise(3, "B", primary: []),
             SubstitutionFixture.exercise(2, "A"), 4),
        ]

        for row in rows {
            #expect(ExerciseSubstitution.score(of: row.candidate, against: row.exercise) == row.score, "\(row.label)")
        }
    }

    @Test("RF-34 afinidade: mesma família 2, ambos com carga externa 1, peso corporal contra carga 0")
    func equipmentAffinityTable() {
        let rows: [(Equipment, Equipment, Int)] = [
            (.barbell, .barbell, 2),
            (.barbell, .dumbbell, 2),
            (.dumbbell, .kettlebell, 2),
            (.machine, .cable, 2),
            (.smith, .machine, 2),
            (.bodyweight, .bodyweight, 2),
            (.barbell, .machine, 1),
            (.dumbbell, .smith, 1),
            (.kettlebell, .cable, 1),
            (.bodyweight, .barbell, 0),
            (.machine, .bodyweight, 0),
        ]

        for (lhs, rhs, affinity) in rows {
            #expect(ExerciseSubstitution.equipmentAffinity(lhs, rhs) == affinity, "\(lhs) × \(rhs)")
            #expect(ExerciseSubstitution.equipmentAffinity(rhs, lhs) == affinity, "\(rhs) × \(lhs)")
        }
    }

    @Test("RF-34 empates saem por nome sem caixa nem acento, depois nome original, depois uuidString")
    func tiesAreBrokenDeterministically() {
        let bench = SubstitutionFixture.barbellBench
        // All tie on score (5) and affinity (2): dumbbell, chest, bilateral, kg.
        let accented = SubstitutionFixture.exercise(50, "Ênfase no peitoral com halteres", equipment: .dumbbell)
        let alternating = SubstitutionFixture.exercise(51, "Supino alternado com halteres", equipment: .dumbbell)
        let lowercase = SubstitutionFixture.exercise(52, "supino com halteres", equipment: .dumbbell)
        let sameNameHighID = SubstitutionFixture.exercise(0x5B, "Supino com halteres", equipment: .dumbbell)
        let sameNameLowID = SubstitutionFixture.exercise(0x5A, "Supino com halteres", equipment: .dumbbell)
        let catalog = [lowercase, sameNameHighID, accented, sameNameLowID, alternating]
        let expected = [accented, alternating, sameNameLowID, sameNameHighID, lowercase]

        let permutations: [[ExerciseDefinition]] = [
            catalog,
            Array(catalog.reversed()),
            Array(catalog.dropFirst(2) + catalog.prefix(2)),
        ]
        for permutation in permutations {
            let result = ExerciseSubstitution.candidates(for: bench, in: permutation, limit: 10)
            #expect(result == expected)
        }
    }

    @Test("RF-34 mesma entrada em qualquer ordem produz a mesma lista")
    func resultDoesNotDependOnCatalogOrder() {
        let bench = SubstitutionFixture.barbellBench
        let catalog = SubstitutionFixture.chestCatalog
        let baseline = ExerciseSubstitution.candidates(for: bench, in: catalog, limit: 20)

        for shift in 1..<catalog.count {
            let rotated = Array(catalog.dropFirst(shift) + catalog.prefix(shift))
            #expect(ExerciseSubstitution.candidates(for: bench, in: rotated, limit: 20) == baseline, "shift \(shift)")
            #expect(
                ExerciseSubstitution.candidates(for: bench, in: Array(rotated.reversed()), limit: 20) == baseline,
                "reversed shift \(shift)"
            )
        }
    }

    // MARK: - Limit

    @Test("RF-34 limit corta a lista; limit <= 0 devolve vazio; limit grande devolve todos")
    func limitIsApplied() {
        let bench = SubstitutionFixture.barbellBench
        let catalog = SubstitutionFixture.chestCatalog
        let all = ExerciseSubstitution.candidates(for: bench, in: catalog, limit: 100)

        #expect(all.count == 4)
        #expect(ExerciseSubstitution.candidates(for: bench, in: catalog, limit: 2) == Array(all.prefix(2)))
        #expect(ExerciseSubstitution.candidates(for: bench, in: catalog, limit: 1) == [SubstitutionFixture.dumbbellBench])
        #expect(ExerciseSubstitution.candidates(for: bench, in: catalog, limit: 0).isEmpty)
        #expect(ExerciseSubstitution.candidates(for: bench, in: catalog, limit: -3).isEmpty)
    }

    @Test("RF-34 limit padrão é 5")
    func defaultLimitIsFive() {
        let bench = SubstitutionFixture.barbellBench
        let many = (0..<8).map { index in
            SubstitutionFixture.exercise(100 + index, "Supino variação \(index)", equipment: .dumbbell)
        }

        #expect(ExerciseSubstitution.candidates(for: bench, in: many).count == 5)
    }
}

/// Chest exercises mirroring `exercises.v1.json` (same muscles, equipment and names), plus
/// patterns from T2.19. Defaults: chest, barbell, bilateral, kilograms, horizontal push.
private enum SubstitutionFixture {
    static let barbellBench = exercise(1, "Supino reto com barra")
    static let dumbbellBench = exercise(2, "Supino reto com halteres", equipment: .dumbbell)
    static let smithIncline = exercise(3, "Supino inclinado no smith", equipment: .smith)
    static let chestPress = exercise(4, "Supino na máquina (chest press)", equipment: .machine)
    static let pushUp = exercise(5, "Flexão de braço", equipment: .bodyweight)
    static let dumbbellFly = exercise(6, "Crucifixo com halteres", equipment: .dumbbell, pattern: .chestFly)
    static let overheadPress = exercise(7, "Desenvolvimento com barra", primary: [.shoulders], pattern: .verticalPush)
    static let benchWithoutPattern = exercise(8, "Supino antigo sem padrão", pattern: nil)

    static let chestCatalog = [
        pushUp, overheadPress, chestPress, barbellBench, dumbbellFly, smithIncline, benchWithoutPattern, dumbbellBench,
    ]

    /// `00000000-0000-4000-8000-<number in 12 hex digits>`, so `uuidString` order follows `number`.
    static func id(_ number: Int) -> UUID {
        let hex = String(number, radix: 16, uppercase: true)
        let node = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-4000-8000-" + node)!
    }

    static func exercise(
        _ number: Int,
        _ name: String,
        primary: [MuscleGroup] = [.chest],
        equipment: Equipment = .barbell,
        unilateral: Bool = false,
        loadUnit: LoadUnit = .kilograms,
        pattern: MovementPattern? = .horizontalPush
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id(number),
            slug: "exercise-\(number)",
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: [],
            equipment: equipment,
            loadUnit: loadUnit,
            loadIncrement: 2.5,
            isUnilateral: unilateral,
            movementPattern: pattern
        )
    }
}
