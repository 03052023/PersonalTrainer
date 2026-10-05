import SwiftUI
import TrainerCore

/// "Também hoje" da tela Hoje (SPEC §7.17 X2, RF-53; DESIGN §9.3): as atividades fixas de hoje
/// ("Pilates · 19h · 50 min") com "Feito", que grava o registro do dia. Sem fixa hoje, não desenha nada.
///
/// Andaime da 2.4 (docs/V24-CONTRACT.md §3.2): a assinatura `init(model:)` está congelada (a `plans-ui` põe o
/// cartão na tela Hoje); o corpo é da tarefa `activities-ui`.
struct TodayActivitiesCard: View {
    let model: ActivitiesModel

    init(model: ActivitiesModel) {
        self.model = model
    }

    var body: some View {
        EmptyView()
    }
}
