import Foundation

/// Padrões de prescrição de um objetivo de programa (SPEC §7.9), usados pelo seed, pela edição de
/// programa (novo exercício herda faixa, RIR, séries e descanso do objetivo) e pela revisão (§7.8 R3).
///
/// Onde a SPEC dá uma faixa de RIR ou de descanso, o valor único aqui é o ponto que o app aplica por
/// padrão: RIR no meio da faixa e descanso maior para compostos, menor para isolados.
public struct GoalDefaults: Sendable, Hashable {
    /// Faixa de repetições de exercícios compostos (`MovementPattern.isCompound == true`).
    public let compoundRepRange: ClosedRange<Int>
    /// Faixa de repetições de exercícios isolados.
    public let isolationRepRange: ClosedRange<Int>
    /// RIR alvo das séries de trabalho.
    public let targetRIR: Int
    /// Séries de trabalho por grupo primário por semana (§7.8 R3 compara com esta faixa).
    public let weeklySetsPerMuscle: ClosedRange<Int>
    /// Descanso entre séries de compostos, em segundos.
    public let compoundRestSeconds: Int
    /// Descanso entre séries de isolados, em segundos.
    public let isolationRestSeconds: Int
    /// Séries por exercício num dia de treino.
    public let setsPerExercise: Int

    public init(
        compoundRepRange: ClosedRange<Int>,
        isolationRepRange: ClosedRange<Int>,
        targetRIR: Int,
        weeklySetsPerMuscle: ClosedRange<Int>,
        compoundRestSeconds: Int,
        isolationRestSeconds: Int,
        setsPerExercise: Int
    ) {
        self.compoundRepRange = compoundRepRange
        self.isolationRepRange = isolationRepRange
        self.targetRIR = targetRIR
        self.weeklySetsPerMuscle = weeklySetsPerMuscle
        self.compoundRestSeconds = compoundRestSeconds
        self.isolationRestSeconds = isolationRestSeconds
        self.setsPerExercise = setsPerExercise
    }
}

extension ProgramGoal {
    /// Padrões de prescrição do objetivo (tabela SPEC §7.9).
    public var defaults: GoalDefaults {
        switch self {
        case .hypertrophy:
            return GoalDefaults(
                compoundRepRange: 6...12, // SPEC §7.9: 6–12 em compostos
                isolationRepRange: 8...15, // SPEC §7.9: 8–15 em isolados
                targetRIR: 2, // SPEC §7.9: RIR 1–3, meio da faixa
                weeklySetsPerMuscle: 10...20, // SPEC §7.9: 10–20 séries/grupo/semana
                compoundRestSeconds: 150, // SPEC §7.9: descanso 90–180 s
                isolationRestSeconds: 90, // SPEC §7.9: piso da faixa 90–180 s
                setsPerExercise: 3 // SPEC §7.9: 5 exercícios × 3 séries por dia
            )
        case .strength:
            return GoalDefaults(
                compoundRepRange: 3...6, // SPEC §7.9: 3–6
                isolationRepRange: 6...10, // SPEC §7.9: acessórios acima da faixa de força
                targetRIR: 2, // SPEC §7.9: RIR 1–3, meio da faixa
                weeklySetsPerMuscle: 6...12, // SPEC §7.9: 6–12 séries/grupo/semana
                compoundRestSeconds: 240, // SPEC §7.9: descanso 180–300 s
                isolationRestSeconds: 150, // SPEC §7.9: acessórios com descanso menor
                setsPerExercise: 4 // SPEC §7.9: mais séries com menos repetições
            )
        case .endurance:
            return GoalDefaults(
                compoundRepRange: 12...20, // SPEC §7.9: 12–20
                isolationRepRange: 15...20, // SPEC §7.9: topo da faixa 12–20
                targetRIR: 3, // SPEC §7.9: RIR 2–4, meio da faixa
                weeklySetsPerMuscle: 8...16, // SPEC §7.9: 8–16 séries/grupo/semana
                compoundRestSeconds: 75, // SPEC §7.9: descanso 60–90 s
                isolationRestSeconds: 60, // SPEC §7.9: piso da faixa 60–90 s
                setsPerExercise: 3 // SPEC §7.9
            )
        case .longevity:
            return GoalDefaults(
                compoundRepRange: 8...12, // SPEC §7.9: 8–15, parte baixa em compostos
                isolationRepRange: 10...15, // SPEC §7.9: 8–15, parte alta em isolados
                targetRIR: 3, // SPEC §7.9: RIR 2–3, lado conservador
                weeklySetsPerMuscle: 6...12, // SPEC §7.9: 6–12 séries/grupo/semana
                compoundRestSeconds: 120, // SPEC §7.9: descanso 90–120 s
                isolationRestSeconds: 90, // SPEC §7.9: piso da faixa 90–120 s
                setsPerExercise: 2 // SPEC §7.9: sessões curtas; 30–60 min/semana de força (Momma 2022)
            )
        case .combat:
            return GoalDefaults(
                compoundRepRange: 3...6, // SPEC §7.9: força máxima 3–6 reps
                isolationRepRange: 6...10, // SPEC §7.9: acessórios (pegada, tronco) acima da faixa de força
                targetRIR: 2, // SPEC §7.9: RIR 2–3, lado de força
                weeklySetsPerMuscle: 6...12, // SPEC §7.9: volume de força
                compoundRestSeconds: 180, // SPEC §7.9: descanso completo em força/potência
                isolationRestSeconds: 90, // SPEC §7.9: acessórios com descanso menor
                setsPerExercise: 3 // SPEC §7.9: 3–5 séries de potência, 3 como padrão
            )
        }
    }
}

extension MovementPattern {
    /// `true` para padrões multiarticulares, que usam `compoundRepRange` e `compoundRestSeconds`
    /// de `GoalDefaults`; `false` para isolados. Switch exaustivo de propósito: um case novo em
    /// `MovementPattern` obriga a decidir aqui.
    public var isCompound: Bool {
        switch self {
        case .horizontalPush, .verticalPush, .horizontalPull, .verticalPull,
             .squat, .lunge, .hinge, .hipThrust, .carry, .explosive:
            return true
        case .chestFly, .shoulderIsolation, .elbowFlexion, .elbowExtension,
             .kneeExtension, .kneeFlexion, .calfRaise, .coreFlexion, .coreStability, .neck:
            return false
        }
    }
}
