import Foundation
import TrainerCore

/// Tudo o que a folha "Informações do exercício" mostra (SPEC RF-47; docs/V22-CONTRACT.md §2.2).
/// Valor puro: a tela Hoje monta a partir do plano (`PlannedExercise`) e a ficha da sessão a partir
/// do snapshot gravado (`SessionExerciseModel`); "Da última vez" chega pronto do
/// `SessionPlanning.lastSession(forExerciseID:)`.
///
/// `targetRIR` existe só para frases concretas de primeira vez ("uma carga que daria para levantar
/// umas 9 vezes"); a folha nunca mostra RIR nem "pare N antes do limite" (SPEC RF-41, decisão 18).
///
/// Desde a 2.3 (docs/V23-UI-CONTRACT.md §4.4), o conteúdo também leva o `slug`, a marca de exercício
/// personalizado, os grupos primários e o padrão de movimento: com eles a folha acha a guia do
/// "Como fazer" (SPEC E1, RF-40) e reconhece o aeróbico (SPEC §7.14). Os dois `init` de uso
/// preenchem tudo; no `init` completo esses campos têm padrão, para os testes e previews antigos.
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
    /// Slug do catálogo do exercício realizado (na sessão, o substituto quando houve troca; SPEC E1).
    /// `nil` quando o exercício sumiu do catálogo.
    let slug: String?
    /// Exercício criado pela pessoa: nunca tem guia (SPEC RF-40, E1).
    let isCustom: Bool
    /// Grupos primários do catálogo, para o "Trabalha: …" da guia (SPEC E2).
    let primaryMuscles: [MuscleGroup]
    /// Padrão de movimento; `.cardio` = aeróbico (SPEC §7.14 F1).
    let movementPattern: MovementPattern?

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
        lastSession: ExerciseLastSession?,
        slug: String? = nil,
        isCustom: Bool = false,
        primaryMuscles: [MuscleGroup] = [],
        movementPattern: MovementPattern? = nil
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
        self.slug = slug
        self.isCustom = isCustom
        self.primaryMuscles = primaryMuscles
        self.movementPattern = movementPattern
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
            lastSession: lastSession,
            slug: planned.exercise.slug,
            isCustom: planned.exercise.isCustom,
            primaryMuscles: planned.exercise.primaryMuscles,
            movementPattern: planned.exercise.movementPattern
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
            lastSession: lastSession,
            slug: catalogExercise?.slug,
            isCustom: catalogExercise?.isCustom ?? false,
            primaryMuscles: catalogExercise?.primaryMuscles ?? [],
            movementPattern: catalogExercise?.movementPattern
        )
    }

    /// Como a carga de hoje aparece (SPEC RF-46). Desde a 2.3 (D3), 0 num exercício com equipamento é
    /// "sem carga externa": aparece como sem carga (`toChoose`), nunca "0 kg".
    var loadDisplay: TodayTargetText.LoadDisplay {
        if equipment != .bodyweight, let load, load <= 0 {
            return .toChoose
        }
        return TodayTargetText.loadDisplay(load: load, unit: loadUnit, equipment: equipment)
    }

    /// Aeróbico (SPEC §7.14 F1): o padrão `cardio` do catálogo.
    var isCardio: Bool {
        movementPattern == .cardio
    }

    /// Intensidade pelo teste da fala (SPEC F2, `CardioIntensity.classify`); `nil` fora do aeróbico.
    var cardioIntensity: CardioIntensity? {
        CardioText.intensity(pattern: movementPattern, slug: slug, sets: sets, repMax: repMax)
    }

    /// Nível (ou carga) de hoje maior que 0. No aeróbico, vale F3 (sobe o nível) em vez dos blocos de F6.
    var hasLevel: Bool {
        (load ?? 0) > 0
    }

    /// O selo da nota (DESIGN §7), o mesmo da ficha: nos intervalos do Cardio sem nível, a nota `increase`
    /// diz "Mais um bloco" (SPEC §7.14 F6, RF-47; 2.4). `nil` = sem selo.
    var badgeText: String? {
        note.badgeText(isCardio: isCardio, hasLevel: hasLevel, loadUnit: loadUnit)
    }
}
