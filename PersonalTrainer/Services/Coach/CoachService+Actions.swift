import Foundation
import TrainerCore

/// Efeitos das respostas do diálogo (SPEC §7.11; contrato V2-FINAL §2.3). Programa só pelo
/// `ProgramRepositoring` e semana leve só pelo `SessionPlanning` (AGENTS R4).
extension CoachService {
    /// Navegação pedida por uma resposta; quem navega é o integrador, pelos fechamentos.
    enum FollowUp: Equatable {
        case backup
        case renewalHelp
        case start
        case progress(UUID)
        case chooseProgram
    }

    /// Executa o efeito de `action`; lança se nada pôde ser aplicado.
    func performEffect(of action: CoachAction, on message: CoachMessage, now: Date) throws -> FollowUp? {
        switch action {
        case .apply:
            return try applySuggestion(of: message, now: now)
        case .keepNormal:
            // Contrato: `dismissDeload` grava `dismissedAt` e limpa o pedido manual.
            try planner.dismissDeload(now: now)
            clearPendingDeload()
            return nil
        case .howToRenew:
            // SPEC §7.11 C4: a permissão do aviso da véspera é pedida nesta ação, se a pessoa
            // o ligou (AGENTS §7: nunca no launch).
            if isExpiryReminderEnabled {
                syncExpiryReminder(now: now, requestsAuthorization: true)
            }
            return .renewalHelp
        case .backupNow:
            return .backup
        case .start:
            return .start
        case .seeProgress:
            guard let text = message.suggestionID, let exerciseID = UUID(uuidString: text) else {
                return nil
            }
            return .progress(exerciseID)
        case .ok, .notNow, .neverAgain, .understood, .remindTomorrow, .later, .done, .skip:
            // Só o log: ele esconde a mensagem, e no C8 "Feito" é a própria marca da semana.
            return nil
        }
    }

    func perform(_ followUp: FollowUp) {
        switch followUp {
        case .backup:
            onBackupRequested?()
        case .renewalHelp:
            onRenewalHelpRequested?()
        case .start:
            onStartRequested?()
        case .progress(let exerciseID):
            onProgressRequested?(exerciseID)
        case .chooseProgram:
            onChooseProgramRequested?()
        }
    }

    // MARK: - C2 Aplicar

    /// Aplica a sugestão da revisão (SPEC §7.8 R5):
    /// - addSets/removeSets: `updateTarget` com `proposedSets` (absoluto: aplicar duas vezes não
    ///   soma), mantendo faixa, RIR, descanso e carga inicial;
    /// - changeRepRange: `updateTarget` com a faixa proposta;
    /// - swapExercise: `replaceExercise` pelo primeiro de `SessionPlanning.programSubstitutes`
    ///   que ainda não está no dia (`swapReplacements`);
    /// - switchProgram: `activate` do próximo programa com o mesmo objetivo (as cargas ficam, o
    ///   histórico é por exercício); sem outro, a pessoa escolhe na aba Programa;
    /// - deload: `SessionPlanning.requestDeload`;
    /// - reduceDays: só informa (contrato), nada muda.
    func applySuggestion(of message: CoachMessage, now: Date) throws -> FollowUp? {
        guard message.rule == .review else {
            return nil
        }
        guard let suggestionID = message.suggestionID,
              let suggestion = review?.suggestions.first(where: { $0.id == suggestionID })
        else {
            throw CoachServiceError.suggestionNotFound
        }

        switch suggestion.kind {
        case .addSets, .removeSets:
            guard let sets = suggestion.proposedSets else {
                throw CoachServiceError.suggestionNotFound
            }
            let targets = try activeTargets(suggestion.targetIDs)
            for target in targets {
                try programs.updateTarget(
                    id: target.id,
                    sets: sets,
                    repMin: target.repMin,
                    repMax: target.repMax,
                    targetRIR: target.targetRIR,
                    restSeconds: target.restSeconds,
                    startingLoad: target.startingLoad
                )
            }
            return nil

        case .changeRepRange:
            guard let range = suggestion.proposedRepRange else {
                throw CoachServiceError.suggestionNotFound
            }
            let targets = try activeTargets(suggestion.targetIDs)
            for target in targets {
                try programs.updateTarget(
                    id: target.id,
                    sets: target.sets,
                    repMin: range.lowerBound,
                    repMax: range.upperBound,
                    targetRIR: target.targetRIR,
                    restSeconds: target.restSeconds,
                    startingLoad: target.startingLoad
                )
            }
            return nil

        case .swapExercise:
            // Todos os substitutos antes de gravar: sem um deles, nada muda.
            let replacements = try swapReplacements(for: suggestion.targetIDs)
            for replacement in replacements {
                try programs.replaceExercise(targetID: replacement.targetID, with: replacement.substitute.id)
            }
            return nil

        case .switchProgram:
            guard let candidate = try switchCandidate() else {
                return .chooseProgram
            }
            try programs.activate(programID: candidate.id)
            return nil

        case .deload:
            try planner.requestDeload(now: now)
            markPendingDeload(since: now, trigger: .manual)
            return nil

        case .reduceDays:
            return nil
        }
    }

