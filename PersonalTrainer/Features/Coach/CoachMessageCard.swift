import SwiftUI
import TrainerCore

/// Uma mensagem do diálogo na Home (SPEC §7.11): título, a frase do motivo com os números, o
/// "Por quê?" (RF-32) e as respostas. Tom calmo (DESIGN §1, §6): nada de vermelho nem de alerta,
/// só o símbolo da regra na cor de ação.
///
/// View pura: a resposta sai por `onAction` e quem a aplica é o `CoachService`.
struct CoachMessageCard: View {
    let message: CoachMessage
    let references: ReferenceCatalog
    let onAction: (CoachAction) -> Void
    /// Frase do que "Aplicar" muda, mostrada na confirmação (`CoachService.applySummary(for:)`).
    let applyDetail: String?

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: message.rule.symbolName)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(message.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(message.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let topic = message.referenceTopic {
                WhyButton(topic: topic, catalog: references)
            }
            CoachActionButtons(message: message, applyDetail: applyDetail, fillsWidth: false, onAction: onAction)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Mensagem — revisão") {
    ScrollView {
        CoachMessageCard(
            message: CoachPreviewData.review,
            references: WhySheet.previewCatalog,
            onAction: { _ in },
            applyDetail: "Supino reto e Crucifixo passam a ter 4 séries por sessão. Faixa, RIR e descanso continuam iguais."
        )
        .padding()
    }
}

#Preview("Mensagem — semana leve") {
    CoachMessageCard(message: CoachPreviewData.deload, references: WhySheet.previewCatalog, onAction: { _ in })
        .padding()
}
