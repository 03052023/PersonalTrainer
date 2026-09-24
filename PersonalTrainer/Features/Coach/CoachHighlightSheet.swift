import SwiftUI
import TrainerCore

/// Destaque de uma mensagem ao abrir o app (SPEC §7.11: "exibidas na abertura, se houver algo
/// novo e importante"): C4, C1, C5 e C2 (`CoachMessage.highlightsOnLaunch`).
///
/// Apresentação pelo integrador:
/// ```swift
/// .sheet(item: $coach.highlight, onDismiss: { coach.highlightDidDismiss() }) { message in
///     CoachHighlightSheet(message: message, references: env.references,
///                         onAction: { coach.handle($0, on: message) },
///                         applyDetail: coach.applySummary(for: message))
/// }
/// ```
/// A folha não se fecha sozinha depois de uma resposta: `CoachService.handle` zera
/// `highlight`, o que a fecha. "Fechar" só dispensa o destaque; a mensagem continua na Home.
struct CoachHighlightSheet: View {
    let message: CoachMessage
    let references: ReferenceCatalog
    let onAction: (CoachAction) -> Void
    let applyDetail: String?

    @Environment(\.dismiss) private var dismiss

    init(
        message: CoachMessage,
        references: ReferenceCatalog,
        onAction: @escaping (CoachAction) -> Void,
        applyDetail: String? = nil
    ) {
        self.message = message
        self.references = references
        self.onAction = onAction
        self.applyDetail = applyDetail
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: message.rule.symbolName)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    // DESIGN §5: título em New York.
                    Text(message.title)
                        .font(.system(.title2, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message.reason)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if let topic = message.referenceTopic {
                        WhyButton(topic: topic, catalog: references)
                    }
                    CoachActionButtons(message: message, applyDetail: applyDetail, fillsWidth: true, onAction: onAction)
                        .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Destaque — expiração") {
    Text("Home")
        .sheet(isPresented: .constant(true)) {
            CoachHighlightSheet(message: CoachPreviewData.expiry, references: WhySheet.previewCatalog, onAction: { _ in })
        }
}

#Preview("Destaque — revisão") {
    CoachHighlightSheet(
        message: CoachPreviewData.review,
        references: WhySheet.previewCatalog,
        onAction: { _ in },
        applyDetail: "Supino reto e Crucifixo passam a ter 4 séries por sessão. Faixa, RIR e descanso continuam iguais."
    )
}
