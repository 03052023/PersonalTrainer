import SwiftUI
import TrainerCore

/// Seletor de RIR da série (SPEC RF-03, §7.1, RF-41): segmentos "—", 0…5, onde "—" é `nil`
/// (não informado). Só RIR é armazenado; RPE, quando exibido, é derivado (10 − RIR).
///
/// RF-41: abaixo dos segmentos aparece o significado do valor escolhido ("2 · mais duas"), e o
/// botão "O que é RIR?", ao lado do título, abre a `RIRExplainerSheet`. Os segmentos continuam de
/// 0 a 5 (RF-03): P4 compara o RIR com T + 2, então 4 e 5 precisam existir; 3, 4 e 5 leem
/// "com folga".
struct RIRPicker: View {
    @Binding var selection: Int?
    private let references: ReferenceCatalog

    @State private var isShowingExplainer = false

    init(selection: Binding<Int?>, references: ReferenceCatalog = .empty) {
        self._selection = selection
        self.references = references
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Com Dynamic Type grande, título e botão não cabem lado a lado: o botão desce.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 8)
                    explainerButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    explainerButton
                }
            }

            // Tags tipadas como `Int?` para casarem com a seleção opcional: `nil` seleciona "—".
            Picker("RIR", selection: $selection) {
                Text("—")
                    .accessibilityLabel(RIRText.spokenOption(nil))
                    .tag(Int?.none)
                ForEach(0...5, id: \.self) { value in
                    Text(String(value))
                        .accessibilityLabel(RIRText.spokenOption(value))
                        .tag(Int?.some(value))
                }
            }
            .pickerStyle(.segmented)

            Text(RIRText.meaning(for: selection))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .sheet(isPresented: $isShowingExplainer) {
            RIRExplainerSheet(references: references)
                .presentationDetents([.medium, .large])
        }
    }

    private var title: some View {
        Text("RIR (repetições em reserva)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var explainerButton: some View {
        Button {
            isShowingExplainer = true
        } label: {
            Label("O que é RIR?", systemImage: "questionmark.circle")
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
        .accessibilityHint("Mostra a escala, um exemplo e as referências")
    }
}

// MARK: - Previews

private struct RIRPickerPreviewHost: View {
    @State private var selection: Int?

    init(selection: Int?) {
        self._selection = State(initialValue: selection)
    }

    var body: some View {
        RIRPicker(selection: $selection)
            .padding()
    }
}

#Preview("RIR 2") {
    RIRPickerPreviewHost(selection: 2)
}

#Preview("Não informado") {
    RIRPickerPreviewHost(selection: nil)
}

#Preview("Dynamic Type AX5") {
    RIRPickerPreviewHost(selection: 0)
        .dynamicTypeSize(.accessibility5)
}
