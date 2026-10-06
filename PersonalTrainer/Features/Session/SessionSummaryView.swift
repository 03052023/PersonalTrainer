import StoreKit
import SwiftData
import SwiftUI
import TrainerCore

/// "Sessão concluída" (SPEC F4, RF-44 h, RF-12; DESIGN §13 e §10; mockup "Sessão concluída"): a flor
/// do objetivo com a pétala se enchendo devagar, o nome do dia, Duração, "Exercícios X de Y" (feitos =
/// com ao menos uma série de trabalho), Séries (de trabalho), FC média/máx só quando houver e "A
/// próxima sessão já está pronta: Dia B — …". Sem tonelagem (fica no detalhe do Histórico), sem verde
/// nem laranja do sistema.
///
/// Só leitura: recebe a `WorkoutSessionModel` já `completed`/`abandoned` e formata; nada aqui
/// escreve no `ModelContext` (AGENTS R4). A FC chega do HealthKit pelo gravador logo depois de
/// concluir; como o modelo é observável, a linha aparece sozinha. O resumo não mantém a tela acesa
/// (RF-44 g).
///
/// Pedido de avaliação (SPEC §7.18 L3), só com `ratingGate` (o `SessionFlowView` só o passa depois de
/// concluir nesta abertura da ficha): uns 2 s depois de aparecer, a caixa do sistema
/// (`RequestReviewAction`), se a `RatingPromptPolicy` deixar. Se a pessoa sair antes, a tarefa é cancelada e
/// nada é pedido; com o Saúde ainda gravando, espera até mais 8 s e, sem resposta, não pede. Nunca ao tocar
/// num botão, sem texto do app pedindo avaliação e sem perguntar antes se a pessoa gostou (diretrizes 5.6.1
/// e 5.6.3 da App Store).
struct SessionSummaryView: View {
    /// L3: a espera depois de o resumo aparecer.
    static let ratingDelay: Duration = .seconds(2)
    /// L3: com o Saúde ainda gravando, mais `ratingHealthChecks` esperas de `ratingHealthInterval` (8 s).
    static let ratingHealthInterval: Duration = .milliseconds(500)
    static let ratingHealthChecks = 16

    private let session: WorkoutSessionModel
    private let activeGoal: ProgramGoal?
    private let nextDayName: String?
    private let ratingGate: RatingPromptGate?
    private let now: () -> Date
    private let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    /// Objetivo mostrado na flor: começa vazio e se enche ao aparecer (DESIGN §10).
    @State private var shownGoal: ProgramGoal? = nil

