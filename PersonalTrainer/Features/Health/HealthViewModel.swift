import Foundation
import Observation
import os
import TrainerCore

/// Estado do card "Saúde" e da tela de detalhe (SPEC RF-27..RF-31, §7.10; TASKS T5.3).
///
/// Lê o app Saúde pelo `HealthDataReading` (só leitura, ARCHITECTURE §8) e calcula o relatório com
/// `HealthCalculator`, código puro de `TrainerCore/Health`. Nada aqui alimenta o motor de
/// musculação (SPEC P12, AGENTS R2): o relatório é só contexto na tela.
///
/// - Autorização: nunca pedida no launch (AGENTS §7). `needsAuthorization` começa verdadeiro até o
///   usuário tocar "Conectar ao Saúde"; a flag `healthReadAuthorized` fica em `UserDefaults` porque o
///   HealthKit não revela se a leitura foi concedida (o pedido "dá certo" mesmo quando negado).
/// - Relógio e calendário chegam por injeção (SPEC P11): nada aqui lê a data do sistema.
/// - Perfil manual: se o Saúde não informa data de nascimento ou sexo, `HealthProfileView` grava ano
///   e sexo em `UserDefaults` e o ViewModel mescla esses valores na `UserPhysiology` antes do cálculo.
@Observable
@MainActor
final class HealthViewModel {
    /// Chaves de `UserDefaults`. Estáveis: mudar uma delas apaga o que o usuário já informou.
    enum Keys {
        static let readAuthorized = "healthReadAuthorized"
        static let birthYear = "profileBirthYear"
        static let sex = "profileSex"
        static let maxHeartRate = "profileMaxHeartRate"
        static let dismissedSuggestions = "healthDismissedSuggestions"
    }

    /// Mensagem exibida quando o aparelho não tem o app Saúde (iPad, alguns simuladores).
    static let unavailableMessage = "O app Saúde não está disponível neste aparelho."
    static let readFailedMessage = "Não foi possível ler os dados do app Saúde. Puxe para baixo para tentar de novo."
    static let authorizationFailedMessage = "Não foi possível conectar ao app Saúde. Tente de novo."

    /// Faixa aceita para uma FCmáx informada à mão; fora dela o valor é ignorado (erro de digitação).
    static let maxHeartRateRange = 100...230
    /// Janela do gráfico de VO2máx (SPEC A3: tendência de 90 dias).
    static let vo2MaxWindowDays = 90

    // MARK: Estado exposto

    /// Último relatório calculado. Uma leitura que falha mantém o anterior: é contexto, não
    /// prescrição, e um número de ontem é mais útil que um card vazio.
    private(set) var report: HealthReport?
    private(set) var isLoading = false
    /// Mensagem pt-BR da última falha; `nil` quando a última operação deu certo.
    var errorMessage: String?
    /// Verdadeiro até o usuário conectar ao Saúde por este app (flag `healthReadAuthorized`).
    private(set) var needsAuthorization: Bool
    /// Verdadeiro enquanto o pedido de autorização está aberto (desabilita o botão).
    private(set) var isRequestingAuthorization = false
    /// Medições de VO2máx dos últimos 90 dias, em ordem cronológica, para o gráfico de tendência.
    /// O relatório só traz o resumo; a série vem da última leitura.
    private(set) var vo2MaxHistory: [Vo2MaxSample] = []
    /// Idade/sexo/FCmáx efetivamente usados no último cálculo (Saúde mesclado com o perfil manual).
    private(set) var physiology: UserPhysiology?
    /// O que o app Saúde informou na última leitura, antes da mescla (a tela de perfil mostra a origem).
    private(set) var healthProvidedPhysiology: UserPhysiology?
    /// Momento (relógio injetado) da última leitura bem-sucedida.
    private(set) var lastLoadedAt: Date?

    /// Perfil manual (`UserDefaults`); `nil` = não informado.
    private(set) var profileBirthYear: Int?
    private(set) var profileSex: BiologicalSexValue?
    private(set) var profileMaxHeartRate: Int?

    /// Metas usadas no cálculo; expostas para os textos da tela ("meta de 7 h").
    let targets: HealthTargets
    /// Calendário do usuário, o mesmo do cálculo; as views usam para rotular dias.
    let calendar: Calendar

    // MARK: Dependências

