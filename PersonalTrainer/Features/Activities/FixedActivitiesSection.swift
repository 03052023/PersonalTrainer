import SwiftUI
import TrainerCore

/// "Atividades fixas" da aba Plano (SPEC §7.17 X2, RF-53; DESIGN §9.3): as atividades fora do app que se
/// repetem toda semana ("Pilates · terça · 19h · 50 min"), com "Acrescentar atividade fixa", editar e
/// apagar.
///
/// Andaime da 2.4 (docs/V24-CONTRACT.md §3.2): a assinatura `init(model:)` está congelada (a `plans-ui` põe
/// a seção na aba Plano); o corpo é da tarefa `activities-ui`.
struct FixedActivitiesSection: View {
    let model: ActivitiesModel

    init(model: ActivitiesModel) {
        self.model = model
    }

    var body: some View {
        EmptyView()
    }
}
