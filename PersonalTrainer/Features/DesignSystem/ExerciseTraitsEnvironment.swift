import SwiftUI
import TrainerCore

/// Medida e marca "de casa" dos exercícios (SPEC RF-42, RF-43) no ambiente do SwiftUI, para que
/// qualquer tela formate "3 × 20–40 s" ou "30 passos" sem receber o catálogo por `init`.
/// Injetado na raiz (`PersonalTrainerApp`) a partir de `AppEnvironment.traits`; sem injeção
/// (previews isoladas, testes), vale `.empty`: tudo em repetições.
private struct ExerciseTraitsKey: EnvironmentKey {
    static let defaultValue: ExerciseTraitsCatalog = .empty
}

extension EnvironmentValues {
    var exerciseTraits: ExerciseTraitsCatalog {
        get { self[ExerciseTraitsKey.self] }
        set { self[ExerciseTraitsKey.self] = newValue }
    }
}
