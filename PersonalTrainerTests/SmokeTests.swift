import TrainerCore
import XCTest

/// Garante que o alvo de testes do app enxerga o pacote local TrainerCore (T0.1).
final class SmokeTests: XCTestCase {
    func testTrainerCoreVersionIsNotEmpty() {
        XCTAssertFalse(TrainerCore.version.isEmpty)
    }
}
