import SwiftUI
import TrainerCore

/// Uma sugestão de saúde (SPEC §7.10 A3–A5, RF-28..RF-30): título, motivo com os números (A6),
/// botão "Por quê?" com as referências do tópico da sugestão (RF-32) e "Ok, entendi", que esconde
/// a sugestão até o fim da semana (TASKS T5.3).
struct HealthSuggestionRow: View {
    private let suggestion: HealthSuggestion
    private let references: ReferenceCatalog
    private let onDismiss: (@MainActor () -> Void)?

    /// - Parameter onDismiss: `nil` esconde o botão "Ok, entendi" (ex.: previews).
    init(
        suggestion: HealthSuggestion,
        references: ReferenceCatalog,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.suggestion = suggestion
        self.references = references
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: Self.symbolName(for: suggestion.kind))
                    .foregroundStyle(.secondary)
            }
            Text(suggestion.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                WhyButton(topic: suggestion.referenceTopic, catalog: references)
                Spacer(minLength: 0)
                if let onDismiss {
                    Button("Ok, entendi") {
                        onDismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        // Numa List, sem `.borderless` um toque em qualquer ponto da linha dispararia os dois botões.
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    /// Símbolo por tipo de sugestão; também usado na linha de sugestão do card.
    static func symbolName(for kind: HealthSuggestionKind) -> String {
        switch kind {
        case .wearWatchAtNight: return "applewatch"
        case .updateVo2Max: return "figure.walk"
        case .aerobicDeficit: return "heart"
        case .lowSleep: return "bed.double"
        case .recoveryAlert: return "exclamationmark.triangle"
        case .lowSteps: return "figure.walk"
        }
    }
}
