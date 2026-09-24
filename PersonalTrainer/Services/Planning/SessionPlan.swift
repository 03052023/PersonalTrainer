import Foundation
import TrainerCore

/// Plano do próximo treino calculado por `SessionPlanning` (SPEC §7.2/§7.3).
/// DTO puro: nada aqui é persistido. Ao iniciar a sessão, cada `PlannedExercise` vira um
/// `SessionExerciseModel` com a prescrição copiada como snapshot (ARCHITECTURE §5, AR-10).
struct SessionPlan: Sendable, Hashable {
    let programID: UUID
    let programName: String
    let programDayID: UUID
    let programDayName: String
    /// Ordenado por `target.order`.
    let exercises: [PlannedExercise]
    let generatedAt: Date
    /// SPEC §7.5: as prescrições já são as de semana leve (`DeloadPolicy.deloadPrescription`).
    /// O `SessionCoordinator` copia para `WorkoutSessionModel.isDeload` ao iniciar a sessão, e é
    /// isso que faz a progressão ignorar a sessão (P3) e o `DeloadScheduler` contar a passagem.
    let isDeload: Bool
    /// Por que este dia (CA4-5). `nil` em planos montados fora do planejador (previews, testes).
    let reason: PlanReason?
    /// SPEC RF-42: os exercícios já são os equivalentes de casa (§7.13 H1–H4). O programa não muda;
    /// a Home mostra a faixa "Em casa".
    let isHomeMode: Bool
    /// Avisos do modo casa em pt-BR, na ordem do dia: um "Sem opção em casa para X" por exercício
    /// que saiu da sessão (§7.13 H2). Vazio fora do modo casa.
    let homeNotices: [String]
    /// Duração estimada em minutos (DESIGN §9.2, `SessionDurationEstimate`); 0 sem exercícios.
    let estimatedMinutes: Int

    /// `isDeload`, `reason` e os campos da versão 2.1 têm padrão para que quem já monta
    /// `SessionPlan` à mão (previews, testes, doubles) continue compilando sem mudança. Sem
    /// `estimatedMinutes`, a estimativa é calculada aqui, com todo exercício medido em repetições;
    /// o planejador passa a dele, que conhece a medida de cada exercício (SPEC RF-43).
    init(
        programID: UUID,
        programName: String,
        programDayID: UUID,
        programDayName: String,
        exercises: [PlannedExercise],
        generatedAt: Date,
        isDeload: Bool = false,
        reason: PlanReason? = nil,
        isHomeMode: Bool = false,
        homeNotices: [String] = [],
        estimatedMinutes: Int? = nil
    ) {
        self.programID = programID
        self.programName = programName
        self.programDayID = programDayID
        self.programDayName = programDayName
        self.exercises = exercises
        self.generatedAt = generatedAt
        self.isDeload = isDeload
        self.reason = reason
        self.isHomeMode = isHomeMode
        self.homeNotices = homeNotices
        self.estimatedMinutes = estimatedMinutes
            ?? SessionDurationEstimate.minutes(for: exercises, traits: .empty)
    }
}

/// Um exercício do plano com a prescrição já calculada pelo motor.
struct PlannedExercise: Sendable, Hashable, Identifiable {
    /// Gerado pelo planejador; torna-se `SessionExerciseModel.uuid` quando a sessão é iniciada,
    /// para que a UI possa referenciar o exercício antes e depois do início com o mesmo id.
    let id: UUID
    let exercise: ExerciseDefinition
    let target: ExerciseTarget
    let prescription: ExercisePrescription
}
