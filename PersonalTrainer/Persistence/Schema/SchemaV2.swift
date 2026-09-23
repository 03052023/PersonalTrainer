import Foundation
import SwiftData
import TrainerCore

/// Versão 2 do esquema SwiftData do iPhone (T2.11, docs/M2-CONTRACT.md §2).
///
/// Redeclara os 8 modelos de `SchemaV1` com os mesmos nomes e campos e acrescenta:
///
/// | Modelo | Campo novo | Padrão |
/// |--------|-----------|--------|
/// | `ExerciseModel` | `movementPatternRaw: String?` | `nil` |
/// | `ExerciseModel` | `isCustom: Bool` | `false` |
/// | `ProgramModel` | `goalRaw: String` | `"hypertrophy"` |
/// | `ProgramModel` | `summary: String?` | `nil` |
/// | `SessionExerciseModel` | `prescribedTargetReps: Int` | `0` (desconhecido → usar `prescribedRepMin`) |
///
/// Todo campo novo tem valor padrão NA DECLARAÇÃO: é o que o `@Model` registra como
/// `defaultValue` do atributo e o que permite o estágio `.lightweight` V1→V2 preencher as
/// linhas existentes sem código de migração. Os inits recebem os campos novos no fim, com o
/// mesmo padrão, para que todo call site escrito contra V1 continue compilando.
///
/// Regra R6 (AGENTS.md): depois que V2 for publicada, este arquivo congela como `SchemaV1`.
/// Mudança futura = `SchemaV3` + estágio em `PersonalTrainerMigrationPlan` + teste de migração.
///
/// O checklist de V1 continua valendo (ARCHITECTURE §5, §15): `uuid` gerado no cliente,
/// enums/arrays como `String`, relação declarada só no pai, to-many não opcional iniciado em
/// `[]`, relação com `ExerciseModel` nunca `cascade`.
enum SchemaV2: VersionedSchema {
    // Propriedades computadas (e não `static var` armazenadas) para não criar estado
    // global mutável, proibido em Swift 6 strict concurrency.
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            ExerciseModel.self,
            ProgramModel.self,
            ProgramDayModel.self,
            ProgramExerciseModel.self,
            WorkoutSessionModel.self,
            SessionExerciseModel.self,
            SetLogModel.self,
            UserSettingsModel.self,
        ]
    }

    /// Objetivo gravado quando o programa não informa um (SPEC §7.9: hipertrofia é o padrão).
    /// Precisa ser igual ao literal da declaração de `ProgramModel.goalRaw`, que o `@Model`
    /// exige como expressão literal para registrar o padrão da migração leve.
    static let defaultGoalRaw = "hypertrophy"

    // MARK: - Codificação de arrays como CSV (ARCHITECTURE §5, decisão 2)

    /// Mesmo formato de `SchemaV1`: o CSV gravado por V1 é lido por V2 sem conversão.
    /// Redeclarado aqui para V2 não depender de uma versão congelada.
    static func encodeMuscleGroups(_ groups: [MuscleGroup]) -> String {
        groups.map { $0.rawValue }.joined(separator: ",")
    }

    /// Valores desconhecidos são descartados em vez de derrubar a leitura: um case novo
    /// gravado por versão futura do app não pode impedir o catálogo de abrir.
    static func decodeMuscleGroups(_ raw: String) -> [MuscleGroup] {
        raw.split(separator: ",").compactMap { piece in
            MuscleGroup(rawValue: String(piece).trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - Catálogo

    /// Exercício do catálogo. Nunca é deletado fisicamente: `isArchived` esconde e o
    /// histórico continua apontando para ele (ARCHITECTURE §5).
    @Model
    final class ExerciseModel {
        @Attribute(.unique) var uuid: UUID
        @Attribute(.unique) var slug: String
        var name: String
        var primaryMusclesRaw: String
        var secondaryMusclesRaw: String
        var equipmentRaw: String
        var loadUnitRaw: String
        var loadIncrement: Double
        var isUnilateral: Bool
        var machineNotes: String?
        var isArchived: Bool
        /// `MovementPattern.rawValue` (RF-34). `nil` em exercícios migrados de V1 até o seed v2
        /// preencher, e em exercícios criados pelo usuário sem padrão escolhido.
        var movementPatternRaw: String? = nil
        /// `true` para exercício criado pelo usuário (T2.5). O seed nunca o altera.
        var isCustom: Bool = false

        init(
            uuid: UUID,
            slug: String,
            name: String,
            primaryMusclesRaw: String,
            secondaryMusclesRaw: String,
            equipmentRaw: String,
            loadUnitRaw: String,
            loadIncrement: Double,
            isUnilateral: Bool,
            machineNotes: String?,
            isArchived: Bool,
            movementPatternRaw: String? = nil,
            isCustom: Bool = false
        ) {
            self.uuid = uuid
            self.slug = slug
            self.name = name
            self.primaryMusclesRaw = primaryMusclesRaw
            self.secondaryMusclesRaw = secondaryMusclesRaw
            self.equipmentRaw = equipmentRaw
            self.loadUnitRaw = loadUnitRaw
            self.loadIncrement = loadIncrement
            self.isUnilateral = isUnilateral
            self.machineNotes = machineNotes
            self.isArchived = isArchived
            self.movementPatternRaw = movementPatternRaw
            self.isCustom = isCustom
        }

        // Propriedades computadas: não persistidas, só expõem os tipos de TrainerCore.

        var primaryMuscles: [MuscleGroup] {
            get { SchemaV2.decodeMuscleGroups(primaryMusclesRaw) }
            set { primaryMusclesRaw = SchemaV2.encodeMuscleGroups(newValue) }
        }

        var secondaryMuscles: [MuscleGroup] {
            get { SchemaV2.decodeMuscleGroups(secondaryMusclesRaw) }
            set { secondaryMusclesRaw = SchemaV2.encodeMuscleGroups(newValue) }
        }

        /// `nil` quando `equipmentRaw` não é um case conhecido; os mappers tratam como erro.
        var equipment: Equipment? {
            Equipment(rawValue: equipmentRaw)
        }

        /// `nil` quando `loadUnitRaw` não é um case conhecido; os mappers tratam como erro.
        var loadUnit: LoadUnit? {
            LoadUnit(rawValue: loadUnitRaw)
        }

        /// `nil` sem padrão gravado ou com raw desconhecido. Diferente de `equipment`, não é
        /// erro de mapeamento: o padrão é opcional no domínio e só alimenta o "Trocar" (RF-34).
        var movementPattern: MovementPattern? {
            get { movementPatternRaw.flatMap { MovementPattern(rawValue: $0) } }
            set { movementPatternRaw = newValue?.rawValue }
        }
    }

    // MARK: - Programa

    @Model
    final class ProgramModel {
        var uuid: UUID
        var name: String
        var isActive: Bool
        var createdAt: Date
        /// `ProgramGoal.rawValue` (SPEC §7.9). Programas migrados de V1 viram hipertrofia.
        var goalRaw: String = "hypertrophy"
        /// Descrição curta em pt-BR para o seletor de programas.
        var summary: String? = nil

        @Relationship(deleteRule: .cascade, inverse: \ProgramDayModel.program)
        var days: [ProgramDayModel] = []

        init(
            uuid: UUID,
            name: String,
            isActive: Bool,
            createdAt: Date,
            days: [ProgramDayModel] = [],
            goalRaw: String = SchemaV2.defaultGoalRaw,
            summary: String? = nil
        ) {
            self.uuid = uuid
            self.name = name
            self.isActive = isActive
            self.createdAt = createdAt
            self.days = days
            self.goalRaw = goalRaw
            self.summary = summary
        }

        /// `nil` quando `goalRaw` não é um case conhecido (gravado por versão futura do app);
        /// quem consome usa `?? .hypertrophy`, como `ProgramTemplate.effectiveGoal`.
        /// Atribuir `nil` grava o padrão (hipertrofia).
        var goal: ProgramGoal? {
            get { ProgramGoal(rawValue: goalRaw) }
            set { goalRaw = newValue?.rawValue ?? SchemaV2.defaultGoalRaw }
        }
    }

    @Model
    final class ProgramDayModel {
        var uuid: UUID
        var name: String
        var order: Int

        @Relationship(deleteRule: .cascade, inverse: \ProgramExerciseModel.day)
        var exercises: [ProgramExerciseModel] = []

        /// Inverso de `ProgramModel.days`; declarado sem macro (o pai já define a regra).
        var program: ProgramModel?

        init(
            uuid: UUID,
            name: String,
            order: Int,
            exercises: [ProgramExerciseModel] = [],
            program: ProgramModel? = nil
        ) {
            self.uuid = uuid
            self.name = name
            self.order = order
            self.exercises = exercises
            self.program = program
        }
    }

    @Model
    final class ProgramExerciseModel {
        var uuid: UUID
        var order: Int
        var sets: Int
        var repMin: Int
        var repMax: Int
        var targetRIR: Int
        var restSeconds: Int
        var startingLoad: Double?

        /// Só navegação; `nullify` garante que apagar o programa nunca toca o catálogo.
        @Relationship(deleteRule: .nullify)
        var exercise: ExerciseModel?

        /// Inverso de `ProgramDayModel.exercises`.
        var day: ProgramDayModel?

        init(
            uuid: UUID,
            order: Int,
            sets: Int,
            repMin: Int,
            repMax: Int,
            targetRIR: Int,
            restSeconds: Int,
            startingLoad: Double?,
            exercise: ExerciseModel? = nil,
            day: ProgramDayModel? = nil
        ) {
            self.uuid = uuid
            self.order = order
            self.sets = sets
            self.repMin = repMin
            self.repMax = repMax
            self.targetRIR = targetRIR
            self.restSeconds = restSeconds
            self.startingLoad = startingLoad
            self.exercise = exercise
            self.day = day
        }
    }

    // MARK: - Sessão

    /// Uma execução de um Dia. `programDayUUID`/`programDayName` são cópias, não relação:
    /// editar o programa depois não reescreve o histórico (ARCHITECTURE §5, decisão 3; AR-10).
    @Model
    final class WorkoutSessionModel {
        var uuid: UUID
        var programDayUUID: UUID
        var programDayName: String
        var statusRaw: String
        var startedAt: Date
        var endedAt: Date?
        var notes: String
        var hkWorkoutUUID: UUID?
        var avgHeartRate: Double?
        var maxHeartRate: Double?
        var isDeload: Bool
        /// `DeviceSource.rawValue` (`iphone`, `watch`, `importer`).
        var sourceRaw: String

        @Relationship(deleteRule: .cascade, inverse: \SessionExerciseModel.session)
        var exercises: [SessionExerciseModel] = []

        init(
            uuid: UUID,
            programDayUUID: UUID,
            programDayName: String,
            statusRaw: String,
            startedAt: Date,
            endedAt: Date?,
            notes: String,
            hkWorkoutUUID: UUID?,
            avgHeartRate: Double?,
            maxHeartRate: Double?,
            isDeload: Bool,
            sourceRaw: String,
            exercises: [SessionExerciseModel] = []
        ) {
            self.uuid = uuid
            self.programDayUUID = programDayUUID
            self.programDayName = programDayName
            self.statusRaw = statusRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.notes = notes
            self.hkWorkoutUUID = hkWorkoutUUID
            self.avgHeartRate = avgHeartRate
            self.maxHeartRate = maxHeartRate
            self.isDeload = isDeload
            self.sourceRaw = sourceRaw
            self.exercises = exercises
        }

        /// `nil` quando `statusRaw` não é um case conhecido; os mappers tratam como erro.
        var status: SessionStatus? {
            SessionStatus(rawValue: statusRaw)
        }
    }

    /// Snapshot da prescrição de um exercício dentro da sessão (ARCHITECTURE §5, decisão 3).
    @Model
    final class SessionExerciseModel {
        var uuid: UUID
        var order: Int
        var exerciseUUID: UUID
        var exerciseName: String
        var prescribedLoad: Double?
        var prescribedSets: Int
        var prescribedRepMin: Int
        var prescribedRepMax: Int
        var prescribedRIR: Int
        var restSeconds: Int
        var noteRaw: String
        var wasSkipped: Bool
        var substitutedFromUUID: UUID?
        /// `ExercisePrescription.targetReps` no momento do planejamento (SPEC P5). `0` =
        /// desconhecido (sessões gravadas por V1): a tela usa `prescribedRepMin`.
        var prescribedTargetReps: Int = 0

        /// Só navegação; `nullify` garante que apagar a sessão nunca toca o catálogo.
        @Relationship(deleteRule: .nullify)
        var exercise: ExerciseModel?

        @Relationship(deleteRule: .cascade, inverse: \SetLogModel.sessionExercise)
        var sets: [SetLogModel] = []

        /// Inverso de `WorkoutSessionModel.exercises`.
        var session: WorkoutSessionModel?

        init(
            uuid: UUID,
            order: Int,
            exerciseUUID: UUID,
            exerciseName: String,
            prescribedLoad: Double?,
            prescribedSets: Int,
            prescribedRepMin: Int,
            prescribedRepMax: Int,
            prescribedRIR: Int,
            restSeconds: Int,
            noteRaw: String,
            wasSkipped: Bool,
            substitutedFromUUID: UUID?,
            exercise: ExerciseModel? = nil,
            sets: [SetLogModel] = [],
            session: WorkoutSessionModel? = nil,
            prescribedTargetReps: Int = 0
        ) {
            self.uuid = uuid
            self.order = order
            self.exerciseUUID = exerciseUUID
            self.exerciseName = exerciseName
            self.prescribedLoad = prescribedLoad
            self.prescribedSets = prescribedSets
            self.prescribedRepMin = prescribedRepMin
            self.prescribedRepMax = prescribedRepMax
            self.prescribedRIR = prescribedRIR
            self.restSeconds = restSeconds
            self.noteRaw = noteRaw
            self.wasSkipped = wasSkipped
            self.substitutedFromUUID = substitutedFromUUID
            self.exercise = exercise
            self.sets = sets
            self.session = session
            self.prescribedTargetReps = prescribedTargetReps
        }

        /// `nil` quando `noteRaw` não é um case conhecido.
        var note: PrescriptionNote? {
            PrescriptionNote(rawValue: noteRaw)
        }
    }

    /// Série registrada. `uuid` é `.unique` porque é a chave de dedup entre iPhone e Watch
    /// (ARCHITECTURE §7, AR-4). Só RIR é persistido (ADR 004).
    @Model
    final class SetLogModel {
        @Attribute(.unique) var uuid: UUID
        var index: Int
        var load: Double
        var reps: Int
        var rir: Int?
        var isWarmup: Bool
        var completedAt: Date
        var sourceRaw: String
        var updatedAt: Date

        /// Inverso de `SessionExerciseModel.sets`.
        var sessionExercise: SessionExerciseModel?

        init(
            uuid: UUID,
            index: Int,
            load: Double,
            reps: Int,
            rir: Int?,
            isWarmup: Bool,
            completedAt: Date,
            sourceRaw: String,
            updatedAt: Date,
            sessionExercise: SessionExerciseModel? = nil
        ) {
            self.uuid = uuid
            self.index = index
            self.load = load
            self.reps = reps
            self.rir = rir
            self.isWarmup = isWarmup
            self.completedAt = completedAt
            self.sourceRaw = sourceRaw
            self.updatedAt = updatedAt
            self.sessionExercise = sessionExercise
        }
    }

    // MARK: - Configuração

    /// Linha única, criada no primeiro launch (ARCHITECTURE §5, §11). Igual à de V1: o
    /// onboarding do M2 usa `@AppStorage("hasCompletedOnboarding")`, não o SwiftData.
    @Model
    final class UserSettingsModel {
        @Attribute(.unique) var uuid: UUID
        var weekStartsOnMonday: Bool
        /// JSON `{"chest": 2, ...}` com chaves = `MuscleGroup.rawValue` (SPEC §7.4).
        var weeklyTargetsRaw: String
        var healthKitEnabled: Bool
        var defaultRestSeconds: Int
        var schemaSeedVersion: Int

        init(
            uuid: UUID,
            weekStartsOnMonday: Bool,
            weeklyTargetsRaw: String,
            healthKitEnabled: Bool,
            defaultRestSeconds: Int,
            schemaSeedVersion: Int
        ) {
            self.uuid = uuid
            self.weekStartsOnMonday = weekStartsOnMonday
            self.weeklyTargetsRaw = weeklyTargetsRaw
            self.healthKitEnabled = healthKitEnabled
            self.defaultRestSeconds = defaultRestSeconds
            self.schemaSeedVersion = schemaSeedVersion
        }

        /// Metas semanais por grupo. Grupos ausentes ficam a cargo de quem consome
        /// (padrão 2×/semana, SPEC §7.4); aqui só se codifica o que foi configurado.
        var weeklyTargets: [MuscleGroup: Int] {
            get {
                guard
                    let data = weeklyTargetsRaw.data(using: .utf8),
                    let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
                else {
                    return [:]
                }
                var result: [MuscleGroup: Int] = [:]
                for (key, value) in decoded {
                    if let group = MuscleGroup(rawValue: key) {
                        result[group] = value
                    }
                }
                return result
            }
            set {
                var raw: [String: Int] = [:]
                for (group, value) in newValue {
                    raw[group.rawValue] = value
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                if
                    let data = try? encoder.encode(raw),
                    let string = String(data: data, encoding: .utf8)
                {
                    weeklyTargetsRaw = string
                } else {
                    weeklyTargetsRaw = "{}"
                }
            }
        }
    }
}
