import SwiftUI
import TrainerCore

/// Tela de detalhe de saúde (SPEC RF-27..RF-31, §7.10): semana aeróbica, VO2máx, recuperação,
/// passos e sugestões, cada bloco com o "Por quê?" do seu tópico (RF-32).
///
/// Tudo é só leitura do app Saúde e só contexto: nada aqui muda a musculação (SPEC P12). Os
/// alertas de recuperação usam linguagem cuidadosa (sinal para observar, não diagnóstico).
struct HealthDetailView: View {
    private typealias Format = HealthCardView.Format

    private let model: HealthViewModel
    private let references: ReferenceCatalog

    init(model: HealthViewModel, references: ReferenceCatalog) {
        self.model = model
        self.references = references
    }

    var body: some View {
        List {
            if !model.isHealthAvailable {
                Section {
                    Text(HealthViewModel.unavailableMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                if let message = model.errorMessage {
                    errorSection(message)
                }
                if let report = model.report {
                    aerobicSection(report.aerobic)
                    vo2MaxSection(report.vo2Max)
                    recoverySection(report.recovery)
                    stepsSection(report.steps)
                    suggestionsSection
                } else if model.needsAuthorization {
                    connectSection
                } else if model.isLoading || model.errorMessage == nil {
                    // Sem relatório e sem erro: a primeira leitura ainda não terminou.
                    loadingSection
                } else {
                    emptySection
                }
            }
            footerSection
        }
        .navigationTitle("Saúde")
        // Fechamentos isolados ao MainActor capturando só o ViewModel, como na HomeView.
        .refreshable { @MainActor [model] in
            await model.load()
        }
        .task { @MainActor [model] in
            await model.loadIfStale()
        }
    }

    // MARK: - Semana aeróbica (RF-27, A1–A2)

    private func aerobicSection(_ aerobic: AerobicWeekSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(Format.aerobicHeadline(aerobic))
                    .font(.headline)
                ProgressView(
                    value: Format.clampedProgress(aerobic.moderateEquivalentMinutes, of: aerobic.target),
                    total: 1
                )
                .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline) {
                    Text("Moderado \(Format.integer(aerobic.moderateMinutes)) min · Vigoroso \(Format.integer(aerobic.vigorousMinutes)) min")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    WhyButton(topic: "topic.aerobic", catalog: references)
                }
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 4)

            AerobicWeekChart(summary: aerobic, calendar: model.calendar)
                .padding(.vertical, 4)
        } header: {
            Text("Semana aeróbica")
        } footer: {
            Text("Meta semanal: \(Format.integer(aerobic.target)) min moderados-equivalentes (a OMS recomenda de 150 a 300). 1 min vigoroso conta como 2. Os treinos vêm do app Exercício do Apple Watch ou de qualquer app que grave no Saúde.")
        }
    }

    // MARK: - VO2máx (RF-28, A3)

    private func vo2MaxSection(_ vo2Max: Vo2MaxSummary?) -> some View {
        Section {
            if let vo2Max {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Format.decimal(vo2Max.latest)) mL/kg/min")
                            .font(.title3.weight(.semibold))
                        Text("Medido em \(Format.date(vo2Max.latestDate, calendar: model.calendar))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    WhyButton(topic: "topic.vo2max", catalog: references)
                }
                .buttonStyle(.borderless)

                LabeledContent("Faixa") {
                    Text(bandText(vo2Max))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Variação em 90 dias") {
                    Text(changeText(vo2Max.change90Days))
                }
                Vo2MaxTrendChart(samples: model.vo2MaxHistory, calendar: model.calendar)
                    .padding(.vertical, 4)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sem estimativa de VO2máx no app Saúde.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    WhyButton(topic: "topic.vo2max", catalog: references)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("VO2máx")
        } footer: {
            Text("O Apple Watch estima o VO2máx em caminhadas, corridas e trilhas ao ar livre registradas no app Exercício, usando GPS e frequência cardíaca. Sem essas atividades, o valor fica desatualizado.")
        }
    }

    private func bandText(_ vo2Max: Vo2MaxSummary) -> String {
        if let band = vo2Max.band {
            if let age = vo2Max.ageYears {
                return "\(band.displayName) para \(age) anos"
            }
            return band.displayName
        }
        let physiology = model.physiology
        if physiology?.birthDate == nil || physiology?.sex == nil {
            return "Informe idade e sexo no perfil"
        }
        return "Sem tabela de referência para este perfil"
    }

    private func changeText(_ change: Double?) -> String {
        guard let change else { return "Medições insuficientes" }
        return "\(Format.signedDecimal(change)) mL/kg/min"
    }

    // MARK: - Recuperação (RF-29, A4)

    private func recoverySection(_ recovery: RecoverySummary) -> some View {
        Section {
            comparisonRow(
                title: "HRV (SDNN)",
                unit: "ms",
                recent: recovery.hrv7,
                baseline: recovery.hrv28,
                fractionDigits: 0,
                topic: "topic.hrv"
            )
            comparisonRow(
                title: "FC de repouso",
                unit: "bpm",
                recent: recovery.restingHR7,
                baseline: recovery.restingHR28,
                fractionDigits: 0,
                topic: nil
            )
            comparisonRow(
                title: "Sono",
                unit: "h",
                recent: recovery.sleep7,
                baseline: recovery.sleep28,
                fractionDigits: 1,
                topic: "topic.sleep"
            )
            LabeledContent("Noites com dados (7 dias)") {
                Text("\(recovery.nightsWithData7) de 7")
            }
            ForEach(recovery.alerts, id: \.self) { alert in
                alertRow(alert, recovery: recovery)
            }
        } header: {
            Text("Recuperação")
        } footer: {
            Text("Média dos últimos 7 dias comparada à das últimas 4 semanas. HRV, FC de repouso e sono ficam mais completos quando você dorme com o Apple Watch.")
        }
    }

    private func comparisonRow(
        title: String,
        unit: String,
        recent: Double?,
        baseline: Double?,
        fractionDigits: Int,
        topic: String?
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("7 dias: \(valueText(recent, unit: unit, fractionDigits: fractionDigits)) · 28 dias: \(valueText(baseline, unit: unit, fractionDigits: fractionDigits))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let topic {
                WhyButton(topic: topic, catalog: references)
            }
        }
        .buttonStyle(.borderless)
    }

    private func valueText(_ value: Double?, unit: String, fractionDigits: Int) -> String {
        guard let value else { return "sem dados" }
        return "\(Format.decimal(value, maxFractionDigits: fractionDigits)) \(unit)"
    }

    private func alertRow(_ alert: RecoveryAlert, recovery: RecoverySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(alertTitle(alert, recovery: recovery))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            Text(alertDetail(alert))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.yellow.opacity(0.15))
    }

    /// Título com os números que geraram o alerta (SPEC A6).
    private func alertTitle(_ alert: RecoveryAlert, recovery: RecoverySummary) -> String {
        switch alert {
        case .hrvDrop:
            if let recent = recovery.hrv7, let baseline = recovery.hrv28, baseline > 0 {
                let drop = (1 - recent / baseline) * 100
                return "HRV \(Format.decimal(drop, maxFractionDigits: 0)) % abaixo da sua média de 4 semanas"
            }
            return "HRV abaixo da sua média de 4 semanas"
        case .restingHeartRateRise:
            if let recent = recovery.restingHR7, let baseline = recovery.restingHR28 {
                return "FC de repouso \(Format.decimal(recent - baseline, maxFractionDigits: 0)) bpm acima da sua média de 4 semanas"
            }
            return "FC de repouso acima da sua média de 4 semanas"
        case .lowSleep:
            let target = Format.decimal(model.targets.sleepHours)
            if let sleep = recovery.sleep7 {
                return "Média de \(Format.decimal(sleep)) h de sono nos últimos 7 dias (meta: \(target) h)"
            }
            return "Sono abaixo da meta de \(target) h nos últimos 7 dias"
        }
    }

    private func alertDetail(_ alert: RecoveryAlert) -> String {
        switch alert {
        case .hrvDrop, .restingHeartRateRise:
            return "Costuma acompanhar noites mal dormidas, estresse, álcool ou o começo de uma gripe. É um sinal para observar, não um diagnóstico, e não muda a carga da musculação."
        case .lowSleep:
            return "Dormir de 7 a 9 horas ajuda a recuperação. É um sinal para observar e não muda a carga da musculação."
        }
    }

    // MARK: - Passos

    private func stepsSection(_ steps: StepsSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let average = steps.average7 {
                    Text("\(Format.integer(average)) passos por dia")
                        .font(.headline)
                    ProgressView(value: Format.clampedProgress(average, of: steps.target), total: 1)
                        .accessibilityHidden(true)
                } else {
                    Text("Sem dados de passos nos últimos 7 dias")
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Meta: \(Format.integer(steps.target)) por dia")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    WhyButton(topic: "topic.steps", catalog: references)
                }
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
        } header: {
            Text("Passos")
        } footer: {
            Text("Média diária dos últimos 7 dias, contada pelo iPhone e pelo Apple Watch.")
        }
    }

    // MARK: - Sugestões (A3–A5)

    private var suggestionsSection: some View {
        Section {
            let suggestions = model.visibleSuggestions
            if suggestions.isEmpty {
                Text("Nada a sugerir agora.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(suggestions) { suggestion in
                    HealthSuggestionRow(
                        suggestion: suggestion,
                        references: references,
                        onDismiss: { [model] in
                            model.dismiss(suggestion)
                        }
                    )
                }
            }
        } header: {
            Text("Sugestões")
        }
    }

    // MARK: - Estados sem relatório

    private func errorSection(_ message: String) -> some View {
        Section {
            Label {
                Text(message)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var connectSection: some View {
        Section {
            Text("Conecte ao app Saúde para ver aeróbico, VO2máx, sono e recuperação.")
                .foregroundStyle(.secondary)
            Button("Conectar ao Saúde") {
                Task { @MainActor [model] in
                    await model.requestAuthorization()
                }
            }
            .disabled(model.isRequestingAuthorization)
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 8) {
                ProgressView()
                Text("Lendo o app Saúde…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView(
                "Sem dados do app Saúde",
                systemImage: "heart.text.square",
                description: Text("Puxe para baixo para tentar de novo.")
            )
        }
    }

    // MARK: - Rodapé

    private var footerSection: some View {
        Section {
            NavigationLink {
                HealthProfileView(model: model)
            } label: {
                Label("Idade, sexo e FCmáx", systemImage: "person.crop.circle")
            }
        } footer: {
            Text("Estes dados só servem de contexto; nunca mudam a carga da musculação. Se algo não aparece, confira as permissões no app Saúde: toque na sua foto › Apps › Magister.")
        }
    }
}
