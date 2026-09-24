import Foundation
import SwiftData
import TrainerCore

/// Implementação de `ProgramRepositoring` sobre SwiftData (T2.6, T2.20, T2.12; AGENTS R4): depois
/// do seed, o único lugar do app que altera `ProgramModel`, `ProgramDayModel` e
/// `ProgramExerciseModel`.
///
/// - Cada mutação acha as entidades, valida e só então altera o store; `save()` no fim de cada
///   operação. Se o `save()` falhar, `rollback()` descarta o que ficou pendente para o contexto não
///   guardar meio programa editado.
/// - Leituras devolvem DTOs de `TrainerCore`; nenhum `@Model` sai daqui.
/// - `@MainActor` porque `@Model` não é `Sendable` (ARCHITECTURE §10).
/// - Sessões nunca são tocadas: elas guardam snapshots da prescrição (ARCHITECTURE §5, decisão 3),
///   então editar o programa só muda as próximas prescrições (CA2-4).
@MainActor
final class ProgramRepository: ProgramRepositoring {
    private let modelContext: ModelContext

    // Limites de `updateTarget` (contrato em `ProgramRepositoring`).
    private static let setsRange = 1...10
    private static let maxReps = 50
    private static let rirRange = 0...5
    private static let restRange = 15...600

    /// Ordenação por nome independente do idioma do aparelho (SPEC P11: mesma entrada, mesma saída).
    private static let sortLocale = Locale(identifier: "pt_BR")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Leitura

    func allPrograms() throws -> [ProgramTemplate] {
        let models = try modelContext.fetch(FetchDescriptor<ProgramModel>())
        return try models
            .map { try template(from: $0) }
            .sorted { Self.listOrder($0, $1) }
    }

    func program(id: UUID) throws -> ProgramTemplate? {
        guard let model = try fetchProgram(uuid: id) else {
            return nil
        }
        return try template(from: model)
    }

    // MARK: - Programa

    func activate(programID: UUID) throws {
        guard try fetchProgram(uuid: programID) != nil else {
            throw ProgramRepositoryError.programNotFound(programID)
        }

        // Percorre todos, não só os ativos: garante exatamente um ativo mesmo que o store tenha
        // chegado aqui com dois. A rotação recomeça em D1 sozinha (SPEC S2: o dia da última sessão
        // não existe no programa novo).
        for program in try modelContext.fetch(FetchDescriptor<ProgramModel>()) {
            let shouldBeActive = program.uuid == programID
            if program.isActive != shouldBeActive {
                program.isActive = shouldBeActive
            }
        }
        try save()
    }

    func rename(programID: UUID, to name: String) throws {
        guard let program = try fetchProgram(uuid: programID) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        program.name = try Self.validatedName(name)
        try save()
    }

    func setGoal(programID: UUID, goal: ProgramGoal, applyDefaults: Bool) throws {
        guard let program = try fetchProgram(uuid: programID) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }

        program.goalRaw = goal.rawValue