    /// Os alvos do programa ativo com esses ids. Lança `suggestionOutdated` se algum sumiu: a
    /// revisão foi feita sobre outra versão do programa, e aplicar só uma parte confundiria.
    func activeTargets(_ ids: [UUID]) throws -> [ExerciseTarget] {
        let targets = try programs.allPrograms()
            .filter { $0.isActive }
            .flatMap { $0.days }
            .flatMap { $0.exercises }
        var found: [ExerciseTarget] = []
        for id in ids {
            guard let target = targets.first(where: { $0.id == id }) else {
                throw CoachServiceError.suggestionOutdated
            }
            found.append(target)
        }
        guard !found.isEmpty else {
            throw CoachServiceError.suggestionOutdated
        }
        return found
    }

    /// O substituto de cada alvo de uma troca (RF-34): o primeiro candidato de
    /// `SessionPlanning.programSubstitutes` que não está no dia do alvo nem foi escolhido para
    /// outro alvo do mesmo dia, como no editor manual; assim o dia não fica com o mesmo exercício
    /// duas vezes. Lança `suggestionOutdated` se um alvo sumiu do programa ativo e `noSubstitute`
    /// se não sobra candidato.
    ///
    /// `programSubstitutes`, e não `substitutes`: a troca muda o programa, e o modo casa só vale
    /// para a sessão (SPEC RF-42: "o programa não muda"). Com ele ligado, `substitutes` daria só
    /// exercícios de casa, que ficariam no programa depois de desligar a chave.
    func swapReplacements(for targetIDs: [UUID]) throws -> [(targetID: UUID, substitute: ExerciseDefinition)] {
        let days = try programs.allPrograms()
            .filter { $0.isActive }
            .flatMap { $0.days }
        var takenByDay: [UUID: Set<UUID>] = [:]
        var replacements: [(targetID: UUID, substitute: ExerciseDefinition)] = []
        for targetID in targetIDs {
            guard let day = days.first(where: { candidate in candidate.exercises.contains { $0.id == targetID } }),
                  let target = day.exercises.first(where: { $0.id == targetID })
            else {
                throw CoachServiceError.suggestionOutdated
            }
            var taken = takenByDay[day.id] ?? Set(day.exercises.map { $0.exerciseID })
            // O próprio exercício já sai da lista; com um candidato a mais do que os exercícios
            // do dia, sobra ao menos um fora dele quando o catálogo tem.
            let candidates = try planner.programSubstitutes(for: target.exerciseID, limit: taken.count + 1)
            guard let substitute = candidates.first(where: { !taken.contains($0.id) }) else {
                throw CoachServiceError.noSubstitute
            }
            taken.insert(substitute.id)
            takenByDay[day.id] = taken
            replacements.append((targetID: targetID, substitute: substitute))
        }
        guard !replacements.isEmpty else {
            throw CoachServiceError.suggestionOutdated
        }
        return replacements
    }

