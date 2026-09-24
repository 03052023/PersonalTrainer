import SwiftUI
import TrainerCore

/// "O que é RIR?" (SPEC RF-41 b): explicação curta com exemplo, a escala, a equivalência com RPE,
/// a dica "na dúvida, chute para baixo" e as referências do tópico `topic.rir` do catálogo
/// (RF-32). Só lê o `ReferenceCatalog` recebido; catálogo vazio só esconde as referências.
struct RIRExplainerSheet: View {
    private let references: ReferenceCatalog

    @Environment(\.dismiss) private var dismiss

    init(references: ReferenceCatalog) {
        self.references = references
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("RIR quer dizer repetições em reserva: quantas repetições você ainda faria, com boa técnica, ao terminar a série.")
                    Text("Exemplo: o plano pede de 8 a 12 repetições com RIR 2. Você fez 10 e sente que sairiam mais duas, e não uma terceira. Registre 10 repetições e RIR 2.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(Self.scaleRows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label)
                                .monospacedDigit()
                            Spacer(minLength: 8)
                            Text(row.rpe)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("A escala")
                } footer: {
                    Text("RPE é outra escala de esforço, de 1 a 10: RPE = 10 − RIR. RIR 2 é o mesmo que RPE 8.")
                }

                Section("Na dúvida, chute para baixo") {
                    Text("Em média, a estimativa erra por cerca de uma repetição, e acerta mais perto do fim da série. Entre dois números, registre o menor.")
                }

                if let explanation = references.explanations[Self.topic] {
                    Section("Por que parar antes do limite") {
                        Text(explanation)
                    }
                }

                let topicReferences = references.references(for: Self.topic)
                if !topicReferences.isEmpty {
                    Section("Referências") {
                        ForEach(topicReferences) { reference in
                            WhySheet.ReferenceRow(reference: reference)
                        }
                    }
                }
            }
            .navigationTitle("O que é RIR?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Tópico do catálogo de referências com as fontes do RIR (`references.v1.json`).
    static let topic = "topic.rir"

    /// Uma linha da escala: o rótulo do RF-41 (a) e o RPE equivalente (10 − RIR).
    struct ScaleRow: Hashable {
        let label: String
        let rpe: String
    }

    /// A escala do RF-41 (a) com o RPE ao lado, na ordem de `RIRText.scale` (0, 1, 2, 3+).
    static let scaleRows: [ScaleRow] = zip(RIRText.scale, ["RPE 10", "RPE 9", "RPE 8", "RPE 7 ou menos"])
        .map { ScaleRow(label: $0.0, rpe: $0.1) }
}

#Preview("Com referências") {
    RIRExplainerSheet(references: WhySheet.previewCatalog)
}

#Preview("Sem catálogo") {
    RIRExplainerSheet(references: .empty)
}