        // SPEC §7.9: o objetivo define faixa de reps, RIR e descanso. Séries e carga inicial ficam
        // como estão: o contrato de `setGoal` só reescreve esses três parâmetros. Carregadas e
        // isometrias de pescoço contam passos/segundos no campo de reps: faixa e descanso delas
        // ficam como estão, só o RIR segue o objetivo.
        if applyDefaults {
            let defaults = goal.defaults
            for day in program.days {
                for target in day.exercises {
                    target.targetRIR = defaults.targetRIR
                    guard Self.stepsOrSecondsRange(target.exercise) == nil else {
                        continue
                    }
                    let isCompound = Self.isCompound(target.exercise)
                    let repRange = isCompound ? defaults.compoundRepRange : defaults.isolationRepRange
                    target.repMin = repRange.lowerBound
                    target.repMax = repRange.upperBound
                    target.restSeconds = isCompound ? defaults.compoundRestSeconds : defaults.isolationRestSeconds
                }
            }
        }
        try save()
    }

    func duplicate(programID: UUID, name: String, now: Date) throws -> UUID {
        guard let source = try fetchProgram(uuid: programID) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        let copyName = try Self.validatedName(name)

        // Cópia inativa com UUIDs novos em todos os níveis: o original e a cópia evoluem separados.
        // `createdAt` vem de quem chama (SPEC P11). Inserir antes de ligar relações é o caminho
        // mais previsível do SwiftData (mesmo padrão do `SessionCoordinator`).
        let copy = ProgramModel(uuid: UUID(), name: copyName, isActive: false, createdAt: now)
        copy.goalRaw = source.goalRaw
        copy.summary = source.summary
        modelContext.insert(copy)

        for sourceDay in source.days.sorted(by: { Self.dayOrder($0, $1) }) {
            let day = ProgramDayModel(uuid: UUID(), name: sourceDay.name, order: sourceDay.order)
            modelContext.insert(day)
            copy.days.append(day)

            for sourceTarget in sourceDay.exercises.sorted(by: { Self.targetOrder($0, $1) }) {
                let target = ProgramExerciseModel(
                    uuid: UUID(),
                    order: sourceTarget.order,
                    sets: sourceTarget.sets,
                    repMin: sourceTarget.repMin,
                    repMax: sourceTarget.repMax,
                    targetRIR: sourceTarget.targetRIR,
                    restSeconds: sourceTarget.restSeconds,
                    startingLoad: sourceTarget.startingLoad
                )
                modelContext.insert(target)
                // O catálogo é compartilhado: a cópia aponta para os mesmos `ExerciseModel`.
                target.exercise = sourceTarget.exercise
                day.exercises.append(target)
            }
        }

        try save()
        return copy.uuid
    }

    func delete(programID: UUID) throws {
        guard let program = try fetchProgram(uuid: programID) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard !program.isActive else {
            throw ProgramRepositoryError.cannotDeleteActive
        }

        // Dias e alvos saem em cascata; o catálogo fica (`nullify`, ARCHITECTURE §5) e o histórico
        // não muda, porque sessões guardam cópias, não relações com o programa.
        modelContext.delete(program)
        try save()
    }

    // MARK: - Exercícios do dia (RF-16, RF-33)

    func addExercise(exerciseID: UUID, toDay dayID: UUID) throws -> UUID {
        guard let day = try fetchDay(uuid: dayID) else {
            throw ProgramRepositoryError.dayNotFound(dayID)
        }
        guard let exercise = try fetchExercise(uuid: exerciseID) else {
            throw ProgramRepositoryError.exerciseNotFound(exerciseID)
        }
        guard day.exercises.count < ProgramLimits.maxExercisesPerDay else {
            throw ProgramRepositoryError.tooManyExercises
        }

        // Padrões do objetivo do programa (SPEC §7.9); `goalRaw` desconhecido vale hipertrofia,
        // como `ProgramTemplate.effectiveGoal`.
        let goal = day.program.flatMap { ProgramGoal(rawValue: $0.goalRaw) } ?? .hypertrophy
        let defaults = goal.defaults
        let isCompound = Self.isCompound(exercise)
        // Carregadas e isometrias de pescoço contam passos/segundos, com descanso curto de acessório;
        // os demais usam a faixa do objetivo para compostos ou isolados.
        let repRange: ClosedRange<Int>
        let restSeconds: Int
        if let stepsOrSeconds = Self.stepsOrSecondsRange(exercise) {
            repRange = stepsOrSeconds
            restSeconds = defaults.isolationRestSeconds
        } else {
            repRange = isCompound ? defaults.compoundRepRange : defaults.isolationRepRange
            restSeconds = isCompound ? defaults.compoundRestSeconds : defaults.isolationRestSeconds
        }
        // Depois do maior `order` existente: mantém `order` único no dia sem renumerar os outros.
        let nextOrder = (day.exercises.map { $0.order }.max() ?? -1) + 1

        let target = ProgramExerciseModel(
            uuid: UUID(),
            order: nextOrder,
            sets: defaults.setsPerExercise,
            repMin: repRange.lowerBound,
            repMax: repRange.upperBound,
            targetRIR: defaults.targetRIR,
            restSeconds: restSeconds,
            // Sem carga inicial: o motor calibra na 1ª sessão (SPEC P2).
            startingLoad: nil
        )
        modelContext.insert(target)
        target.exercise = exercise
        day.exercises.append(target)

        try save()
        return target.uuid
    }

    func removeTarget(id: UUID) throws {
        guard let target = try fetchTarget(uuid: id) else {
            throw ProgramRepositoryError.targetNotFound(id)
        }

        if let day = target.day {
            let remaining = day.exercises.filter { $0.uuid != id }
            guard remaining.count >= ProgramLimits.minExercisesPerDay else {
                throw ProgramRepositoryError.tooFewExercises
            }
            // Tira da relação antes de apagar para o array do dia não guardar o alvo apagado até o
            // próximo fetch; depois fecha o buraco em `order` (0…n-1).
            day.exercises.removeAll { $0.uuid == id }
            Self.renumber(remaining)
        }

        modelContext.delete(target)
        try save()
    }

    func moveTarget(id: UUID, toIndex newIndex: Int) throws {
        guard let target = try fetchTarget(uuid: id) else {
            throw ProgramRepositoryError.targetNotFound(id)
        }
        guard let day = target.day else {
            throw ProgramRepositoryError.invalidParameters("Exercício sem dia no programa.")
        }

        var ordered = day.exercises.sorted { Self.targetOrder($0, $1) }
        guard newIndex >= 0, newIndex < ordered.count else {
            throw ProgramRepositoryError.invalidParameters("Posição fora da lista do dia.")
        }
        guard let currentIndex = ordered.firstIndex(where: { $0.uuid == id }) else {
            throw ProgramRepositoryError.targetNotFound(id)
        }

        let moving = ordered.remove(at: currentIndex)
        ordered.insert(moving, at: newIndex)
        for (index, item) in ordered.enumerated() where item.order != index {
            item.order = index
        }
        try save()
    }

    func replaceExercise(targetID: UUID, with exerciseID: UUID) throws {
        guard let target = try fetchTarget(uuid: targetID) else {
            throw ProgramRepositoryError.targetNotFound(targetID)
        }
        guard let exercise = try fetchExercise(uuid: exerciseID) else {
            throw ProgramRepositoryError.exerciseNotFound(exerciseID)
        }

        // RF-34: séries, faixa, RIR e descanso ficam. A carga inicial era do exercício antigo (outro
        // equipamento, outro incremento) e sai: o substituto começa em calibração (SPEC P2).
        target.exercise = exercise
        target.startingLoad = nil
        try save()
    }

    func updateTarget(
        id: UUID,
        sets: Int,
        repMin: Int,
        repMax: Int,
        targetRIR: Int,
        restSeconds: Int,
        startingLoad: Double?
    ) throws {
        guard let target = try fetchTarget(uuid: id) else {
            throw ProgramRepositoryError.targetNotFound(id)
        }

        guard Self.setsRange.contains(sets) else {
            throw ProgramRepositoryError.invalidParameters("As séries devem ficar entre 1 e 10.")
        }
        guard repMin >= 1, repMin < repMax, repMax <= Self.maxReps else {
            throw ProgramRepositoryError.invalidParameters(
                "A faixa de repetições deve ir de 1 a 50, com o mínimo menor que o máximo."
            )
        }
        guard Self.rirRange.contains(targetRIR) else {
            throw ProgramRepositoryError.invalidParameters("O RIR alvo deve ficar entre 0 e 5.")
        }
        guard Self.restRange.contains(restSeconds) else {
            throw ProgramRepositoryError.invalidParameters("O descanso deve ficar entre 15 s e 10 min.")
        }
        if let startingLoad {
            guard startingLoad.isFinite, startingLoad >= 0 else {
                throw ProgramRepositoryError.invalidParameters("A carga inicial não pode ser negativa.")
            }
            guard let increment = target.exercise?.loadIncrement else {
                throw ProgramRepositoryError.invalidParameters("Exercício do programa sem catálogo.")
            }
            // SPEC P8: toda carga prescrita é múltiplo do incremento. `Load.round` devolve o próprio
            // valor quando ele já está na grade (com tolerância de ponto flutuante).
            guard Load.round(startingLoad, toIncrement: increment) == startingLoad else {
                throw ProgramRepositoryError.invalidParameters(
                    "A carga inicial deve ser múltiplo do incremento do exercício."
                )
            }
        }

        target.sets = sets
        target.repMin = repMin
        target.repMax = repMax
        target.targetRIR = targetRIR
        target.restSeconds = restSeconds
        target.startingLoad = startingLoad
        try save()
    }

    // MARK: - Mapeamento

    /// `ProgramMapper` monta dias e alvos ordenados. Objetivo e resumo são lidos aqui direto do
    /// modelo para o DTO sempre carregá-los, qualquer que seja a versão do mapper.
    private func template(from model: ProgramModel) throws -> ProgramTemplate {
        let mapped = try ProgramMapper.template(from: model)
        return ProgramTemplate(
            id: mapped.id,
            name: mapped.name,
            days: mapped.days,
            isActive: mapped.isActive,
            goal: ProgramGoal(rawValue: model.goalRaw),
            summary: model.summary
        )
    }

    // MARK: - Regras auxiliares

    /// Ativo primeiro, depois nome (pt-BR, sem diferenciar maiúsculas); empate pelo id (SPEC P11).
    private static func listOrder(_ lhs: ProgramTemplate, _ rhs: ProgramTemplate) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive
        }
        let byName = lhs.name.compare(rhs.name, options: [.caseInsensitive], locale: sortLocale)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func dayOrder(_ lhs: ProgramDayModel, _ rhs: ProgramDayModel) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.uuid.uuidString < rhs.uuid.uuidString
    }

    private static func targetOrder(_ lhs: ProgramExerciseModel, _ rhs: ProgramExerciseModel) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.uuid.uuidString < rhs.uuid.uuidString
    }

    /// Reatribui `order` 0…n-1 na ordem atual, sem buracos.
    private static func renumber(_ targets: [ProgramExerciseModel]) {
        for (index, target) in targets.sorted(by: { targetOrder($0, $1) }).enumerated() where target.order != index {
            target.order = index
        }
    }

    /// Composto vs. isolado pelo padrão de movimento (SPEC §7.9). Sem padrão (catálogo antigo ou
    /// exercício do usuário sem padrão) conta como isolado, como define o contrato do M2.
    private static func isCompound(_ exercise: ExerciseModel?) -> Bool {
        guard
            let raw = exercise?.movementPatternRaw,
            let pattern = MovementPattern(rawValue: raw)
        else {
            return false
        }
        return pattern.isCompound
    }

    /// Faixa padrão de exercícios que contam passos (carregadas, 20–40) ou segundos (isometria de
    /// pescoço, 10–20) no campo de repetições, como no seed v2. `nil` para os demais, que usam a
    /// faixa de reps do objetivo (SPEC §7.9).
    private static func stepsOrSecondsRange(_ exercise: ExerciseModel?) -> ClosedRange<Int>? {
        guard
            let raw = exercise?.movementPatternRaw,
            let pattern = MovementPattern(rawValue: raw)
        else {
            return nil
        }
        switch pattern {
        case .carry:
            return 20...40
        case .neck:
            return 10...20
        default:
            return nil
        }
    }

    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProgramRepositoryError.invalidParameters("O nome não pode ficar vazio.")
        }
        return trimmed
    }

    // MARK: - Store

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func fetchProgram(uuid: UUID) throws -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(
            predicate: #Predicate<ProgramModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchDay(uuid: UUID) throws -> ProgramDayModel? {
        var descriptor = FetchDescriptor<ProgramDayModel>(
            predicate: #Predicate<ProgramDayModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchTarget(uuid: UUID) throws -> ProgramExerciseModel? {
        var descriptor = FetchDescriptor<ProgramExerciseModel>(
            predicate: #Predicate<ProgramExerciseModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchExercise(uuid: UUID) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
