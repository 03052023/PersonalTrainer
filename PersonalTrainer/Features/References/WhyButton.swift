import SwiftUI
import TrainerCore

/// Botão pequeno "Por quê?" (SPEC RF-32) que abre a `WhySheet` do tópico. Some quando o
/// catálogo não tem referência para o tópico — inclusive quando o catálogo não carregou
/// (`ReferenceCatalog.empty`) —, para nunca abrir uma folha vazia.
///
/// Usa `.buttonStyle(.borderless)` para funcionar dentro de linhas de `List` sem transformar a
/// linha inteira em botão.
struct WhyButton: View {
    private let topic: String
    private let catalog: ReferenceCatalog

    @State private var isShowingSheet = false

    init(topic: String, catalog: ReferenceCatalog) {
        self.topic = topic
        self.catalog = catalog
    }

    var body: some View {
        if !catalog.references(for: topic).isEmpty {
            Button {
                isShowingSheet = true
            } label: {
                Label("Por quê?", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .accessibilityHint("Mostra a explicação e as referências científicas")
            .sheet(isPresented: $isShowingSheet) {
                WhySheet(topic: topic, catalog: catalog)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview("Botão Por quê?") {
    List {
        HStack {
            Text("Supino reto · 62,5 kg")
            Spacer()
            WhyButton(topic: "note.increase", catalog: WhySheet.previewCatalog)
        }
        HStack {
            Text("Tópico sem referência (botão oculto)")
            Spacer()
            WhyButton(topic: "topic.hrv", catalog: WhySheet.previewCatalog)
        }
    }
}
