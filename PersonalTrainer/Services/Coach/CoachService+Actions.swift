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
        case .done:
            // C8: a resposta no log é a marca da semana; desde a 2.4, o bloco feito também vira um
            // registro nas atividades fora do app (SPEC §7.17 X6).
            if message.rule == .longevity {
                recordLongevityActivity(for: message, now: now)
            }
            return nil
        case .ok, .notNow, .neverAgain, .understood, .remindTomorrow, .later, .skip:
            // Só o log: ele esconde a mensagem.
            return nil
        }
    }

    /// SPEC §7.17 X6: o "Feito" do C8 grava 10 min leves de equilíbrio ou de mobilidade
    /// (`OutsideActivities.longevityEntry`), para as Metas da semana contarem as vezes (W2.6). Uma falha
    /// só vai para o log: a marca do C8 é a resposta no log do diálogo, que continua sendo gravada.
    func recordLongevityActivity(for message: CoachMessage, now: Date) {
        guard let entry = OutsideActivities.longevityEntry(key: message.itemKey, at: now) else {
            Self.logger.error("C8 sem registro de atividade: bloco desconhecido \(message.itemKey, privacy: .public).")
            return
        }
        var log = activities.load()
        log.entries.append(entry)
        do {
            try activities.save(log)
            // W2.6: daqui em diante, o "Feito" conta pelo registro, não pela marca do log.
            if defaults.object(forKey: DefaultsKey.longevityEntriesSince) == nil {
                defaults.set(now, forKey: DefaultsKey.longevityEntriesSince)
            }
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Registro do C8 não foi gravado nas atividades: \(reason, privacy: .public)")
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
    /// - switchProgram: na Hipertrofia, `activate` do próximo formato do seed (as cargas ficam, o
    ///   histórico é por exercício); sem outro, a pessoa escolhe na folha "Seu objetivo" (RF-45);
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
            try switchPrincipal(to: candidate.program.id)
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

    /// Os 3 formatos da Hipertrofia do seed (`programs.v2.json`), na ordem da folha "Seu objetivo"
    /// (SPEC RF-35, RF-45), com o título leigo. Os mesmos ids e títulos de
    /// `GoalPlanCatalog.hypertrophyFormats`, repetidos aqui porque um serviço não depende de
    /// `Features/` (ARCHITECTURE §3).
    /// Desde a 2.3 (D1), o primeiro é o Equilibrado; o antigo Corpo todo ficou escondido.
    static let hypertrophyFormats: [(id: UUID, title: String)] = [
        (UUID(uuidString: "9FE0818F-1417-4953-B357-43D757054FCC") ?? UUID(), "Equilibrado"),
        (UUID(uuidString: "C7DDB9BA-1897-40D8-BDC8-A14EB6219FDD") ?? UUID(), "Mais pernas e glúteos"),
        (UUID(uuidString: "ADE28A46-680B-4701-A51F-992519A8AD63") ?? UUID(), "Mais tronco e braços"),
    ]

    /// C2 "Experimentar um novo plano" (SPEC RF-45: objetivo = plano). Na Hipertrofia, o
    /// próximo dos 3 formatos do seed depois do ativo (dando a volta; um ativo que não é formato
    /// vai para o primeiro, então o antigo Corpo todo vai para o Equilibrado), só entre os que
    /// existem, têm dias e continuam na Hipertrofia. Nunca um programa escondido pela RF-45 (cópia,
    /// o antigo Corpo todo, o antigo Empurrar/Inferior/Puxar). Nos outros objetivos, `nil`: a
    /// pessoa escolhe na folha "Seu objetivo".
    ///
    /// Com dois planos ativos, o "ativo" é o principal (SPEC §7.15 M1, M2), que é o da Hipertrofia
    /// quando ela está entre os ativos.
    func switchCandidate() throws -> (program: ProgramTemplate, title: String)? {
        let all = try programs.allPrograms()
        guard
            let active = ActivePlanOrder.sorted(all.filter { $0.isActive }).first,
            active.effectiveGoal == .hypertrophy
        else {
            return nil
        }
        let formats = Self.hypertrophyFormats
        let start = formats.firstIndex(where: { $0.id == active.id }).map { $0 + 1 } ?? 0
        for offset in 0..<formats.count {
            let format = formats[(start + offset) % formats.count]
            guard
                format.id != active.id,
                let program = all.first(where: { $0.id == format.id }),
                program.effectiveGoal == .hypertrophy,
                !program.days.isEmpty
            else {
                continue
            }
            return (program: program, title: format.title)
        }
        return nil
    }

    /// Troca o plano principal pelo novo formato (SPEC §7.15 M8). Com um plano só, `activate`: fica só o
    /// novo, como sempre. Com um segundo plano ativo, troca só o principal e mantém o outro: tira o antigo
    /// e acrescenta o novo, nessa ordem (dois do mesmo objetivo não ficam ativos juntos). Se acrescentar
    /// falhar, o antigo volta, para a pessoa não ficar sem ele, e o erro sobe.
    func switchPrincipal(to programID: UUID) throws {
        let actives = try programs.allPrograms().filter { $0.isActive }
        guard actives.count > 1, let principal = ActivePlanOrder.sorted(actives).first else {
            try programs.activate(programID: programID)
            return
        }
        try programs.removeActivePlan(programID: principal.id)
        do {
            try programs.addActivePlan(programID: programID)
        } catch {
            do {
                try programs.addActivePlan(programID: principal.id)
            } catch let restoreError {
                let reason = String(describing: restoreError)
                Self.logger.error("O plano anterior não voltou depois da troca que falhou: \(reason, privacy: .public)")
            }
            throw error
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
            return "\(subject) \(verb) a ter \(setsText) por sessão. Repetições e descanso continuam iguais."
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
                return "O plano passa a ser \(candidate.title). As cargas de cada exercício são mantidas."
            }
            return "Você escolhe o novo plano em seguida. As cargas de cada exercício são mantidas."
        case .deload:
            return "As próximas sessões, uma de cada dia do programa, ficam mais leves: cerca de 60% das séries, com cargas 15% menores."
        case .reduceDays:
            return "Nada muda sozinho: para treinar em menos dias, ajuste o plano na aba Plano."
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
        return "Não foi possível aplicar a mudança agora. Tente de novo ou ajuste pela aba Plano."
    }
}