    /// C2 "Experimentar um novo programa": o primeiro programa inativo com o mesmo objetivo do
    /// ativo e com dias, na ordem de `allPrograms` (ativo primeiro, depois por nome), para a
    /// escolha ser previsível. `nil` quando não há outro.
    func switchCandidate() throws -> ProgramTemplate? {
        let all = try programs.allPrograms()
        guard let active = all.first(where: { $0.isActive }) else {
            return nil
        }
        return all.first { program in
            !program.isActive && program.effectiveGoal == active.effectiveGoal && !program.days.isEmpty
        }
    }

    // MARK: - Texto da confirmação

    /// Uma frase por mensagem do C2 com o que "Aplicar" muda, para a confirmação da view.
    func makeApplyDetails(for messages: [CoachMessage]) -> [String: String] {
        var details: [String: String] = [:]
        for message in messages where message.rule == .review {
            guard let suggestionID = message.suggestionID,
                  let suggestion = review?.suggestions.first(where: { $0.id == suggestionID }),
                  let text = applyDetail(for: suggestion)
            else {
                continue
            }
            details[message.id] = text
        }
        return details
    }

    func applyDetail(for suggestion: ProgramSuggestion) -> String? {
        let names = suggestion.targetIDs.compactMap { targetExercises[$0]?.name }
        let subject = Self.joinedNames(names)
        let verb = names.count > 1 ? "passam" : "passa"
        switch suggestion.kind {
        case .addSets, .removeSets:
            guard let sets = suggestion.proposedSets, !subject.isEmpty else {
                return nil
            }
            let setsText = sets == 1 ? "1 série" : "\(sets) séries"
            return "\(subject) \(verb) a ter \(setsText) por sessão. Faixa, RIR e descanso continuam iguais."
        case .changeRepRange:
            guard let range = suggestion.proposedRepRange, !subject.isEmpty else {
                return nil
            }
            return "\(subject) \(verb) para a faixa de \(range.lowerBound) a \(range.upperBound) repetições."
        case .swapExercise:
            // A mesma escolha de "Aplicar", para a confirmação dizer o que vai mudar.
            let replacements: [(targetID: UUID, substitute: ExerciseDefinition)]
            do {
                replacements = try swapReplacements(for: suggestion.targetIDs)
            } catch CoachServiceError.noSubstitute {
                return "Não há um exercício parecido no catálogo para a troca."
            } catch {
                return nil
            }
            let pairs = replacements.compactMap { replacement -> String? in
                guard let exercise = targetExercises[replacement.targetID] else {
                    return nil
                }
                return "\(exercise.name) dá lugar a \(replacement.substitute.name)"
            }
            guard !pairs.isEmpty else {
                return nil
            }
            return Self.joinedNames(pairs) + ". Séries, faixa e descanso continuam os mesmos."
        case .switchProgram:
            if let candidate = try? switchCandidate() {
                return "O programa ativo passa a ser \(candidate.name). As cargas de cada exercício são mantidas."
            }
            return "Você escolhe o novo programa na aba Programa. As cargas de cada exercício são mantidas."
        case .deload:
            return "As próximas sessões, uma de cada dia do programa, ficam mais leves: cerca de 60% das séries, com cargas 15% menores."
        case .reduceDays:
            return "Nada muda sozinho: para treinar em menos dias, ajuste o programa na aba Programa."
        }
    }

    /// "A", "A e B", "A, B e C".
    static func joinedNames(_ names: [String]) -> String {
        guard let last = names.last else {
            return ""
        }
        guard names.count > 1 else {
            return last
        }
        return names.dropLast().joined(separator: ", ") + " e " + last
    }

    // MARK: - Erros

    static func errorText(for error: any Error) -> String {
        if let coachError = error as? CoachServiceError {
            switch coachError {
            case .suggestionNotFound, .suggestionOutdated:
                return "Esta sugestão não vale mais para o programa atual; nada foi alterado."
            case .noSubstitute:
                return "Não há um exercício parecido no catálogo para a troca; nada foi alterado."
            }
        }
        return "Não foi possível aplicar a mudança agora. Tente de novo ou ajuste pela aba Programa."
    }
}