    /// - Parameters:
    ///   - ratingGate: `nil` nunca pede avaliação (sessão reaberta, encerrada sem registrar, previews).
    ///   - now: o relógio do `AppEnvironment`, para a regra da L3.
    init(
        session: WorkoutSessionModel,
        activeGoal: ProgramGoal?,
        nextDayName: String?,
        ratingGate: RatingPromptGate? = nil,
        now: @escaping () -> Date = { Date() },
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.activeGoal = activeGoal
        self.nextDayName = nextDayName
        self.ratingGate = ratingGate
        self.now = now
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                totals
                if let nextDayName, !nextDayName.isEmpty {
                    Text(SessionSheetText.nextSession(nextDayName))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 16)
        }
        .paperBackground()
        .safeAreaInset(edge: .bottom) {
            closeButton
        }
        .onAppear {
            fillPetal(with: activeGoal)
        }
        .onChange(of: activeGoal) { _, newGoal in
            fillPetal(with: newGoal)
        }
        .task {
            await requestRatingIfAllowed()
        }
    }

    // MARK: - Seções

    private var header: some View {
        VStack(spacing: 10) {
            FlowerView(activeGoal: shownGoal, size: 92)
            Text(SessionSheetText.summaryTitle(abandoned: isAbandoned))
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(session.programDayName)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var totals: some View {
        VStack(spacing: 0) {
            summaryRow("Duração", value: SessionSheetText.duration(stats.duration))
            Divider()
            summaryRow("Exercícios", value: SessionSheetText.exercisesDone(stats.exerciseCount, of: orderedExercises.count))
            Divider()
            summaryRow("Séries", value: "\(stats.workingSetCount)")
            if let heartRate = SessionSheetText.heartRate(average: session.avgHeartRate, maximum: session.maxHeartRate) {
                Divider()
                summaryRow("FC média / máx", value: heartRate)
            }
        }
        .padding(.horizontal, 16)
        .inkCard()
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Botão principal ≥ 56 pt (`PrimaryButtonStyle`), como o "Começar" da tela Hoje.
    private var closeButton: some View {
        Button("Fechar") {
            onClose()
        }
        .buttonStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.background)
    }

    // MARK: - Dados derivados

    private var isAbandoned: Bool {
        session.status == .abandoned
    }

    private var orderedExercises: [SessionExerciseModel] {
        session.exercises.sorted { $0.order < $1.order }
    }

    /// Duração, séries de trabalho e exercícios feitos (≥ 1 série de trabalho); aquecimentos
    /// antigos ficam fora (SPEC P1). Mesmo cálculo do detalhe do Histórico.
    private var stats: SessionStats {
        SessionStats.compute(
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exerciseSets: orderedExercises.map { exercise in
                exercise.sets
                    .sorted { $0.index < $1.index }
                    .map { HistoryMapper.setResult(from: $0) }
            }
        )
    }

    /// A pétala se enche devagar (DESIGN §10). Com Reduzir Movimento, a `FlowerView` troca o
    /// crescimento por uma mudança direta.
    private func fillPetal(with goal: ProgramGoal?) {
        guard shownGoal != goal else {
            return
        }
        if reduceMotion {
            shownGoal = goal
        } else {
            withAnimation(.easeInOut(duration: 0.6).delay(0.2)) {
                shownGoal = goal
            }
        }
    }

    // MARK: - Pedido de avaliação (SPEC §7.18 L3)

    /// Roda no `.task` do resumo: o SwiftUI cancela a tarefa quando a view some, e o `Task.sleep` cancelado
    /// lança, então sair antes dos 2 s nunca pede. Fora da loja, nem espera.
    private func requestRatingIfAllowed() async {
        guard let ratingGate, ratingGate.isStoreInstall else {
            return
        }
        let sessionID = session.uuid
        do {
            try await Task.sleep(for: Self.ratingDelay)
        } catch {
            return
        }
        var outcome = ratingGate.healthOutcome(for: sessionID)
        var remainingChecks = Self.ratingHealthChecks
        while outcome == .pending, remainingChecks > 0 {
            do {
                try await Task.sleep(for: Self.ratingHealthInterval)
            } catch {
                return
            }
            remainingChecks -= 1
            outcome = ratingGate.healthOutcome(for: sessionID)
        }
        guard !Task.isCancelled else {
            return
        }
        // Ainda `pending` depois da espera vira `.failed` na regra: não pede nesta sessão.
        ratingGate.requestIfAllowed(sessionID: sessionID, healthOutcome: outcome, now: now()) {
            requestReview()
        }
    }
}

// MARK: - Preview

#if DEBUG
/// Sessão encerrada montada só pelo caminho oficial de escrita (`SessionCoordinating`) sobre o
/// `AppEnvironment.preview()`: nenhum `insert`/`save` direto a partir de `Features/` (R4).
private enum SessionSummaryPreviewData {
    struct Fixture {
        let environment: AppEnvironment
        let session: WorkoutSessionModel
    }

    @MainActor
    static func make(abandoned: Bool) -> Fixture? {
        let environment = AppEnvironment.preview()
        let coordinator = environment.coordinator
        var clock = environment.now()
        guard
            let plan = try? environment.planner.nextPlan(now: clock),
            let sessionID = try? environment.planner.startSession(from: plan, now: clock)
        else {
            return nil
        }

        for (position, planned) in plan.exercises.enumerated() {
            // O último exercício fica pulado.
            if position == plan.exercises.count - 1 {
                try? coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: planned.id, now: clock)
                continue
            }
            for index in 0..<max(0, planned.prescription.sets) {
                clock = clock.addingTimeInterval(180)
                _ = try? coordinator.logSet(
                    sessionID: sessionID,
                    sessionExerciseID: planned.id,
                    index: index,
                    load: planned.prescription.load ?? 40,
                    reps: planned.prescription.repMax,
                    rir: nil,
                    isWarmup: false,
                    now: clock
                )
            }
        }

        clock = clock.addingTimeInterval(300)
        if abandoned {
            try? coordinator.abandonSession(sessionID: sessionID, now: clock)
        } else {
            try? coordinator.finishSession(sessionID: sessionID, now: clock)
        }
        guard let session = coordinator.session(withID: sessionID) else {
            return nil
        }
        return Fixture(environment: environment, session: session)
    }
}

#Preview("Sessão concluída") {
    if let fixture = SessionSummaryPreviewData.make(abandoned: false) {
        SessionSummaryView(
            session: fixture.session,
            activeGoal: .combat,
            nextDayName: "Dia B — Salto, terra e supino",
            onClose: {}
        )
        .modelContainer(fixture.environment.modelContainer)
        .tint(Theme.accent)
    } else {
        Text("Preview indisponível")
    }
}

#Preview("Sessão encerrada") {
    if let fixture = SessionSummaryPreviewData.make(abandoned: true) {
        SessionSummaryView(session: fixture.session, activeGoal: nil, nextDayName: nil, onClose: {})
            .modelContainer(fixture.environment.modelContainer)
            .tint(Theme.accent)
    } else {
        Text("Preview indisponível")
    }
}
#endif
