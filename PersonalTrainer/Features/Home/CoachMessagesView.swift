import SwiftUI
import TrainerCore

/// "Ver todas (N)" do diálogo da Home (SPEC §7.11; DESIGN §9.4; docs/V22-CONTRACT.md §3.3): a
/// mesma `CoachFeedSection` da Home, sem o corte de `Array(coach.messages.prefix(1))`, empurrada
/// dentro da `NavigationStack` da Home. `onAction` e `applyDetail` são os mesmos fechamentos da
/// Home, para que responder por aqui tenha o mesmo efeito que responder na tela inicial.
struct CoachMessagesView: View {
    let messages: [CoachMessage]
    let references: ReferenceCatalog
    let onAction: (CoachAction, CoachMessage) -> Void
    let applyDetail: (CoachMessage) -> String?

    init(
        messages: [CoachMessage],
        references: ReferenceCatalog,
        onAction: @escaping (CoachAction, CoachMessage) -> Void,
        applyDetail: @escaping (CoachMessage) -> String? = { _ in nil }
    ) {
        self.messages = messages
        self.references = references
        self.onAction = onAction
        self.applyDetail = applyDetail
    }

    var body: some View {
        ScrollView {
            CoachFeedSection(
                messages: messages,
                references: references,
                onAction: onAction,
                applyDetail: applyDetail
            )
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Mensagens")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Ver todas") {
    NavigationStack {
        CoachMessagesView(
            messages: CoachPreviewData.all,
            references: WhySheet.previewCatalog,
            onAction: { _, _ in }
        )
    }
}
