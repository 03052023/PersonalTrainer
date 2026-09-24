import SwiftUI
import TrainerCore

/// Seção de mensagens do diálogo na Home (SPEC §7.11, RF-37): um `CoachMessageCard` por
/// mensagem, na ordem do feed (a mais importante primeiro). Sem mensagens, não ocupa espaço.
///
/// View pura: recebe `CoachService.messages` e devolve as respostas por `onAction`; o
/// integrador liga `onAction` a `CoachService.handle(_:on:)` e, se quiser o texto da
/// confirmação do "Aplicar", `applyDetail` a `CoachService.applySummary(for:)`.
struct CoachFeedSection: View {
    let messages: [CoachMessage]
    let references: ReferenceCatalog
    let onAction: (CoachAction, CoachMessage) -> Void
    let applyDetail: (CoachMessage) -> String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // DESIGN §5: títulos de seção em New York.
                Text("Mensagens")
                    .font(.system(.title3, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                ForEach(messages) { message in
                    CoachMessageCard(
                        message: message,
                        references: references,
                        onAction: { action in onAction(action, message) },
                        applyDetail: applyDetail(message)
                    )
                    .transition(.opacity)
                }
            }
            // DESIGN §10: movimento lento e calmo; com Reduzir Movimento, sem animação.
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.4), value: messages)
        }
    }
}

#Preview("Mensagens da Home") {
    ScrollView {
        CoachFeedSection(
            messages: CoachPreviewData.all,
            references: WhySheet.previewCatalog,
            onAction: { _, _ in }
        )
        .padding()
    }
}

#Preview("Sem mensagens") {
    CoachFeedSection(messages: [], references: WhySheet.previewCatalog, onAction: { _, _ in })
}
