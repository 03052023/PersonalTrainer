import Foundation
import Observation
import os
import TrainerCore

/// O diálogo do app com o usuário (SPEC §7.11 C1–C8; contrato V2-FINAL §2.3).
///
/// Monta o `CoachInput` com o planejador, os programas, o log e os ajustes, pede o feed ao
/// `CoachFeedBuilder` (TrainerCore, função pura) e aplica as respostas: grava cada uma no log e
/// executa o efeito da ação. Nunca toca o `ModelContext` (AGENTS R4): programa só pelo
/// `ProgramRepositoring`, semana leve só pelo `SessionPlanning`. O relógio chega por `now`
/// (AGENTS R3).
///
/// Uso pelo integrador:
/// - `refresh(healthSuggestions:recovery:)` ao abrir a Home e ao voltar ao app;
/// - `messages` no `CoachFeedSection`, `highlight` no `CoachHighlightSheet` com
///   `.sheet(item: $coach.highlight, onDismiss: { coach.highlightDidDismiss() })`;
/// - `handle(_:on:)` em toda resposta; `onBackupRequested`, `onRenewalHelpRequested`,
///   `onStartRequested`, `onProgressRequested` e `onChooseProgramRequested` para navegar;
/// - `errorMessage` num `.alert` (ou `isPresentingError`).
@Observable
@MainActor
final class CoachService {
    /// Chaves de `UserDefaults` (contrato V2-FINAL §2: strings exatas, compartilhadas).
    enum DefaultsKey {
        /// Double (`timeIntervalSince1970`), gravada pelo Ajustes depois de exportar backup.
        static let lastBackupAt = "lastBackupAt"
        /// Bool: a pessoa pediu aviso na véspera da expiração (SPEC §7.11 C4).
        static let expiryReminderEnabled = "expiryReminderEnabled"
        /// Double: desde quando o status da semana leve é `.pending` (período do id do C1).
        static let pendingDeloadSince = "coachPendingDeloadSince"
        /// String (`DeloadTrigger.rawValue`) do pendente acima; só o `CoachService` usa, para
        /// saber quando um pendente automático virou pedido manual.
        static let pendingDeloadTrigger = "coachPendingDeloadTrigger"
    }

    /// Identificador do lembrete de expiração (um só: reagendar substitui).
    nonisolated static let expiryReminderIdentifier = "coach.expiryReminder"
    /// SPEC §7.11 C4: "notificação local na véspera"; o contrato fixa as 10h.
    nonisolated static let expiryReminderHour = 10
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
    /// `ExpirationDate` do perfil embutido; `nil` no simulador.
    private(set) var provisioningExpiry: Date?
    /// Espelho de `DefaultsKey.expiryReminderEnabled`, relido a cada `refresh`.
    private(set) var isExpiryReminderEnabled: Bool
    /// Frase do que "Aplicar" vai mudar, por `CoachMessage.id` (só C2); ver `applySummary(for:)`.
    private(set) var applyDetails: [String: String] = [:]
    /// Mensagem pt-BR para o `.alert`; a view zera ao fechar.
    var errorMessage: String?

    // MARK: - Navegação (fechamentos que o integrador fornece)

    /// C7 "Fazer backup".
    @ObservationIgnored var onBackupRequested: (() -> Void)?
    /// C4 "Como renovar": abrir a `RenewalHelpView`.
    @ObservationIgnored var onRenewalHelpRequested: (() -> Void)?
    /// C5 "Começar".
    @ObservationIgnored var onStartRequested: (() -> Void)?
    /// C6 "Ver evolução" do exercício (`ExerciseDefinition.id`).
    @ObservationIgnored var onProgressRequested: ((UUID) -> Void)?
    /// C2 "Trocar de programa" sem outro programa do mesmo objetivo: a pessoa escolhe na aba
    /// Programa.
    @ObservationIgnored var onChooseProgramRequested: (() -> Void)?

    /// Fila das notificações (pedido de permissão, agendar, cancelar), encadeada para manter a
    /// ordem. Os testes aguardam `pendingWork?.value` em vez de dormir (AGENTS §7).
    @ObservationIgnored private(set) var pendingWork: Task<Void, Never>?

    // MARK: - Dependências

    let planner: any SessionPlanning
    let programs: any ProgramRepositoring
    let logStore: any CoachLogStoring
    let notifications: any NotificationScheduling
    let now: () -> Date
    let calendar: Calendar
    let defaults: UserDefaults

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
    /// O último estado do lembrete de expiração enviado ao agendador; `nil` antes do primeiro.
    @ObservationIgnored var appliedReminder: ReminderState?

    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "CoachService"
    )

    init(
        planner: any SessionPlanning,
        programs: any ProgramRepositoring,
        log: any CoachLogStoring,
        expiry: ProvisioningExpiryReader,
        notifications: any NotificationScheduling,
        now: @escaping () -> Date,
        calendar: Calendar,
        defaults: UserDefaults
    ) {
        self.planner = planner
        self.programs = programs
        self.logStore = log
        self.notifications = notifications
        self.now = now
        self.calendar = calendar
        self.defaults = defaults
        // O perfil só muda numa reinstalação, que reinicia o processo: basta ler uma vez.
        self.provisioningExpiry = expiry.expirationDate()
        self.isExpiryReminderEnabled = defaults.bool(forKey: DefaultsKey.expiryReminderEnabled)
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
    func refresh(healthSuggestions: [HealthSuggestion], recovery: RecoveryContext) {
        lastHealthSuggestions = healthSuggestions
        lastRecovery = recovery
        rebuild(allowsNewHighlight: true)
    }

    /// O que "Aplicar" vai mudar, para a confirmação (SPEC §7.11: "ações que alteram o programa
    /// pedem confirmação"). `nil` fora do C2.
    func applySummary(for message: CoachMessage) -> String? {
        applyDetails[message.id]
    }

    /// Fecha o destaque sem responder: a mensagem continua no feed da Home.
    func dismissHighlight() {
        highlight = nil
    }

    /// Chamar no `onDismiss` do `.sheet` do destaque: faz a navegação que uma resposta dada na
    /// folha pediu (ex.: "Como renovar" abre a `RenewalHelpView` depois que o destaque fecha).
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
    /// - `done` (C8): a própria resposta no log é a marca da semana;
    /// - `backupNow`, `howToRenew`, `start`, `seeProgress`: navegação pelos fechamentos.
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

    /// Liga ou desliga o aviso da véspera (SPEC §7.11 C4). Ligar é uma ação da pessoa, então é
    /// aqui (e na resposta à mensagem C4) que a permissão de notificação é pedida, nunca no
    /// launch (AGENTS §7).
    func setExpiryReminderEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.expiryReminderEnabled)
        isExpiryReminderEnabled = enabled
        syncExpiryReminder(now: now(), requestsAuthorization: enabled)
    }

    // MARK: - Internos

    /// Recalcula o feed com o log e os ajustes atuais.
    func rebuild(allowsNewHighlight: Bool) {
        let now = self.now()
        isExpiryReminderEnabled = defaults.bool(forKey: DefaultsKey.expiryReminderEnabled)
        var log = logStore.load()
        let input = makeInput(log: &log, now: now)
        messages = CoachFeedBuilder.feed(input: input, log: log, now: now, calendar: calendar)
        applyDetails = makeApplyDetails(for: messages)
        updateHighlight(allowsNew: allowsNewHighlight)
        syncExpiryReminder(now: now, requestsAuthorization: false)
    }

    /// Mantém o destaque aberto enquanto a mensagem existir; um novo só quando permitido (o
    /// `refresh`, não a resposta a outra mensagem, para não encadear folhas).
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
