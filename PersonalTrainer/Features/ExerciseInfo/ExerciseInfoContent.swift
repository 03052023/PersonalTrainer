import Foundation
import TrainerCore

/// Tudo o que a folha "Informações do exercício" mostra (SPEC RF-47; docs/V22-CONTRACT.md §2.2).
/// Valor puro: a tela Hoje monta a partir do plano (`PlannedExercise`) e a ficha da sessão a partir
/// do snapshot gravado (`SessionExerciseModel`); "Da última vez" chega pronto do
/// `SessionPlanning.lastSession(forExerciseID:)`.
///
/// `targetRIR` existe só para frases concretas de primeira vez ("uma carga que daria para levantar
/// umas 9 vezes"); a folha nunca mostra RIR nem "pare N antes do limite" (SPEC RF-41, decisão 18).
struct ExerciseInfoContent: Sendable, Hashable, Identifiable {
    /// Linha que abriu a folha: `PlannedExercise.id` ou `SessionExerciseModel.uuid`. Serve de
    /// identidade para `.sheet(item:)`.
    let id: UUID
    /// `ExerciseDefinition.id` / `SessionExerciseModel.exerciseUUID`: chave do histórico (P3).
    let exerciseID: UUID
    let name: String
    /// `nil` quando o exercício sumiu do catálogo (relação anulada): tratado como exercício com carga.
    let equipment: Equipment?
    let loadUnit: LoadUnit
    let measure: ExerciseMeasure
    let machineNotes: String?
    let sets: Int
    /// Meta de hoje, já resolvida por `TodayTargetText.goal(targetReps:repMin:)`.
    let targetReps: Int
    let repMin: Int
    let repMax: Int
    let targetRIR: Int
    /// Carga prescrita; `nil` = primeira vez sem carga (SPEC P2).
    let load: Double?
    let restSeconds: Int
    let note: PrescriptionNote
    let lastSession: ExerciseLastSession?

    init(
        id: UUID,
        exerciseID: UUID,
        name: String,
        equipment: Equipment?,
        loadUnit: LoadUnit,
        measure: ExerciseMeasure,
        machineNotes: String?,
        sets: Int,
        targetReps: Int,
        repMin: Int,
        repMax: Int,
        targetRIR: Int,
        load: Double?,
        restSeconds: Int,
        note: PrescriptionNote,
        lastSession: ExerciseLastSession?
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.equipment = equipment
        self.loadUnit = loadUnit
        self.measure = measure
        self.machineNotes = machineNotes
        self.sets = sets
        self.targetReps = targetReps
        self.repMin = repMin
        self.repMax = repMax
        self.targetRIR = targetRIR
        self.load = load
        self.restSeconds = restSeconds
        self.note = note
        self.lastSession = lastSession
    }

    /// Tela Hoje: a partir do plano, antes de a sessão existir.
    init(planned: PlannedExercise, measure: ExerciseMeasure, lastSession: ExerciseLastSession?) {
        let prescription = planned.prescription
        self.init(
            id: planned.id,
            exerciseID: planned.exercise.id,
            name: planned.exercise.name,
            equipment: planned.exercise.equipment,
            loadUnit: planned.exercise.loadUnit,
            measure: measure,
            machineNotes: planned.exercise.machineNotes,
            sets: prescription.sets,
            targetReps: TodayTargetText.goal(targetReps: prescription.targetReps, repMin: prescription.repMin),
            repMin: prescription.repMin,
            repMax: prescription.repMax,
            targetRIR: prescription.targetRIR,
            load: prescription.load,
            restSeconds: prescription.restSeconds,
            note: prescription.note,
            lastSession: lastSession
        )
    }

    /// Ficha da sessão: a partir do snapshot gravado (a prescrição de quando a sessão começou).
    @MainActor
    init(sessionExercise: SessionExerciseModel, measure: ExerciseMeasure, lastSession: ExerciseLastSession?) {
        let catalogExercise = sessionExercise.exercise
        self.init(
            id: sessionExercise.uuid,
            exerciseID: sessionExercise.exerciseUUID,
            name: sessionExercise.exerciseName,
            equipment: catalogExercise?.equipment,
            loadUnit: catalogExercise?.loadUnit ?? .kilograms,
            measure: measure,
            machineNotes: catalogExercise?.machineNotes,
            sets: sessionExercise.prescribedSets,
            targetReps: TodayTargetText.goal(
                targetReps: sessionExercise.prescribedTargetReps,
                repMin: sessionExercise.prescribedRepMin
            ),
            repMin: sessionExercise.prescribedRepMin,
            repMax: sessionExercise.prescribedRepMax,
            targetRIR: sessionExercise.prescribedRIR,
            load: sessionExercise.prescribedLoad,
            restSeconds: sessionExercise.restSeconds,
            note: sessionExercise.note ?? .hold,
            lastSession: lastSession
        )
    }

    /// Como a carga de hoje aparece (SPEC RF-46).
    var loadDisplay: TodayTargetText.LoadDisplay {
        TodayTargetText.loadDisplay(load: load, unit: loadUnit, equipment: equipment)
    }
}
