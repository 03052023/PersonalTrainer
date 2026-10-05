import SwiftUI
import TrainerCore

/// As guias do "Como fazer" (SPEC RF-40, §7.12) no ambiente do SwiftUI, para que a ficha da sessão, a folha
/// "Informações do exercício" e o catálogo mostrem o botão sem receber o catálogo por `init`
/// (docs/V23-UI-CONTRACT.md §4.4).
///
/// O integrador injeta na raiz, uma vez, `ExerciseGuideLibrary.load(bundle: .main)`. Sem injeção (previews
/// isoladas, testes) ou com o arquivo reprovado na validação (SPEC E8), vale `.empty`: nenhum botão aparece e
/// nada mais muda.
private struct ExerciseGuidesKey: EnvironmentKey {
    static let defaultValue: ExerciseGuideCatalog = .empty
}

extension EnvironmentValues {
    var exerciseGuides: ExerciseGuideCatalog {
        get { self[ExerciseGuidesKey.self] }
        set { self[ExerciseGuidesKey.self] = newValue }
    }
}
