import Foundation
import Observation
import os
import TrainerCore

/// O diálogo do app com o usuário (SPEC §7.11: C1–C3 e C5–C8; contrato V2-FINAL §2.3). A C4 saiu na
/// 2.5 (SPEC §7.18 L4): o app não lê nem avisa a validade da instalação.
///
/// Monta o `CoachInput` com o planejador, os programas, o log e os ajustes, pede o feed ao
/// `CoachFeedBuilder` (TrainerCore, função pura) e aplica as respostas: grava cada uma no log e
/// executa o efeito da ação. Nunca toca o `ModelContext` (AGENTS R4): programa só pelo
/// `ProgramRepositoring`, semana leve só pelo `SessionPlanning`. O relógio chega por `now`
/// (AGENTS R3).
///
/// Uso pelo integrador:
/// - `refresh(healthSuggestions:recovery:allowsHighlight:)` ao abrir e ao voltar ao app (com
///   destaque) e depois de mudanças na tela (sem destaque);
/// - `messages` no `CoachFeedSection`, `highlight` no `CoachHighlightSheet` com
///   `.sheet(item: $coach.highlight, onDismiss: { coach.highlightDidDismiss() })`;
/// - `handle(_:on:)` em toda resposta; `onBackupRequested`, `onStartRequested`,
///   `onProgressRequested` e `onChooseProgramRequested` para navegar;
/// - `errorMessage` num `.alert` (ou `isPresentingError`).
@Observable
@MainActor
final class CoachService {
    /// Chaves de `UserDefaults` (contrato V2-FINAL §2: strings exatas, compartilhadas).
    enum DefaultsKey {
        /// Double (`timeIntervalSince1970`), gravada pelo Ajustes depois de exportar backup.
        static let lastBackupAt = "lastBackupAt"
        /// Double: desde quando o status da semana leve é `.pending` (período do id do C1).
        static let pendingDeloadSince = "coachPendingDeloadSince"
        /// String (`DeloadTrigger.rawValue`) do pendente acima; só o `CoachService` usa, para
        /// saber quando um pendente automático virou pedido manual.
        static let pendingDeloadTrigger = "coachPendingDeloadTrigger"
        /// String (`UUID`) do programa sobre o qual a última revisão rodou; só o `CoachService`
        /// usa, para tirar do feed as sugestões de um programa que deixou de ser o ativo.
        static let lastReviewProgramID = "coachLastReviewProgramID"
        /// Date: o primeiro "Feito" do C8 que gravou um registro nas atividades fora do app (2.4). Só as
        /// marcas do log de antes dele valem 1 nas Metas (SPEC §7.16 W2.6); as de depois já existem como
        /// registro, e apagar o registro desfaz a vez.
        static let longevityEntriesSince = "coachLongevityEntriesSince"
    }

    /// SPEC §7.11 C5: dias de calendário sem sessão a partir dos quais o próximo dia entra na
    /// mensagem (o mesmo limiar do `CoachFeedBuilder`).
    nonisolated static let comebackDays = 6

    // MARK: - Estado publicado

    /// O feed de agora, o mais importante primeiro (ordem do `CoachFeedBuilder`).
    private(set) var messages: [CoachMessage] = []
    /// Mensagem para o destaque na abertura (SPEC §7.11: "se houver algo novo e importante"):
    /// a primeira do feed com `highlightsOnLaunch` que ainda não foi destacada neste processo.
    /// Settable para o `.sheet(item:)`; fechar a folha sem responder deixa a mensagem no feed.
    var highlight: CoachMessage?
    /// Frase do que "Aplicar" vai mudar, por `CoachMessage.id` (só C2); ver `applySummary(for:)`.
    private(set) var applyDetails: [String: String] = [:]
    /// Mensagem pt-BR para o `.alert`; a view zera ao fechar.
    var errorMessage: String?

    // MARK: - Navegação (fechamentos que o integrador fornece)

    /// C7 "Fazer backup".
    @ObservationIgnored var onBackupRequested: (() -> Void)?
    /// C5 "Começar".
    @ObservationIgnored var onStartRequested: (() -> Void)?
    /// C6 "Ver evolução" do exercício (`ExerciseDefinition.id`).
    @ObservationIgnored var onProgressRequested: ((UUID) -> Void)?
    /// C2 "Trocar de programa" sem outro programa do mesmo objetivo: a pessoa escolhe na aba
    /// Programa.
    @ObservationIgnored var onChooseProgramRequested: (() -> Void)?

