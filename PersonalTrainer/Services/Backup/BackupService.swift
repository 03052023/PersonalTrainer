import Foundation
import SwiftData
import TrainerCore
import os

/// Implementação de `BackupServicing` sobre SwiftData (T2.4, SPEC RF-18, ARCHITECTURE §12).
///
/// Exportar lê o store inteiro e grava um `BackupDocument`. Importar substitui TUDO pelo conteúdo
/// do arquivo, nesta ordem:
/// 1. decodifica e valida o arquivo inteiro (`BackupDocument.decode` + `validate`);
/// 2. recusa se há sessão em andamento (`BackupError.inProgressSession`);
/// 3. tira um retrato do store atual em memória, para restaurar se a escrita falhar;
/// 4. apaga todos os modelos e salva; depois insere o conteúdo e salva; confere as contagens.
///
/// Por que dois `save()` e não um: `ExerciseModel.uuid/slug` e `SetLogModel.uuid` são `.unique`,
/// e o SwiftData transforma o insert de um valor já presente em upsert silencioso (ARCHITECTURE
/// §15). Reimportar o próprio backup (mesmos ids) com delete + insert no mesmo `save()` poderia
/// fundir o modelo novo com a linha que está sendo apagada. Com o delete já gravado, o insert
/// encontra o store vazio. Se a segunda fase falhar, `rollback()` descarta o que ficou pendente e
/// o retrato do passo 3 é reinserido.
///
/// Escreve direto no `ModelContext`, e não por `SessionCoordinating.apply`: a importação é uma
/// restauração do store, não um evento de sessão (não há observadores a notificar, e o
/// HealthKit não deve regravar treinos antigos).
@MainActor
final class BackupService: BackupServicing {
    private let modelContext: ModelContext
    private let appVersion: String
    private let timeZone: TimeZone
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "BackupService"
    )

    /// - Parameters:
    ///   - appVersion: gravado em `BackupDocument.appVersion`; `nil` lê do `Bundle.main`.
    ///   - timeZone: fuso do dia no nome sugerido do arquivo (o dia que o usuário vê).
    init(modelContext: ModelContext, appVersion: String? = nil, timeZone: TimeZone = .current) {
        self.modelContext = modelContext
        self.appVersion = appVersion ?? Self.bundleAppVersion(.main)
        self.timeZone = timeZone
    }

    // MARK: - BackupServicing

    func exportBackup(now: Date) throws -> Data {
        try makeDocument(exportedAt: now).encoded()
    }

    func importBackup(_ data: Data) throws -> BackupImportReport {
        let document = try BackupDocument.decode(from: data)
        try document.validate()

        if try hasSessionInProgress() {
            throw BackupError.inProgressSession
        }

        // Melhor esforço: um store com dado inválido (que não exporta) não pode impedir justamente
        // a restauração que o conserta. Sem retrato, só não há como desfazer uma falha de escrita.
        let previous: BackupDocument?
        do {
            previous = try makeDocument(exportedAt: document.exportedAt)
        } catch {
            logger.error("Sem retrato do store antes de importar: \(String(describing: error), privacy: .public)")
            previous = nil
        }

        // Fase 1: apagar. Em erro nada foi gravado; o rollback devolve o contexto ao estado salvo.
        do {
            try deleteAllModels()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            logger.error("Importação abortada ao apagar o store: \(String(describing: error), privacy: .public)")
            throw error
        }

        // Fase 2: inserir, salvar, conferir. Em erro, volta ao retrato.
        do {
            try insert(document)
            try modelContext.save()
            try verifyCounts(matching: document)
        } catch {
            modelContext.rollback()
            logger.error("Importação falhou ao gravar: \(String(describing: error), privacy: .public)")
            restore(previous)
            throw error
        }

        logger.info("Backup importado: \(document.exercises.count) exercícios, \(document.programs.count) programas, \(document.sessions.count) sessões, \(document.setCount) séries.")
        return BackupImportReport(
            exercises: document.exercises.count,
            programs: document.programs.count,
            sessions: document.sessions.count,
            sets: document.setCount
        )
    }

    func suggestedFileName(now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = Self.zeroPadded(components.year ?? 0, width: 4)
        let month = Self.zeroPadded(components.month ?? 0, width: 2)
        let day = Self.zeroPadded(components.day ?? 0, width: 2)
        return "PersonalTrainer-backup-\(year)-\(month)-\(day).json"
    }

    // MARK: - Exportação

    /// Ordem determinística (mesmo store → mesmo JSON): relações to-many do SwiftData não têm
    /// ordem, então tudo é ordenado por um campo do domínio com desempate por `uuid`.
    func makeDocument(exportedAt: Date) throws -> BackupDocument {
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseModel>())
            .sorted { lhs, rhs in
                lhs.slug != rhs.slug ? lhs.slug < rhs.slug : lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            .map { try exerciseRecord(from: $0) }

        let programs = try modelContext.fetch(FetchDescriptor<ProgramModel>())
            .sorted { lhs, rhs in
                lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            .map { programRecord(from: $0) }

        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSessionModel>())
            .sorted { lhs, rhs in
                lhs.startedAt != rhs.startedAt ? lhs.startedAt < rhs.startedAt : lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            .map { sessionRecord(from: $0) }

        // Linha única (ARCHITECTURE §5); se houver mais de uma, a escolha é determinística.
        let settings = try modelContext.fetch(FetchDescriptor<UserSettingsModel>())
            .min { $0.uuid.uuidString < $1.uuid.uuidString }
            .map { settingsRecord(from: $0) }

        return BackupDocument(
            exportedAt: exportedAt,
            appVersion: appVersion,
            exercises: exercises,
            programs: programs,
            sessions: sessions,
            settings: settings
        )
    }

    /// Equipamento e unidade desconhecidos lançam como nos mappers: `ExerciseDefinition` não os
    /// representa, e inventar um padrão mudaria a prescrição depois de restaurar.
    private func exerciseRecord(from model: ExerciseModel) throws -> BackupDocument.ExerciseRecord {
        guard let equipment = Equipment(rawValue: model.equipmentRaw) else {
            throw MappingError.invalidRawValue(model: "ExerciseModel", field: "equipmentRaw", value: model.equipmentRaw)
        }
        guard let loadUnit = LoadUnit(rawValue: model.loadUnitRaw) else {
            throw MappingError.invalidRawValue(model: "ExerciseModel", field: "loadUnitRaw", value: model.loadUnitRaw)
        }
        let definition = ExerciseDefinition(
            id: model.uuid,
            slug: model.slug,
            name: model.name,
            primaryMuscles: SchemaV1.decodeMuscleGroups(model.primaryMusclesRaw),
            secondaryMuscles: SchemaV1.decodeMuscleGroups(model.secondaryMusclesRaw),
            equipment: equipment,
            loadUnit: loadUnit,
            loadIncrement: model.loadIncrement,
            isUnilateral: model.isUnilateral,
            machineNotes: model.machineNotes,
            movementPattern: model.movementPatternRaw.flatMap { MovementPattern(rawValue: $0) },
            isCustom: model.isCustom
        )
        return BackupDocument.ExerciseRecord(definition: definition, isArchived: model.isArchived)
    }

    /// Um alvo sem exercício (relação anulada) não cabe em `ExerciseTarget` e já é inutilizável
    /// pelo planner; fica fora do backup, com log, em vez de impedir a exportação inteira.
    private func programRecord(from model: ProgramModel) -> BackupDocument.ProgramRecord {
        let days = model.days
            .sorted { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order : lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            .map { day -> ProgramDayTemplate in
                let targets = day.exercises
                    .sorted { lhs, rhs in
                        lhs.order != rhs.order ? lhs.order < rhs.order : lhs.uuid.uuidString < rhs.uuid.uuidString
                    }
                    .compactMap { programExercise -> ExerciseTarget? in
                        guard let exercise = programExercise.exercise else {
                            logger.error("Alvo \(programExercise.uuid.uuidString, privacy: .public) sem exercício ficou fora do backup.")
                            return nil
                        }
                        return ExerciseTarget(
                            id: programExercise.uuid,
                            exerciseID: exercise.uuid,
                            order: programExercise.order,
                            sets: programExercise.sets,
                            repMin: programExercise.repMin,
                            repMax: programExercise.repMax,
                            targetRIR: programExercise.targetRIR,
                            restSeconds: programExercise.restSeconds,
                            startingLoad: programExercise.startingLoad
                        )
                    }
                return ProgramDayTemplate(id: day.uuid, name: day.name, order: day.order, exercises: targets)
            }

        let template = ProgramTemplate(
            id: model.uuid,
            name: model.name,
            days: days,
            isActive: model.isActive,
            goal: ProgramGoal(rawValue: model.goalRaw),
            summary: model.summary
        )
        return BackupDocument.ProgramRecord(template: template, createdAt: model.createdAt)
    }

    private func sessionRecord(from model: WorkoutSessionModel) -> BackupDocument.SessionRecord {
        let exercises = model.exercises
            .sorted { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order : lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            .map { sessionExerciseRecord(from: $0) }

        return BackupDocument.SessionRecord(
            uuid: model.uuid,
            programDayUUID: model.programDayUUID,
            programDayName: model.programDayName,
            statusRaw: model.statusRaw,
            startedAt: model.startedAt,
            endedAt: model.endedAt,
            notes: model.notes,
            hkWorkoutUUID: model.hkWorkoutUUID,
            avgHeartRate: model.avgHeartRate,
            maxHeartRate: model.maxHeartRate,
            isDeload: model.isDeload,
            sourceRaw: model.sourceRaw,
            exercises: exercises
        )
    }

    private func sessionExerciseRecord(from model: SessionExerciseModel) -> BackupDocument.SessionExerciseRecord {
        let sets = model.sets
            .sorted { lhs, rhs in
                lhs.index != rhs.index ? lhs.index < rhs.index : lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            .map { setRecord(from: $0) }

        return BackupDocument.SessionExerciseRecord(
            uuid: model.uuid,
            order: model.order,
            exerciseUUID: model.exerciseUUID,
            exerciseName: model.exerciseName,
            prescribedLoad: model.prescribedLoad,
            prescribedSets: model.prescribedSets,
            prescribedRepMin: model.prescribedRepMin,
            prescribedRepMax: model.prescribedRepMax,
            prescribedTargetReps: model.prescribedTargetReps,
            prescribedRIR: model.prescribedRIR,
            restSeconds: model.restSeconds,
            noteRaw: model.noteRaw,
            wasSkipped: model.wasSkipped,
            substitutedFromUUID: model.substitutedFromUUID,
            sets: sets
        )
    }

    private func setRecord(from model: SetLogModel) -> BackupDocument.SetRecord {
        BackupDocument.SetRecord(
            uuid: model.uuid,
            index: model.index,
            load: model.load,
            reps: model.reps,
            rir: model.rir,
            isWarmup: model.isWarmup,
            completedAt: model.completedAt,
            sourceRaw: model.sourceRaw,
            updatedAt: model.updatedAt
        )
    }

    private func settingsRecord(from model: UserSettingsModel) -> BackupDocument.SettingsRecord {
        BackupDocument.SettingsRecord(
            uuid: model.uuid,
            weekStartsOnMonday: model.weekStartsOnMonday,
            weeklyTargetsRaw: model.weeklyTargetsRaw,
            healthKitEnabled: model.healthKitEnabled,
            defaultRestSeconds: model.defaultRestSeconds,
            schemaSeedVersion: model.schemaSeedVersion
        )
    }

    // MARK: - Importação

    private func hasSessionInProgress() throws -> Bool {
        // `#Predicate` só compara com valores capturados; o `rawValue` vai para um `let`.
        let inProgress = SessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.statusRaw == inProgress }
        )
        return try modelContext.fetchCount(descriptor) > 0
    }

    /// Apaga cada tipo explicitamente, filhos antes dos pais: o cascade só alcança filhos ligados,
    /// e um filho órfão (relação anulada) sobreviveria à importação.
    private func deleteAllModels() throws {
        try deleteAll(SetLogModel.self)
        try deleteAll(SessionExerciseModel.self)
        try deleteAll(WorkoutSessionModel.self)
        try deleteAll(ProgramExerciseModel.self)
        try deleteAll(ProgramDayModel.self)
        try deleteAll(ProgramModel.self)
        try deleteAll(ExerciseModel.self)
        try deleteAll(UserSettingsModel.self)
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        for model in try modelContext.fetch(FetchDescriptor<Model>()) {
            modelContext.delete(model)
        }
    }

    /// Cada modelo é inserido no contexto ANTES de ligar suas relações, o caminho mais previsível
    /// do SwiftData (mesmo padrão do `SessionCoordinator` e de `SchemaV1Tests`). Os campos do
    /// SchemaV2 são atribuídos depois do `init` para não depender da ordem dos parâmetros novos.
    private func insert(_ document: BackupDocument) throws {
        var exercisesByID: [UUID: ExerciseModel] = [:]
        exercisesByID.reserveCapacity(document.exercises.count)

        for record in document.exercises {
            let definition = record.definition
            let model = ExerciseModel(
                uuid: definition.id,
                slug: definition.slug,
                name: definition.name,
                primaryMusclesRaw: SchemaV1.encodeMuscleGroups(definition.primaryMuscles),
                secondaryMusclesRaw: SchemaV1.encodeMuscleGroups(definition.secondaryMuscles),
                equipmentRaw: definition.equipment.rawValue,
                loadUnitRaw: definition.loadUnit.rawValue,
                loadIncrement: definition.loadIncrement,
                isUnilateral: definition.isUnilateral,
                machineNotes: definition.machineNotes,
                isArchived: record.isArchived
            )
            modelContext.insert(model)
            model.movementPatternRaw = definition.movementPattern?.rawValue
            model.isCustom = definition.isCustom
            exercisesByID[definition.id] = model
        }

        for record in document.programs {
            try insertProgram(record, exercisesByID: exercisesByID)
        }

        for record in document.sessions {
            insertSession(record, exercisesByID: exercisesByID)
        }

        if let settings = document.settings {
            let model = UserSettingsModel(
                uuid: settings.uuid,
                weekStartsOnMonday: settings.weekStartsOnMonday,
                weeklyTargetsRaw: settings.weeklyTargetsRaw,
                healthKitEnabled: settings.healthKitEnabled,
                defaultRestSeconds: settings.defaultRestSeconds,
                schemaSeedVersion: settings.schemaSeedVersion
            )
            modelContext.insert(model)
        }
    }

    private func insertProgram(_ record: BackupDocument.ProgramRecord, exercisesByID: [UUID: ExerciseModel]) throws {
        let template = record.template
        let program = ProgramModel(
            uuid: template.id,
            name: template.name,
            isActive: template.isActive,
            createdAt: record.createdAt
        )
        modelContext.insert(program)
        program.goalRaw = template.effectiveGoal.rawValue
        program.summary = template.summary

        for day in template.days {
            let dayModel = ProgramDayModel(uuid: day.id, name: day.name, order: day.order)
            modelContext.insert(dayModel)
            program.days.append(dayModel)

            for target in day.exercises {
                // `validate()` já garantiu; a checagem repetida protege um documento não validado
                // (o retrato do store usado na restauração).
                guard let exercise = exercisesByID[target.exerciseID] else {
                    throw MappingError.missingExercise(programExerciseUUID: target.id)
                }
                let programExercise = ProgramExerciseModel(
                    uuid: target.id,
                    order: target.order,
                    sets: target.sets,
                    repMin: target.repMin,
                    repMax: target.repMax,
                    targetRIR: target.targetRIR,
                    restSeconds: target.restSeconds,
                    startingLoad: target.startingLoad
                )
                modelContext.insert(programExercise)
                programExercise.exercise = exercise
                dayModel.exercises.append(programExercise)
            }
        }
    }

    private func insertSession(_ record: BackupDocument.SessionRecord, exercisesByID: [UUID: ExerciseModel]) {
        let session = WorkoutSessionModel(
            uuid: record.uuid,
            programDayUUID: record.programDayUUID,
            programDayName: record.programDayName,
            statusRaw: record.statusRaw,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            notes: record.notes,
            hkWorkoutUUID: record.hkWorkoutUUID,
            avgHeartRate: record.avgHeartRate,
            maxHeartRate: record.maxHeartRate,
            isDeload: record.isDeload,
            sourceRaw: record.sourceRaw
        )
        modelContext.insert(session)

        for exerciseRecord in record.exercises {
            let sessionExercise = SessionExerciseModel(
                uuid: exerciseRecord.uuid,
                order: exerciseRecord.order,
                exerciseUUID: exerciseRecord.exerciseUUID,
                exerciseName: exerciseRecord.exerciseName,
                prescribedLoad: exerciseRecord.prescribedLoad,
                prescribedSets: exerciseRecord.prescribedSets,
                prescribedRepMin: exerciseRecord.prescribedRepMin,
                prescribedRepMax: exerciseRecord.prescribedRepMax,
                prescribedRIR: exerciseRecord.prescribedRIR,
                restSeconds: exerciseRecord.restSeconds,
                noteRaw: exerciseRecord.noteRaw,
                wasSkipped: exerciseRecord.wasSkipped,
                substitutedFromUUID: exerciseRecord.substitutedFromUUID
            )
            modelContext.insert(sessionExercise)
            sessionExercise.prescribedTargetReps = exerciseRecord.prescribedTargetReps
            // Só navegação (`nullify`); `nil` quando o snapshot aponta para fora do catálogo,
            // exatamente como o `SessionCoordinator` grava nesse caso.
            sessionExercise.exercise = exercisesByID[exerciseRecord.exerciseUUID]
            session.exercises.append(sessionExercise)

            for setRecord in exerciseRecord.sets {
                let setLog = SetLogModel(
                    uuid: setRecord.uuid,
                    index: setRecord.index,
                    load: setRecord.load,
                    reps: setRecord.reps,
                    rir: setRecord.rir,
                    isWarmup: setRecord.isWarmup,
                    completedAt: setRecord.completedAt,
                    sourceRaw: setRecord.sourceRaw,
                    updatedAt: setRecord.updatedAt
                )
                modelContext.insert(setLog)
                sessionExercise.sets.append(setLog)
            }
        }
    }

    /// ARCHITECTURE §12: "valida contagens". Pega um upsert silencioso ou relação perdida que o
    /// `save()` não acusa; a divergência dispara a restauração do retrato.
    private func verifyCounts(matching document: BackupDocument) throws {
        let days = document.programs.reduce(0) { $0 + $1.template.days.count }
        let targets = document.programs.reduce(0) { total, program in
            total + program.template.days.reduce(0) { $0 + $1.exercises.count }
        }
        let sessionExercises = document.sessions.reduce(0) { $0 + $1.exercises.count }

        let storedExercises = try modelContext.fetchCount(FetchDescriptor<ExerciseModel>())
        let storedPrograms = try modelContext.fetchCount(FetchDescriptor<ProgramModel>())
        let storedDays = try modelContext.fetchCount(FetchDescriptor<ProgramDayModel>())
        let storedTargets = try modelContext.fetchCount(FetchDescriptor<ProgramExerciseModel>())
        let storedSessions = try modelContext.fetchCount(FetchDescriptor<WorkoutSessionModel>())
        let storedSessionExercises = try modelContext.fetchCount(FetchDescriptor<SessionExerciseModel>())
        let storedSets = try modelContext.fetchCount(FetchDescriptor<SetLogModel>())
        let storedSettings = try modelContext.fetchCount(FetchDescriptor<UserSettingsModel>())

        let checks: [(name: String, expected: Int, actual: Int)] = [
            ("exercícios", document.exercises.count, storedExercises),
            ("programas", document.programs.count, storedPrograms),
            ("dias", days, storedDays),
            ("exercícios de programa", targets, storedTargets),
            ("sessões", document.sessions.count, storedSessions),
            ("exercícios de sessão", sessionExercises, storedSessionExercises),
            ("séries", document.setCount, storedSets),
            ("ajustes", document.settings == nil ? 0 : 1, storedSettings),
        ]
        for check in checks where check.expected != check.actual {
            throw BackupError.referentialIntegrity(
                "Após importar, \(check.name): \(check.actual) no banco, \(check.expected) no arquivo."
            )
        }
    }

    /// Volta ao retrato tirado antes da importação. Apaga primeiro porque a falha pode ter
    /// acontecido depois do `save()` da fase 2 (contagem divergente).
    private func restore(_ previous: BackupDocument?) {
        guard let previous else {
            logger.fault("Importação falhou sem retrato para restaurar; o store pode ter ficado vazio.")
            return
        }
        do {
            try deleteAllModels()
            try modelContext.save()
            try insert(previous)
            try modelContext.save()
            logger.info("Store restaurado ao estado anterior à importação.")
        } catch {
            modelContext.rollback()
            logger.fault("Falha ao restaurar o store após importação: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Utilitários

    /// "0.1.0 (1)" a partir do Info.plist.
    static func bundleAppVersion(_ bundle: Bundle) -> String {
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static func zeroPadded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
