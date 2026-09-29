import Foundation
import Observation
import os
import TrainerCore

/// Estado da aba "Início" (SPEC RF-49, §7.16; DESIGN §9.1/§9.2; docs/V23-UI-CONTRACT.md §4.3): a
/// saudação, os objetivos ativos, "Esta semana" e o caminho para o treino de hoje, mais as "Metas da
/// semana" que a tela empurra.
///
/// Lê o planejador (`SessionPlanning`) e a sessão em andamento (`SessionCoordinating`); nunca toca o
/// `ModelContext` (AGENTS R4). O relógio e o calendário chegam por parâmetro (SPEC P11): nada aqui lê
/// a data do sistema (AGENTS R3). O relatório de Saúde chega pronto por `healthReport` — este
/// ViewModel nunca pede autorização (AGENTS §7); `loadHealth` só é chamado por `openWeeklyGoals()`,
/// quando a pessoa abre as Metas, e só lê o que já foi autorizado (SPEC §7.16 W4).
@Observable
@MainActor
final class LandingViewModel {
    /// O caminho para o treino de hoje (SPEC RF-49, ponto 2 do contrato da `home`).
    enum PathState: Equatable {
        /// Sessão em andamento (SPEC S3): "Retomar a sessão" abre `onOpenSession(sessionID)`.
        case inProgress(sessionID: UUID, label: String)
        /// Uma ou duas sessões pendentes hoje: "Ver a sessão de hoje" abre `onOpenToday()`.
        case todaySessions(label: String, subtitle: String)
        /// Todas as sessões de hoje já foram feitas.
        case allDone
        /// Dia de descanso da semana ideal (dois planos, SPEC §7.15 M6).
        case restDay
        /// Nenhum objetivo ativo: "Escolher um objetivo" abre `onOpenToday()` (a folha "Seu
        /// objetivo" abre pela tela Hoje).
        case noGoal
    }

    // MARK: Estado exposto

    /// Objetivos ativos, o principal primeiro (SPEC §7.15 M1); vazio sem objetivo.
    private(set) var activeGoals: [ProgramGoal] = []
    /// "segunda-feira, 28 de setembro" (RF-49), no calendário e no fuso da pessoa.
    private(set) var dateText = ""
    /// "Bom dia" / "Boa tarde" / "Boa noite" pelo horário do relógio injetado (RF-49).
    private(set) var greeting = ""
    private(set) var pathState: PathState = .noGoal
    /// Segunda a domingo (índice 0…6, `PlanWeekday`): cheio quando há sessão concluída com
    /// série naquele dia da semana corrente.
    private(set) var weekMarks: [Bool] = Array(repeating: false, count: 7)
    /// Índice de hoje em `weekMarks` (`PlanWeekday.of(now:calendar:).rawValue`).
    private(set) var todayWeekdayIndex = 0
    /// "2 sessões nesta semana." / "1 sessão nesta semana." / "Nenhuma sessão nesta semana ainda."
    private(set) var weekSentence = ""
    /// `nil` quando a última leitura da semana deu certo. Só as marcas somem; o caminho continua.
    private(set) var weekReadErrorMessage: String?
    /// As metas da semana (SPEC RF-52, §7.16), para a tela "Metas da semana" embutida.
    private(set) var weeklyGoals: [WeeklyGoal] = []
    /// A mesma frequência por grupo muscular que alimenta a meta `.muscles`, para a grade de
    /// detalhe da tela ("Peito 1 de 2", DESIGN §9.2).
    private(set) var muscleFrequency = WeeklyFrequencyReport(weekStart: .distantPast, weekEnd: .distantPast, entries: [])
    /// "28 set. – 4 out.": o intervalo da semana, embaixo do título das Metas (DESIGN §9.2).
    private(set) var weekRangeText = ""

    // MARK: Dependências

