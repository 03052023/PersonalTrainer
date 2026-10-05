import Foundation

/// A semana que um plano pede (SPEC §7.15 M3; docs/V23-UI-CONTRACT.md §3.1): os dias na ordem da rotação e
/// quantas sessões por semana.
public struct PlanDemand: Sendable, Hashable {
    public let programID: UUID
    public let goal: ProgramGoal
    public let name: String
    /// Na ordem da rotação (`ProgramDayTemplate.order`, empate pelo id).
    public let sessions: [PlanSessionDemand]
    /// Sessões por semana, de 1 ao número de dias (0 num plano sem dias). Menos que o número de dias
    /// é a saída "menos sessões" de M5: a rotação continua de uma semana para a outra.
    public let sessionsPerWeek: Int

    public init(
        programID: UUID,
        goal: ProgramGoal,
        name: String,
        sessions: [PlanSessionDemand],
        sessionsPerWeek: Int
    ) {
        self.programID = programID
        self.goal = goal
        self.name = name
        self.sessions = sessions
        self.sessionsPerWeek = sessionsPerWeek
    }

    /// Todos os dias do plano são de aeróbico (o plano Cardio).
    public var isCardio: Bool {
        !sessions.isEmpty && sessions.allSatisfy { $0.kind == .cardio }
    }

    /// Grupos que fazem de um dia de força um "dia de pernas" (A5).
    public static let lowerBodyGroups: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]

    /// A mesma demanda com as sessões rodadas para começar em `programDayID` (SPEC §7.15 M3): é a fase do
    /// plano, a sessão que a rotação (S2, S8) daria no começo da semana. A ordem da rotação não muda, só o
    /// ponto de partida. Um dia que não está no plano deixa a demanda como está.
    public func startingAt(programDayID: UUID) -> PlanDemand {
        guard let index = sessions.firstIndex(where: { $0.programDayID == programDayID }), index > 0 else {
            return self
        }
        let rotated = Array(sessions[index...]) + Array(sessions[..<index])
        return PlanDemand(
            programID: programID,
            goal: goal,
            name: name,
            sessions: rotated,
            sessionsPerWeek: sessionsPerWeek
        )
    }

    /// Monta a demanda de um programa (SPEC §7.15 M3):
    /// - um dia com algum exercício de padrão `cardio` é de aeróbico, com a intensidade do mais forte;
    /// - os outros são de força, com os grupos primários de todos os exercícios do dia;
    /// - `sessionsPerWeek` ausente vale o número de dias; o valor é limitado a 1…dias.
    ///
    /// `exercises` é o catálogo por id; um alvo cujo exercício falta é ignorado. `minutesPerDay` traz a
    /// duração estimada de cada dia pelo id do dia, quando quem chama sabe (o app, por
    /// `SessionDurationEstimate`).
    public static func from(
        program: ProgramTemplate,
        exercises: [UUID: ExerciseDefinition],
        sessionsPerWeek: Int? = nil,
        minutesPerDay: [UUID: Int] = [:]
    ) -> PlanDemand {
        let days = program.days.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let sessions = days.map { day in
            session(for: day, exercises: exercises, minutes: minutesPerDay[day.id] ?? 0)
        }
        let count = sessions.count
        let perWeek = count == 0 ? 0 : min(max(sessionsPerWeek ?? count, 1), count)
        return PlanDemand(
            programID: program.id,
            goal: program.effectiveGoal,
            name: program.name,
            sessions: sessions,
            sessionsPerWeek: perWeek
        )
    }

    private static func session(
        for day: ProgramDayTemplate,
        exercises: [UUID: ExerciseDefinition],
        minutes: Int
    ) -> PlanSessionDemand {
        var cardioIntensity: CardioIntensity?
        var muscles: Set<MuscleGroup> = []
        for target in day.exercises {
            guard let exercise = exercises[target.exerciseID] else {
                continue
            }
            if exercise.movementPattern == .cardio {
                let intensity = CardioIntensity.classify(slug: exercise.slug, sets: target.sets, repMax: target.repMax)
                if let current = cardioIntensity, current.rank >= intensity.rank {
                    continue
                }
                cardioIntensity = intensity
            } else {
                muscles.formUnion(exercise.primaryMuscles)
            }
        }
        if let cardioIntensity {
            return PlanSessionDemand(
                programDayID: day.id,
                dayName: day.name,
                kind: .cardio,
                cardioIntensity: cardioIntensity,
                estimatedMinutes: minutes
            )
        }
        return PlanSessionDemand(
            programDayID: day.id,
            dayName: day.name,
            kind: .strength,
            primaryMuscles: muscles,
            isLowerBody: !muscles.isDisjoint(with: lowerBodyGroups),
            estimatedMinutes: minutes
        )
    }
}
