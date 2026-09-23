import SwiftUI

/// Fluxo modal da sessão (T1.8): `ActiveSessionView` enquanto o treino está em andamento e
/// `SessionSummaryView` depois de Finalizar/Abandonar (SPEC F4). Apresentado pelo `RootView`
/// em `fullScreenCover`; `onClose` devolve o controle à Home, que recalcula o próximo treino.
///
/// Monta o `ActiveSessionViewModel` a partir do `AppEnvironment` recebido por parâmetro (a
/// feature não lê o ambiente sozinha, ARCHITECTURE §3) e o guarda em `@State` para que
/// sobreviva às reavaliações do `body` de quem apresenta.
struct SessionFlowView: View {
    @State private var model: ActiveSessionViewModel
    /// Sessão encerrada, relida pelo coordinator ao finalizar; `nil` enquanto o treino corre.
    @State private var finishedSession: WorkoutSessionModel? = nil

    private let sessionID: UUID
    private let coordinator: any SessionCoordinating
    private let onClose: () -> Void

    init(sessionID: UUID, environment: AppEnvironment, onClose: @escaping () -> Void) {
        self.sessionID = sessionID
        self.coordinator = environment.coordinator
        self.onClose = onClose
        self._model = State(initialValue: ActiveSessionViewModel(
            sessionID: sessionID,
            coordinator: environment.coordinator,
            restTimer: environment.restTimer,
            notifications: environment.notifications,
            now: environment.now
        ))
    }

    var body: some View {
        if let finishedSession {
            SessionSummaryView(session: finishedSession, onClose: onClose)
        } else {
            ActiveSessionView(model: model, onFinished: { showSummary() })
        }
    }

    /// `onFinished` só dispara depois de `finish()`/`abandon()` bem-sucedidos: a sessão já está
    /// gravada como `completed`/`abandoned` (RF-06) e o resumo lê esse estado final pelo
    /// coordinator, a fonte da verdade (ARCHITECTURE §7).
    private func showSummary() {
        guard let session = coordinator.session(withID: sessionID) ?? model.session else {
            // Sem sessão para resumir (store inacessível): volta direto à Home.
            onClose()
            return
        }
        finishedSession = session
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
