import SwiftUI
import TrainerCore

/// Botões de resposta de uma mensagem do diálogo (SPEC §7.11), na ordem de `CoachMessage.actions`:
/// a primeira é a principal; "Não sugerir mais isto" fica discreta, numa linha própria.
///
/// "Aplicar" pede confirmação antes de sair pelo `onAction` (SPEC §7.11: "ações que alteram o
/// programa pedem confirmação"). View pura: quem aplica é o `CoachService`.
struct CoachActionButtons: View {
    let message: CoachMessage
    /// Frase do que "Aplicar" muda (`CoachService.applySummary(for:)`); `nil` usa o texto padrão.
    let applyDetail: String?
    /// Botões em coluna e na largura toda (folha de destaque) ou lado a lado (cartão da Home).
    let fillsWidth: Bool
    let onAction: (CoachAction) -> Void

    @State private var isConfirmingApply = false

    init(
        message: CoachMessage,
        applyDetail: String? = nil,
        fillsWidth: Bool = false,
        onAction: @escaping (CoachAction) -> Void
    ) {
        self.message = message
        self.applyDetail = applyDetail
        self.fillsWidth = fillsWidth
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fillsWidth {
                VStack(spacing: 10) {
                    mainButtons
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        mainButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        mainButtons
                    }
                }
            }
            if message.actions.contains(.neverAgain) {
                Button(CoachAction.neverAgain.label) {
                    onAction(.neverAgain)
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            }
        }
        .confirmationDialog(
            "Aplicar ao programa?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("Aplicar") {
                onAction(.apply)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(applyDetail ?? "A mudança vale a partir da próxima sessão, e você pode ajustar de novo na aba Programa.")
        }
    }

    /// Todas as respostas menos "Não sugerir mais isto".
    private var mainActions: [CoachAction] {
        message.actions.filter { $0 != .neverAgain }
    }

    private var mainButtons: some View {
        ForEach(mainActions, id: \.self) { action in
            actionButton(action, isPrimary: action == mainActions.first)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: CoachAction, isPrimary: Bool) -> some View {
        let button = Button {
            tap(action)
        } label: {
            Text(action.label)
                .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
        }
        if isPrimary {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func tap(_ action: CoachAction) {
        if action == .apply {
            isConfirmingApply = true
        } else {
            onAction(action)
        }
    }
}

#Preview("Respostas — cartão") {
    CoachActionButtons(message: CoachPreviewData.review) { _ in }
        .padding()
}

#Preview("Respostas — destaque") {
    CoachActionButtons(message: CoachPreviewData.deload, fillsWidth: true) { _ in }
        .padding()
}