    private let reader: any HealthDataReading
    private let sessionsProvider: @MainActor () -> [SessionSummary]
    private let now: () -> Date
    private let defaults: UserDefaults
    /// Chaves "id|semana" das sugestões dispensadas com "Ok, entendi".
    private var dismissedSuggestionKeys: Set<String>
    /// Última leitura crua do Saúde: permite recalcular ao salvar o perfil sem reler o HealthKit.
    @ObservationIgnored private var lastRawInput: HealthInput?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "HealthViewModel"
    )

    /// - Parameters:
    ///   - reader: fronteira com o HealthKit (`LiveHealthDataReader` no app, `FakeHealthDataReader`
    ///     em previews e testes).
    ///   - sessionsProvider: sessões recentes de musculação (SPEC A5: encaixe do aeróbico longe dos
    ///     dias de inferior). Chamado a cada leitura, no ator principal.
    ///   - defaults: onde ficam a flag de autorização, o perfil manual e as sugestões dispensadas.
    ///     Testes passam uma suite isolada.
    init(
        reader: any HealthDataReading,
        sessionsProvider: @escaping @MainActor () -> [SessionSummary],
        targets: HealthTargets = HealthTargets(),
        now: @escaping () -> Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.reader = reader
        self.sessionsProvider = sessionsProvider
        self.targets = targets
        self.now = now
        self.calendar = calendar
        self.defaults = defaults
        self.needsAuthorization = !defaults.bool(forKey: Keys.readAuthorized)
        self.dismissedSuggestionKeys = Set(defaults.stringArray(forKey: Keys.dismissedSuggestions) ?? [])

        let storedYear = defaults.integer(forKey: Keys.birthYear)
        self.profileBirthYear = storedYear > 0 ? storedYear : nil
        self.profileSex = defaults.string(forKey: Keys.sex).flatMap(BiologicalSexValue.init(rawValue:))
        let storedMaxHeartRate = defaults.integer(forKey: Keys.maxHeartRate)
        self.profileMaxHeartRate = Self.maxHeartRateRange.contains(storedMaxHeartRate) ? storedMaxHeartRate : nil
    }

    // MARK: Derivados para as views

    /// `false` em aparelhos sem o app Saúde: o card mostra o aviso em vez do botão de conectar.
    var isHealthAvailable: Bool {
        reader.isAvailable
    }

    /// Sugestões do relatório menos as dispensadas nesta semana ("Ok, entendi").
    var visibleSuggestions: [HealthSuggestion] {
        guard let report else { return [] }
        return report.suggestions.filter { suggestion in
            !dismissedSuggestionKeys.contains(Self.dismissalKey(for: suggestion, weekStart: report.weekStart))
        }
    }

    /// Ano corrente no calendário do usuário (limites do seletor de ano de nascimento).
    var currentYear: Int {
        calendar.component(.year, from: now())
    }

    // MARK: Ações

    /// Lê o Saúde e recalcula o relatório.
    ///
    /// Sem Saúde no aparelho: só a mensagem. Antes de o usuário conectar: não lê nada (a leitura sem
    /// pedido de autorização falharia e pedir aqui seria pedir no launch). Uma segunda chamada
    /// enquanto a primeira está em andamento é ignorada (pull to refresh durante o `.task`).
    func load() async {
        guard !isLoading else { return }
        guard reader.isAvailable else {
            report = nil
            errorMessage = Self.unavailableMessage
            return
        }
        guard !needsAuthorization else { return }

        isLoading = true
        defer { isLoading = false }

        let referenceDate = now()
        let sessions = sessionsProvider()
        do {
            let input = try await reader.healthInput(
                now: referenceDate,
                calendar: calendar,
                recentSessions: sessions
            )
            lastRawInput = input
            recalculate(from: input, at: referenceDate)
            lastLoadedAt = referenceDate
            errorMessage = nil
        } catch {
            Self.logger.error("Falha ao ler o app Saúde: \(String(describing: error))")
            errorMessage = Self.readFailedMessage
        }
    }

    /// Recarrega só se nunca carregou, se passou `maxAge` ou se o dia mudou. É o que o `.task` do
    /// card chama a cada aparição da Home, para não reler o HealthKit a cada volta de navegação.
    func loadIfStale(maxAge: TimeInterval = 15 * 60) async {
        if let lastLoadedAt {
            let current = now()
            let elapsed = current.timeIntervalSince(lastLoadedAt)
            let isFresh = elapsed >= 0 && elapsed < maxAge && calendar.isDate(lastLoadedAt, inSameDayAs: current)
            if isFresh && errorMessage == nil {
                return
            }
        }
        await load()
    }

    /// Pede leitura ao HealthKit (só por toque do usuário em "Conectar ao Saúde"), grava a flag e
    /// recarrega. Falha mantém `needsAuthorization` e mostra a mensagem.
    func requestAuthorization() async {
        guard !isRequestingAuthorization else { return }
        guard reader.isAvailable else {
            errorMessage = Self.unavailableMessage
            return
        }
        isRequestingAuthorization = true
        do {
            try await reader.requestReadAuthorization()
        } catch {
            isRequestingAuthorization = false
            Self.logger.error("Falha ao pedir autorização de leitura: \(String(describing: error))")
            errorMessage = Self.authorizationFailedMessage
            return
        }
        isRequestingAuthorization = false
        defaults.set(true, forKey: Keys.readAuthorized)
        needsAuthorization = false
        errorMessage = nil
        await load()
    }

    /// Grava o perfil manual e recalcula com a última leitura, sem reler o Saúde.
    /// Valores fora de faixa viram "não informado".
    func saveProfile(birthYear: Int?, sex: BiologicalSexValue?, maxHeartRate: Int?) {
        let latestYear = currentYear
        // Comparação direta em vez de `1900...latestYear`: um relógio injetado absurdo não pode
        // montar um intervalo invertido (trap).
        let validYear = birthYear.flatMap { $0 >= 1900 && $0 <= latestYear ? $0 : nil }
        let validMaxHeartRate = maxHeartRate.flatMap { Self.maxHeartRateRange.contains($0) ? $0 : nil }

        profileBirthYear = validYear
        profileSex = sex
        profileMaxHeartRate = validMaxHeartRate

        if let validYear {
            defaults.set(validYear, forKey: Keys.birthYear)
        } else {
            defaults.removeObject(forKey: Keys.birthYear)
        }
        if let sex {
            defaults.set(sex.rawValue, forKey: Keys.sex)
        } else {
            defaults.removeObject(forKey: Keys.sex)
        }
        if let validMaxHeartRate {
            defaults.set(validMaxHeartRate, forKey: Keys.maxHeartRate)
        } else {
            defaults.removeObject(forKey: Keys.maxHeartRate)
        }

        if let lastRawInput {
            recalculate(from: lastRawInput, at: lastLoadedAt ?? now())
        }
    }

    /// "Ok, entendi": esconde a sugestão até o fim da semana do relatório. Na semana seguinte ela
    /// volta se a condição persistir (as regras de §7.10 são recalculadas a cada leitura).
    func dismiss(_ suggestion: HealthSuggestion) {
        guard let report else { return }
        let weekSuffix = Self.weekSuffix(for: report.weekStart)
        dismissedSuggestionKeys.insert(Self.dismissalKey(for: suggestion, weekStart: report.weekStart))
        // Só as chaves da semana atual interessam; as antigas saem para a lista não crescer sem fim.
        dismissedSuggestionKeys = dismissedSuggestionKeys.filter { $0.hasSuffix(weekSuffix) }
        defaults.set(dismissedSuggestionKeys.sorted(), forKey: Keys.dismissedSuggestions)
    }

    // MARK: Cálculo

    private func recalculate(from rawInput: HealthInput, at referenceDate: Date) {
        let merged = mergedPhysiology(rawInput.physiology)
        let input = HealthInput(
            physiology: merged,
            aerobicWorkouts: rawInput.aerobicWorkouts,
            recovery: rawInput.recovery,
            steps: rawInput.steps,
            vo2Max: rawInput.vo2Max,
            recentSessions: rawInput.recentSessions
        )
        healthProvidedPhysiology = rawInput.physiology
        physiology = merged
        vo2MaxHistory = Self.recentVo2Max(rawInput.vo2Max, now: referenceDate, calendar: calendar)
        report = HealthCalculator.report(input: input, targets: targets, now: referenceDate, calendar: calendar)
    }

    /// O Saúde tem prioridade para data de nascimento e sexo (dado do sistema, mais preciso que um
    /// ano); o perfil só preenche o que falta. A FCmáx informada vence: o Saúde não fornece esse
    /// valor e o usuário só a informa quando mediu (SPEC A1: "salvo valor informado").
    private func mergedPhysiology(_ health: UserPhysiology) -> UserPhysiology {
        UserPhysiology(
            birthDate: health.birthDate ?? profileBirthDate,
            sex: health.sex ?? profileSex,
            maxHeartRateOverride: profileMaxHeartRate ?? health.maxHeartRateOverride
        )
    }

    /// Só o ano é informado: 1º de julho minimiza o erro máximo da idade calculada (± 6 meses).
    private var profileBirthDate: Date? {
        guard let profileBirthYear else { return nil }
        return calendar.date(from: DateComponents(year: profileBirthYear, month: 7, day: 1))
    }

    private static func recentVo2Max(_ samples: [Vo2MaxSample], now: Date, calendar: Calendar) -> [Vo2MaxSample] {
        let windowStart = calendar.date(byAdding: .day, value: -vo2MaxWindowDays, to: now) ?? now
        return samples
            .filter { $0.date >= windowStart && $0.date <= now }
            .sorted { $0.date < $1.date }
    }

    private static func weekSuffix(for weekStart: Date) -> String {
        "|\(Int(weekStart.timeIntervalSince1970))"
    }

    private static func dismissalKey(for suggestion: HealthSuggestion, weekStart: Date) -> String {
        suggestion.id + weekSuffix(for: weekStart)
    }
}