    private let planner: any SessionPlanning
    private let coordinator: any SessionCoordinating
    private let now: () -> Date
    private let calendar: Calendar
    private let healthReport: @MainActor () -> HealthReport?
    private let loadHealth: @MainActor () async -> Void
    private let longevityDone: @MainActor () -> Set<String>

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Landing"
    )

    init(
        planner: any SessionPlanning,
        coordinator: any SessionCoordinating,
        now: @escaping () -> Date,
        calendar: Calendar = .autoupdatingCurrent,
        healthReport: @escaping @MainActor () -> HealthReport? = { nil },
        loadHealth: @escaping @MainActor () async -> Void = {},
        longevityDone: @escaping @MainActor () -> Set<String> = { [] }
    ) {
        self.planner = planner
        self.coordinator = coordinator
        self.now = now
        self.calendar = calendar
        self.healthReport = healthReport
        self.loadHealth = loadHealth
        self.longevityDone = longevityDone
    }

    // MARK: Ações

    /// Relê tudo (o integrador chama ao aparecer, ao voltar para a aba e ao voltar ao primeiro
    /// plano). Nunca lança: uma falha do planejador vira log e um estado seguro (RF-49 ponto 5).
    func refresh() {
        let referenceDate = now()
        dateText = LandingText.dateText(referenceDate, calendar: calendar)
        greeting = LandingText.greeting(hour: calendar.component(.hour, from: referenceDate))

        let goals: [ProgramGoal] = read("os objetivos ativos", fallback: []) {
            try planner.activeProgramGoals()
        }
        activeGoals = goals

        let overview: TodayOverview = read("as sessões de hoje", fallback: .empty) {
            try planner.todayOverview(now: referenceDate)
        }
        pathState = Self.computePathState(
            activeSession: coordinator.activeSession,
            hasActiveGoal: !goals.isEmpty,
            overview: overview
        )

        do {
            let summaries = try planner.completedSessionSummaries()
            let (marks, sentence) = Self.weekMarksAndSentence(
                summaries: summaries,
                now: referenceDate,
                calendar: calendar
            )
            weekMarks = marks
            weekSentence = sentence
            weekReadErrorMessage = nil
        } catch {
            Self.logger.error("Falha ao ler a semana: \(String(describing: error))")
            weekMarks = Array(repeating: false, count: 7)
            weekSentence = ""
            weekReadErrorMessage = "Não foi possível ler a semana."
        }
        todayWeekdayIndex = PlanWeekday.of(referenceDate, calendar: calendar).rawValue

        // Sem a leitura, a semana de segunda a domingo dá o intervalo do título; sem grupos, a meta de
        // músculos some (W2.2) e o resto das Metas segue.
        let week = WeeklyFrequency.weekInterval(containing: referenceDate, weekStartsOnMonday: true, calendar: calendar)
        let frequency: WeeklyFrequencyReport = read(
            "a frequência da semana",
            fallback: WeeklyFrequencyReport(weekStart: week.start, weekEnd: week.end, entries: [])
        ) {
            try planner.weeklyFrequency(now: referenceDate)
        }
        muscleFrequency = frequency
        weekRangeText = LandingText.weekRangeText(
            weekStart: frequency.weekStart,
            weekEnd: frequency.weekEnd,
            calendar: calendar
        )
        let plans: [PlanWeekProgress] = read("o progresso dos planos", fallback: []) {
            try planner.planWeekProgress(now: referenceDate)
        }
        weeklyGoals = WeeklyGoals.goals(WeeklyGoalsInput(
            plans: plans,
            activeGoals: goals,
            frequency: frequency,
            health: healthReport(),
            longevityDone: longevityDone()
        ))
    }

    /// A tela "Metas da semana" chama ao abrir (SPEC §7.16 W4): lê o Saúde se já autorizado (nunca
    /// pede, AGENTS §7) e relê tudo, para as metas de aeróbico, passos e sono chegarem atualizadas.
    func openWeeklyGoals() async {
        await loadHealth()
        refresh()
    }

    /// Uma leitura do planejador que nunca derruba a tela: se falhar, registra no log e devolve o
    /// valor seguro (RF-49 ponto 5).
    private func read<Value>(_ what: String, fallback: Value, _ body: () throws -> Value) -> Value {
        do {
            return try body()
        } catch {
            Self.logger.error("Falha ao ler \(what): \(String(describing: error))")
            return fallback
        }
    }

    // MARK: - Cálculo (puro, testável sem MainActor além da assinatura)

    static func computePathState(
        activeSession: WorkoutSessionModel?,
        hasActiveGoal: Bool,
        overview: TodayOverview
    ) -> PathState {
        if let activeSession {
            return .inProgress(
                sessionID: activeSession.uuid,
                label: "Sessão em andamento: \(activeSession.programDayName)"
            )
        }
        guard hasActiveGoal else {
            return .noGoal
        }
        if overview.isRestDay {
            return .restDay
        }
        let pending = overview.sessions.filter { !$0.isDoneToday }
        guard let first = pending.first else {
            // Sessions vazio com objetivo ativo só acontece com um programa sem dias (raríssimo,
            // planner malformado): trata como "tudo feito" em vez de travar a tela (AGENTS R11).
            return .allDone
        }
        if pending.count == 1 {
            return .todaySessions(
                label: first.plan.programDayName,
                subtitle: LandingText.exerciseCountSubtitle(
                    exerciseCount: first.plan.exercises.count,
                    estimatedMinutes: first.plan.estimatedMinutes
                )
            )
        }
        let label = pending.map(\.plan.programDayName).joined(separator: " + ")
        let totalMinutes = pending.reduce(0) { $0 + $1.plan.estimatedMinutes }
        return .todaySessions(
            label: label,
            subtitle: LandingText.multipleSessionsSubtitle(count: pending.count, estimatedMinutes: totalMinutes)
        )
    }

    /// Marcas por dia da semana corrente (segunda a domingo) e a frase de fato (RF-49): conta
    /// sessões `completed` com ao menos uma série de trabalho, iniciadas na semana (SPEC §7.4).
    static func weekMarksAndSentence(
        summaries: [SessionSummary],
        now: Date,
        calendar: Calendar
    ) -> (marks: [Bool], sentence: String) {
        let week = WeeklyFrequency.weekInterval(containing: now, weekStartsOnMonday: true, calendar: calendar)
        let thisWeek = summaries.filter { summary in
            summary.status == .completed
                && summary.workingSetCount >= 1
                && summary.startedAt >= week.start
                && summary.startedAt < week.end
        }
        var marks = Array(repeating: false, count: 7)
        for summary in thisWeek {
            marks[PlanWeekday.of(summary.startedAt, calendar: calendar).rawValue] = true
        }
        return (marks, LandingText.weekSentence(sessionCount: thisWeek.count))
    }
}