    /// Fila das notificações, encadeada para manter a ordem. Desde a 2.5 só leva o cancelamento do
    /// aviso antigo (SPEC §7.18 L4; `CoachService+LegacyReminder`). Os testes aguardam
    /// `pendingWork?.value` em vez de dormir (AGENTS §7).
    @ObservationIgnored private(set) var pendingWork: Task<Void, Never>?

    // MARK: - Dependências

    let planner: any SessionPlanning
    let programs: any ProgramRepositoring
    let logStore: any CoachLogStoring
    let notifications: any NotificationScheduling
    let now: () -> Date
    let calendar: Calendar
    let defaults: UserDefaults
    /// Medida de cada exercício pelo `slug` (SPEC RF-43): o C6 só fala de exercícios medidos em
    /// repetições. `.empty` mede tudo em repetições.
    let traits: ExerciseTraitsCatalog
    /// As atividades fora do app (SPEC §7.17 X6): o "Feito" do C8 grava ali um registro de equilíbrio ou
    /// de mobilidade, para as Metas contarem as vezes.
    let activities: any OutsideActivityStoring

    // MARK: - Estado interno (usado pelas extensões)

    @ObservationIgnored var lastHealthSuggestions: [HealthSuggestion] = []
    @ObservationIgnored var lastRecovery: RecoveryContext = .unknown
    /// Relatório da revisão corrente (contrato: guardado até a próxima revisão).
    @ObservationIgnored var review: ReviewReport?
    @ObservationIgnored var didLoadReview = false
    /// Exercício de cada alvo do programa ativo (`ExerciseTarget.id`), da última leitura.
    @ObservationIgnored var targetExercises: [UUID: ExerciseDefinition] = [:]
    /// Ids já destacados neste processo: cada mensagem ganha no máximo um destaque.
    @ObservationIgnored var presentedHighlightIDs: Set<String> = []
    /// Navegação pedida a partir do destaque, feita só depois que a folha fecha (duas folhas ao
    /// mesmo tempo não abrem no SwiftUI).
    @ObservationIgnored var deferredFollowUp: FollowUp?

    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "CoachService"
    )

    /// - Parameter activities: o app passa o `LiveOutsideActivityStore` do resto do app; o padrão em
    ///   memória serve aos testes e previews.
    init(
        planner: any SessionPlanning,
        programs: any ProgramRepositoring,
        log: any CoachLogStoring,
        notifications: any NotificationScheduling,
        now: @escaping () -> Date,
        calendar: Calendar,
        defaults: UserDefaults,
        traits: ExerciseTraitsCatalog = .empty,
        activities: any OutsideActivityStoring = FakeOutsideActivityStore()
    ) {
        self.planner = planner
        self.programs = programs
        self.logStore = log
        self.notifications = notifications
        self.now = now
        self.calendar = calendar
        self.defaults = defaults
        self.traits = traits
        self.activities = activities
    }

    /// Ponte para `.alert(isPresented:)`: verdadeiro enquanto há mensagem; atribuir `false` limpa.
    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    // MARK: - Feed

    /// Relê tudo e recalcula o feed e o destaque. Nunca pede permissão de nada (AGENTS §7).
    /// - Parameters:
    ///   - healthSuggestions: `HealthReport.suggestions` de hoje (C3); `[]` sem Saúde.
    ///   - recovery: tendências agregadas para a revisão (SPEC R6); `.unknown` sem dados.
    ///   - allowsHighlight: SPEC §7.11, destaque "na abertura": `true` só na abertura e na volta
    ///     ao primeiro plano. Os outros refreshes (troca de aba, fim da sessão, leitura do Saúde)
    ///     passam `false`: atualizam o feed e mantêm um destaque já escolhido, sem abrir outro.
    func refresh(healthSuggestions: [HealthSuggestion], recovery: RecoveryContext, allowsHighlight: Bool = true) {
        lastHealthSuggestions = healthSuggestions
        lastRecovery = recovery
        rebuild(allowsNewHighlight: allowsHighlight)
        // SPEC §7.18 L4: uma cópia que vem da 2.4 pode ter o aviso antigo agendado; sai uma vez só.
        cancelLegacyExpiryReminderIfNeeded()
    }

    /// O que "Aplicar" vai mudar, para a confirmação (SPEC §7.11: "ações que alteram o programa
    /// pedem confirmação"). `nil` fora do C2.
    func applySummary(for message: CoachMessage) -> String? {
        applyDetails[message.id]
    }

    /// A5 (docs/V21-CONTRACT.md B1): chamar depois de importar um backup, quando o
    /// `BackupImportCleanup` já apagou o `last-review.json`. A revisão guardada em memória valia
    /// para os dados antigos e continuaria no feed até reabrir o app. O `lastReviewAt` fica no log,
    /// então a próxima revisão segue o calendário de sempre.
    func resetAfterImport() {
        review = nil
        didLoadReview = false
        rebuild(allowsNewHighlight: false)
    }

    /// Fecha o destaque sem responder: a mensagem continua no feed da Home.
    func dismissHighlight() {
        highlight = nil
    }

    /// Chamar no `onDismiss` do `.sheet` do destaque: faz a navegação que uma resposta dada na
    /// folha pediu (ex.: o "Começar" do C5 abre a sessão depois que o destaque fecha).
    func highlightDidDismiss() {
        highlight = nil
        guard let followUp = deferredFollowUp else {
            return
        }
        deferredFollowUp = nil
        perform(followUp)
    }

    // MARK: - Respostas

    /// Aplica o efeito de `action` e grava a resposta no log (SPEC §7.11). Se o efeito falha,
    /// nada é gravado, a mensagem fica no feed e o motivo vai para `errorMessage`.
    ///
    /// - `apply` (C2): muda o programa conforme a sugestão (a confirmação é da view);
    /// - `keepNormal` (C1): `SessionPlanning.dismissDeload`;
    /// - `done` (C8): a própria resposta no log é a marca da semana; desde a 2.4, também grava um
    ///   registro de 10 min nas atividades fora do app (SPEC §7.17 X6);
    /// - `backupNow`, `start`, `seeProgress`: navegação pelos fechamentos;
    /// - `howToRenew` (C4, removida na 2.5, SPEC §7.18 L4): nunca é oferecida; se chegar, só vai
    ///   para o log.
    func handle(_ action: CoachAction, on message: CoachMessage) {
        let now = self.now()
        let wasHighlight = highlight?.id == message.id
        if wasHighlight {
            highlight = nil
        }

        let followUp: FollowUp?
        do {
            followUp = try performEffect(of: action, on: message, now: now)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Ação \(action.rawValue, privacy: .public) em \(message.id, privacy: .public) falhou: \(reason, privacy: .public)")
            errorMessage = Self.errorText(for: error)
            return
        }

        var log = logStore.load()
        log.record(message, action: action, at: now)
        var didSaveLog = true
        do {
            try logStore.save(log)
        } catch {
            didSaveLog = false
            let reason = String(describing: error)
            Self.logger.error("Resposta a \(message.id, privacy: .public) não foi gravada: \(reason, privacy: .public)")
            errorMessage = "Não foi possível guardar sua resposta; esta mensagem pode aparecer de novo."
        }

        if let followUp {
            if wasHighlight {
                deferredFollowUp = followUp
            } else {
                perform(followUp)
            }
        }

        rebuild(allowsNewHighlight: false)
        if !didSaveLog {
            // Sem o log gravado o feed recalculado ainda traria a mensagem; nesta tela ela some.
            messages.removeAll { $0.id == message.id }
        }
    }

    // MARK: - Internos

    /// Recalcula o feed com o log e os ajustes atuais.
    func rebuild(allowsNewHighlight: Bool) {
        let now = self.now()
        var log = logStore.load()
        let input = makeInput(log: &log, now: now)
        messages = CoachFeedBuilder.feed(input: input, log: log, now: now, calendar: calendar)
        applyDetails = makeApplyDetails(for: messages)
        updateHighlight(allowsNew: allowsNewHighlight)
    }

    /// Mantém o destaque aberto enquanto a mensagem existir; um novo só quando permitido (o
    /// `refresh` da abertura, não a resposta a outra mensagem, para não encadear folhas).
    private func updateHighlight(allowsNew: Bool) {
        if let current = highlight, let fresh = messages.first(where: { $0.id == current.id }) {
            if fresh != current {
                highlight = fresh
            }
            return
        }
        highlight = nil
        guard allowsNew,
              let next = messages.first(where: { $0.highlightsOnLaunch && !presentedHighlightIDs.contains($0.id) })
        else {
            return
        }
        presentedHighlightIDs.insert(next.id)
        highlight = next
    }

    /// Enfileira um trabalho assíncrono depois do anterior.
    func enqueue(_ work: @escaping @Sendable @MainActor () async -> Void) {
        let previous = pendingWork
        pendingWork = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
