import SwiftData
import SwiftUI
import TrainerCore

/// Fluxo modal da sessão (T1.8, T7.1): a ficha (`ActiveSessionView`) enquanto a sessão está em
/// andamento e o resumo (`SessionSummaryView`) depois de concluir ou encerrar (SPEC F4, RF-44).
/// Apresentado pelo `RootView` em `fullScreenCover`; `onClose` devolve o controle à tela Hoje, que
/// recalcula o próximo treino.
///
/// O cover fica fora do tint da raiz, então a paleta do app (DESIGN §3 e §13: tint `accent`, fundo
/// `background`) é aplicada aqui, na ficha e no resumo. Antes a sessão aparecia com o preto e o azul
/// do sistema.
///
/// Monta o `ActiveSessionViewModel` a partir do `AppEnvironment` recebido por parâmetro (a
/// feature não lê o ambiente sozinha, ARCHITECTURE §3) e o guarda em `@State` para que
/// sobreviva às reavaliações do `body` de quem apresenta.
///
/// O cover não tem gesto de dispensa, então todo estado precisa de uma saída: sem sessão
/// carregável há um botão "Voltar"; sessão já encerrada ao abrir (id obsoleto) vai direto ao
/// resumo, onde "Fechar" chama `onClose`; durante a sessão, "Voltar" (minimizar) também chama
/// `onClose`, sem encerrar nada: a sessão segue em andamento e a tela Hoje oferece "Retomar" (S3).
struct SessionFlowView: View {
    @State private var model: ActiveSessionViewModel
    /// Sessão encerrada, relida pelo coordinator ao concluir; `nil` enquanto a sessão corre.
    @State private var finishedSession: WorkoutSessionModel? = nil
    /// Flor e "próxima sessão" do resumo, lidos do planner uma vez (RF-44 h).
    @State private var summaryGoal: ProgramGoal? = nil
    @State private var nextDayName: String? = nil
    @State private var hasLoadedSummary = false

    private let sessionID: UUID
    private let coordinator: any SessionCoordinating
    private let references: ReferenceCatalog
    private let onClose: () -> Void

    init(sessionID: UUID, environment: AppEnvironment, onClose: @escaping () -> Void) {
        self.sessionID = sessionID
        self.coordinator = environment.coordinator
        self.references = environment.references
        self.onClose = onClose
        self._model = State(initialValue: ActiveSessionViewModel(
            sessionID: sessionID,
            coordinator: environment.coordinator,
            planner: environment.planner,
            restTimer: environment.restTimer,
            notifications: environment.notifications,
            now: environment.now,
            traits: environment.traits
        ))
    }

    var body: some View {
        content
            .tint(Theme.accent)
            .paperBackground()
    }

    @ViewBuilder
    private var content: some View {
        if let finishedSession {
            summary(for: finishedSession)
        } else if let session = model.session {
            if model.isFinished {
                // Já `completed`/`abandoned` ao abrir: não há série a marcar e concluir falharia
                // com `sessionNotInProgress`; o resumo é a única tela que faz sentido.
                summary(for: session)
                    .onAppear {
                        loadSummaryIfNeeded()
                    }
            } else {
                ActiveSessionView(
                    model: model,
                    references: references,
                    onFinished: { showSummary() },
                    onMinimize: onClose
                )
            }
        } else {
            missingSession
        }
    }

    private func summary(for session: WorkoutSessionModel) -> some View {
        SessionSummaryView(
            session: session,
            activeGoal: summaryGoal,
            nextDayName: nextDayName,
            onClose: onClose
        )
    }

    /// Sessão não encontrada (id inválido ou fetch falhou): concluir não tem em que agir e nunca
    /// dispararia `onFinished`, então a saída é explícita.
    private var missingSession: some View {
        ContentUnavailableView {
            Label("Sessão não encontrada", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Não foi possível carregar esta sessão. Volte à tela Hoje e tente de novo.")
        } actions: {
            Button("Voltar") {
                onClose()
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 32)
        }
    }

    /// `onFinished` só dispara depois de concluir ou encerrar com sucesso: a sessão já está
    /// gravada (RF-06) e o resumo lê esse estado final pelo coordinator, a fonte da verdade
    /// (ARCHITECTURE §7).
    private func showSummary() {
        guard let session = coordinator.session(withID: sessionID) ?? model.session else {
            // Sem sessão para resumir (store inacessível): volta direto à tela Hoje.
            onClose()
            return
        }
        loadSummaryIfNeeded()
        finishedSession = session
    }

    /// O objetivo ativo e a próxima sessão, depois de a sessão estar gravada: o planner já
    /// conta com ela para escolher o próximo dia (SPEC S2).
    private func loadSummaryIfNeeded() {
        guard !hasLoadedSummary else {
            return
        }
        hasLoadedSummary = true
        summaryGoal = model.activeGoal()
        nextDayName = model.nextSessionName()
    }
}

// MARK: - Preview

#if DEBUG
/// Sessão recém-iniciada sobre o `AppEnvironment.preview()`, só pelo planner (R4).
private enum SessionFlowPreviewData {
    struct Fixture {
        let environment: AppEnvironment
        let sessionID: UUID
    }

    @MainActor
    static func make() -> Fixture? {
        let environment = AppEnvironment.preview()
        let now = environment.now()
        guard
            let plan = try? environment.planner.nextPlan(now: now),
            let sessionID = try? environment.planner.startSession(from: plan, now: now)
        else {
            return nil
        }
        return Fixture(environment: environment, sessionID: sessionID)
    }
}

#Preview {
    if let fixture = SessionFlowPreviewData.make() {
        SessionFlowView(sessionID: fixture.sessionID, environment: fixture.environment, onClose: {})
            .modelContainer(fixture.environment.modelContainer)
    } else {
        Text("Preview indisponível")
    }
}
#endif
