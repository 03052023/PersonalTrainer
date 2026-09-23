import SwiftUI

@MainActor
struct HealthProbeView: View {
    @State private var model: HealthProbeModel

    init(model: HealthProbeModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Teste de instalação e leitura", systemImage: "heart.text.square")
                    .font(.headline)

                Text("Consulta da última frequência cardíaca salva nas últimas 24 horas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                status
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.phase != .unavailable {
                    Button {
                        Task {
                            await model.read(now: Date())
                        }
                    } label: {
                        Text(model.hasRequestedAccess ? "Ler FC novamente" : "Autorizar e ler FC")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading)
                }

                Divider()

                Text("Para obter uma amostra recente, use o app Treino da Apple no relógio. Depois volte a este teste e toque para ler novamente. A sincronização com o iPhone pode demorar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Este teste não mede FC ao vivo nem grava treinos. Uma amostra com data confirma somente a leitura do Saúde neste aparelho.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        #if os(watchOS)
        "Teste no Watch"
        #else
        "Teste no iPhone"
        #endif
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle:
            Text("Toque no botão para solicitar acesso à frequência cardíaca no Saúde.")
        case .loading:
            ProgressView("Aguardando Saúde…")
        case .reading(let reading):
            VStack(alignment: .leading, spacing: 8) {
                Text("Amostra lida do Saúde")
                    .font(.headline)
                Text("\(reading.beatsPerMinute, format: .number.precision(.fractionLength(0))) bpm")
                    .font(.title2.bold())
                Text("Data da amostra")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reading.sampledAt, format: .dateTime.day().month().year().hour().minute().second())
                    .font(.subheadline)
                Text("É um registro salvo, não uma medição ao vivo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .empty:
            VStack(alignment: .leading, spacing: 8) {
                Text("Nenhuma amostra disponível")
                    .font(.headline)
                Text("Pode não haver dados nas últimas 24 horas ou a leitura pode estar desativada. Confira a permissão de frequência cardíaca deste app nos ajustes do Saúde.")
                Text("Por privacidade, o Saúde não informa ao app se a leitura foi recusada.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            Text("O HealthKit não está disponível neste ambiente. Faça este teste no iPhone ou Apple Watch físico.")
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Text("Não foi possível concluir o teste")
                    .font(.headline)
                Text(errorMessage(error))
            }
        }
    }

    private func errorMessage(_ error: HealthProbeError) -> String {
        switch error {
        case .unavailable:
            return "O HealthKit não está disponível neste aparelho."
        case .authorizationFailed(let code):
            return "A solicitação ao Saúde falhou. Confira as permissões e tente novamente." + codeMessage(code)
        case .readFailed(let code):
            return "A consulta ao Saúde falhou. Desbloqueie o aparelho e tente novamente." + codeMessage(code)
        case .unexpected:
            return "Ocorreu um erro inesperado. Feche e abra o app para tentar novamente."
        }
    }

    private func codeMessage(_ code: Int?) -> String {
        guard let code else { return "" }
        return " Código: \(code)."
    }
}

#Preview("Dados simulados") {
    NavigationStack {
        HealthProbeView(model: HealthProbeModel(service: FakeHealthProbeService()))
    }
}

#Preview("HealthKit indisponível") {
    NavigationStack {
        HealthProbeView(model: HealthProbeModel(
            service: FakeHealthProbeService(scenario: .unavailable)
        ))
    }
}