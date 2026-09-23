import SwiftUI

/// Seletor de RIR da série (SPEC RF-03, §7.1): segmentos "—", 0…5, onde "—" é `nil`
/// (não informado). Só RIR é armazenado; RPE, quando exibido, é derivado (10 − RIR).
struct RIRPicker: View {
    @Binding var selection: Int?

    init(selection: Binding<Int?>) {
        self._selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RIR (reps que sobraram)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Tags tipadas como `Int?` para casarem com a seleção opcional: `nil` seleciona "—".
            Picker("RIR (reps que sobraram)", selection: $selection) {
                Text("—").tag(Int?.none)
                ForEach(0...5, id: \.self) { value in
                    Text(String(value)).tag(Int?.some(value))
                }
            }
            .pickerStyle(.segmented)
        }
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
