import Foundation
import XCTest
@testable import PersonalTrainer

/// Integração da 2.5 (contrato docs/V25-CONTRACT.md §7): o que só existe depois de ligar as tarefas no
/// `AppEnvironment`. As regras em si têm os próprios testes (`RatingPromptTests`, `PrivacyAboutTests`,
/// `CoachServiceTests`); aqui fica só a ligação.
@MainActor
final class AppStoreWiringTests: XCTestCase {
    /// SPEC §7.18 L3 e AGENTS R9: o ambiente das previews usa o Fake, fora da loja, e nunca pede.
    func testL3_previewEnvironmentNeverAsks() {
        let environment = AppEnvironment.preview()
        XCTAssertFalse(environment.ratingPrompt.isStoreInstall)
        XCTAssertTrue(environment.ratingPrompt is FakeRatingPromptStore, "Preview usa o Fake (AGENTS R9)")
        XCTAssertNil(environment.ratingPrompt.lastRequest())

        // O mesmo portão que o `SessionFlowView` monta com o ambiente: fora da loja, nem lê o histórico.
        let gate = RatingPromptGate(
            store: environment.ratingPrompt,
            planner: environment.planner,
            recorder: environment.healthRecorder
        )
        var requests = 0
        let asked = gate.requestIfAllowed(
            sessionID: UUID(),
            healthOutcome: .saved,
            now: Date(timeIntervalSince1970: 1_800_000_000),
            request: { requests += 1 }
        )
        XCTAssertFalse(asked)
        XCTAssertEqual(requests, 0)
        XCTAssertNil(environment.ratingPrompt.lastRequest(), "Sem pedido, nada é gravado")
    }
}
