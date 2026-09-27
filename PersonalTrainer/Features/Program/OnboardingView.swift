import SwiftUI
import TrainerCore

/// Primeiro uso (SPEC RF-45, RF-35, §7.9): um passo só, a folha "Seu objetivo" em `.firstUse`,
/// com o título "Qual é o seu objetivo?", os formatos da Hipertrofia e o aviso de técnica do
/// Combate. "Começar" ativa a escolha se ela não for a ativa; "Pular" mantém o programa ativo. Os
/// dois marcam `hasCompletedOnboarding` em `@AppStorage` (UserDefaults, sem SwiftData) e chamam
/// `onDone`.
///
/// Apresentado pelo integrador em `.sheet`; o gesto de dispensa fica desligado para que toda
/// saída passe por "Começar" ou "Pular" e a marca seja gravada.
struct OnboardingView: View {
    private let programs: any ProgramRepositoring
    private let references: ReferenceCatalog
    private let catalog: (any CatalogRepositoring)?
    private let onDone: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// `catalog` só alimenta a prévia "Dia A: …"; sem ele, a folha fica sem prévia.
    init(
        programs: any ProgramRepositoring,
        references: ReferenceCatalog,
        catalog: (any CatalogRepositoring)? = nil,
        onDone: @escaping () -> Void
    ) {
        self.programs = programs
        self.references = references
        self.catalog = catalog
        self.onDone = onDone
    }

    var body: some View {
        GoalSheet(
            programs: programs,
            catalog: catalog,
            references: references,
            mode: .firstUse,
            isSessionInProgress: false,
            onFinish: { _ in
                finish()
            }
        )
        .interactiveDismissDisabled()
    }

    private func finish() {
        hasCompletedOnboarding = true
        onDone()
    }
}
