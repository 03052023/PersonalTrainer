import Testing
@testable import TrainerCore

@Test("Pacote expõe versão")
func packageHasVersion() {
    #expect(!TrainerCore.version.isEmpty)
}
