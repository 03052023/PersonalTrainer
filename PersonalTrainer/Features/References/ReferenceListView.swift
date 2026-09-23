import SwiftUI
import TrainerCore

/// Lista de todas as referências científicas do app (SPEC RF-32, §7.9), agrupadas por nível de
/// evidência, do mais forte ao mais fraco. Aberta a partir de Ajustes ("Sobre/Referências");
/// não cria `NavigationStack` próprio porque é empurrada na pilha de quem a apresenta.
struct ReferenceListView: View {
    private let catalog: ReferenceCatalog

    init(catalog: ReferenceCatalog) {
        self.catalog = catalog
    }

    var body: some View {
        List {
            Section {
                Text("Toda regra, meta e sugestão do app cita as fontes abaixo. Diretrizes, consensos e meta-análises vêm primeiro; estudos isolados só entram quando não há síntese e aparecem como evidência limitada.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if catalog.references.isEmpty {
                Section {
                    Text("O catálogo de referências não pôde ser carregado.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(levels, id: \.self) { level in
                    let levelReferences = references(at: level)
                    Section {
                        ForEach(levelReferences) { reference in
                            WhySheet.ReferenceRow(reference: reference)
                        }
                    } header: {
                        Text(verbatim: "\(level.displayName) (\(levelReferences.count))")
                    }
                }
            }
        }
        .navigationTitle("Referências")
    }

    /// Níveis com ao menos uma referência, na ordem de `EvidenceLevel.allCases` (mais forte primeiro).
    private var levels: [ScientificReference.EvidenceLevel] {
        ScientificReference.EvidenceLevel.allCases.filter { level in
            catalog.references.contains { $0.level == level }
        }
    }

    /// Referências de um nível, das mais recentes para as mais antigas; empate por autores.
    private func references(at level: ScientificReference.EvidenceLevel) -> [ScientificReference] {
        catalog.references
            .filter { $0.level == level }
            .sorted { lhs, rhs in
                if lhs.year != rhs.year {
                    return lhs.year > rhs.year
                }
                return lhs.authors < rhs.authors
            }
    }
}

#Preview("Referências") {
    NavigationStack {
        ReferenceListView(catalog: WhySheet.previewCatalog)
    }
}

#Preview("Referências — catálogo vazio") {
    NavigationStack {
        ReferenceListView(catalog: .empty)
    }
}
