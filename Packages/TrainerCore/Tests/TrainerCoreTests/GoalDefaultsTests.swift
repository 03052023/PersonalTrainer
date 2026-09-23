import Foundation
import Testing
@testable import TrainerCore

struct GoalDefaultsTests {
    /// Tabela SPEC §7.9 como o app a aplica (valor único onde a SPEC dá faixa de RIR/descanso).
    private static let expected: [(goal: ProgramGoal, defaults: GoalDefaults)] = [
        (.hypertrophy, GoalDefaults(
            compoundRepRange: 6...12, isolationRepRange: 8...15, targetRIR: 2,
            weeklySetsPerMuscle: 10...20, compoundRestSeconds: 150, isolationRestSeconds: 90,
            setsPerExercise: 3
        )),
        (.strength, GoalDefaults(
            compoundRepRange: 3...6, isolationRepRange: 6...10, targetRIR: 2,
            weeklySetsPerMuscle: 6...12, compoundRestSeconds: 240, isolationRestSeconds: 150,
            setsPerExercise: 4
        )),
        (.endurance, GoalDefaults(
            compoundRepRange: 12...20, isolationRepRange: 15...20, targetRIR: 3,
            weeklySetsPerMuscle: 8...16, compoundRestSeconds: 75, isolationRestSeconds: 60,
            setsPerExercise: 3
        )),
        (.longevity, GoalDefaults(
            compoundRepRange: 8...12, isolationRepRange: 10...15, targetRIR: 3,
            weeklySetsPerMuscle: 6...12, compoundRestSeconds: 120, isolationRestSeconds: 90,
            setsPerExercise: 2
        )),
        (.combat, GoalDefaults(
            compoundRepRange: 3...6, isolationRepRange: 6...10, targetRIR: 2,
            weeklySetsPerMuscle: 6...12, compoundRestSeconds: 180, isolationRestSeconds: 90,
            setsPerExercise: 3
        )),
    ]

    @Test("SPEC 7.9 cada objetivo devolve exatamente os padrões da tabela")
    func everyGoalMatchesSpecificationTable() {
        #expect(Self.expected.map { $0.goal } == ProgramGoal.allCases)
        for row in Self.expected {
            #expect(row.goal.defaults == row.defaults, "\(row.goal)")
        }
    }

    @Test("SPEC 7.9 hipertrofia usa 6–12 em compostos, 8–15 em isolados, RIR 2 e 10–20 séries/semana")
    func hypertrophyDefaults() {
        let defaults = ProgramGoal.hypertrophy.defaults

        #expect(defaults.compoundRepRange == 6...12)
        #expect(defaults.isolationRepRange == 8...15)
        #expect(defaults.targetRIR == 2)
        #expect(defaults.weeklySetsPerMuscle == 10...20)
        #expect(defaults.compoundRestSeconds == 150)
        #expect(defaults.isolationRestSeconds == 90)
        #expect(defaults.setsPerExercise == 3)
    }

    @Test("SPEC 7.9 força e combate usam 3–6 reps em compostos e mais descanso que hipertrofia")
    func strengthAndCombatUseLowRepsAndLongRest() {
        let hypertrophy = ProgramGoal.hypertrophy.defaults
        for goal in [ProgramGoal.strength, .combat] {
            let defaults = goal.defaults
            #expect(defaults.compoundRepRange == 3...6, "\(goal)")
            #expect(defaults.compoundRestSeconds > hypertrophy.compoundRestSeconds, "\(goal)")
        }
        #expect(ProgramGoal.strength.defaults.setsPerExercise == 4)
    }

    @Test("SPEC 7.9 padrões são prescrições válidas: reps ≥ 1, RIR 0–5, descanso e séries positivos")
    func everyGoalProducesValidPrescription() {
        for goal in ProgramGoal.allCases {
            let defaults = goal.defaults
            // Same bounds SeedValidator enforces on ExerciseTarget (P4, RIR 0...5, rest > 0).
            #expect(defaults.compoundRepRange.lowerBound >= 1, "\(goal)")
            #expect(defaults.compoundRepRange.lowerBound < defaults.compoundRepRange.upperBound, "\(goal)")
            #expect(defaults.isolationRepRange.lowerBound >= 1, "\(goal)")
            #expect(defaults.isolationRepRange.lowerBound < defaults.isolationRepRange.upperBound, "\(goal)")
            #expect((0...5).contains(defaults.targetRIR), "\(goal)")
            #expect(defaults.weeklySetsPerMuscle.lowerBound >= 1, "\(goal)")
            #expect(defaults.compoundRestSeconds > 0, "\(goal)")
            #expect(defaults.isolationRestSeconds > 0, "\(goal)")
            #expect(defaults.setsPerExercise >= 1, "\(goal)")
        }
    }

    @Test("SPEC 7.9 isolados nunca têm menos reps nem mais descanso que compostos do mesmo objetivo")
    func isolationIsLighterThanCompound() {
        for goal in ProgramGoal.allCases {
            let defaults = goal.defaults
            #expect(defaults.isolationRepRange.lowerBound >= defaults.compoundRepRange.lowerBound, "\(goal)")
            #expect(defaults.isolationRepRange.upperBound >= defaults.compoundRepRange.upperBound, "\(goal)")
            #expect(defaults.isolationRestSeconds <= defaults.compoundRestSeconds, "\(goal)")
        }
    }

    @Test("SPEC 7.9 compostos são os 10 padrões multiarticulares; os outros 10 são isolados")
    func compoundPatternsAreExactlyTheMultiJointOnes() {
        let compounds: Set<MovementPattern> = [
            .horizontalPush, .verticalPush, .horizontalPull, .verticalPull,
            .squat, .lunge, .hinge, .hipThrust, .carry, .explosive,
        ]
        let isolations: Set<MovementPattern> = [
            .chestFly, .shoulderIsolation, .elbowFlexion, .elbowExtension,
            .kneeExtension, .kneeFlexion, .calfRaise, .coreFlexion, .coreStability, .neck,
        ]

        #expect(compounds.union(isolations) == Set(MovementPattern.allCases))
        for pattern in MovementPattern.allCases {
            #expect(pattern.isCompound == compounds.contains(pattern), "\(pattern)")
        }
    }
}
