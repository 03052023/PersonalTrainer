import Foundation
import TrainerCore

/// Ajustes que mudam o planejamento (SPEC RF-39, §7.5 b e RF-42), lidos a cada plano.
///
/// O `SessionPlanner` recebe uma closure que devolve este valor; no app ela lê
/// `UserDefaults.standard` com `load(from:)`, e os testes passam valores fixos. As chaves são
/// as mesmas que o Ajustes grava (docs/V2-FINAL-CONTRACT.md §2): mudar uma delas quebra o que
/// a pessoa já escolheu.
struct PlannerSettings: Sendable, Hashable {
    /// Seletor por frequência (SPEC RF-39, S5–S7). Os raw values são as strings gravadas em
    /// `UserDefaults`; servem também para `@AppStorage` no Ajustes. Nunca renomear um case.
    enum FrequencySelectorMode: String, Sendable, Hashable, CaseIterable {
        /// Padrão: ligado quando o programa ativo tem pelo menos
        /// `PlannerSettings.autoFrequencyMinimumDays` dias.
        case auto
        case on
        case off
    }

    /// `String`: `"auto"`, `"on"` ou `"off"`. Ausente ou desconhecido vale `"auto"`.
    static let frequencySelectorKey = "plannerFrequencySelector"
    /// `Int`: semanas entre semanas leves (SPEC §7.5 b). Ausente vale 6; 0 desliga (b).
    static let deloadWeeksKey = "plannerDeloadWeeks"
    /// `Bool`: modo casa (SPEC RF-42, §7.13; docs/V21-CONTRACT.md B1). Ausente vale `false`. A Home
    /// (interruptor "Em casa") e o Ajustes ("Treinar em casa") gravam a mesma chave.
    static let homeModeKey = "homeModeEnabled"
    /// SPEC RF-39: "padrão: ligado quando o programa tem ≥ 4 dias".
    static let autoFrequencyMinimumDays = 4
    /// SPEC §7.5 (b): "a cada N semanas de treino (padrão 6)".
    static let defaultDeloadWeeks = DeloadPolicy.defaultWeeksBetweenDeloads

    var frequencySelector: FrequencySelectorMode
    /// N de SPEC §7.5 (b). Zero ou negativo desliga o gatilho por tempo; (a) e (c) continuam.
    var deloadWeeks: Int
    /// SPEC RF-42: ligado, o plano troca cada exercício pelo equivalente de casa (§7.13 H1–H4) e o
    /// "Trocar" da sessão oferece só alternativas de casa. O programa não muda.
    var homeModeEnabled: Bool

    init(
        frequencySelector: FrequencySelectorMode = .auto,
        deloadWeeks: Int = PlannerSettings.defaultDeloadWeeks,
        homeModeEnabled: Bool = false
    ) {
        self.frequencySelector = frequencySelector
        self.deloadWeeks = deloadWeeks
        self.homeModeEnabled = homeModeEnabled
    }

    /// Lê as três chaves. `integer(forKey:)` devolve 0 para chave ausente, o que desligaria (b)
    /// em quem nunca abriu o Ajustes; por isso a ausência é conferida antes. Um valor negativo
    /// gravado por engano vira 0 (desligado), o mesmo efeito que `DeloadScheduler` já daria.
    static func load(from defaults: UserDefaults) -> PlannerSettings {
        let mode = defaults.string(forKey: frequencySelectorKey)
            .flatMap { FrequencySelectorMode(rawValue: $0) } ?? .auto
        let weeks: Int
        if defaults.object(forKey: deloadWeeksKey) == nil {
            weeks = defaultDeloadWeeks
        } else {
            weeks = max(0, defaults.integer(forKey: deloadWeeksKey))
        }
        // `bool(forKey:)` devolve `false` para chave ausente, que é o padrão do modo casa.
        let homeMode = defaults.bool(forKey: homeModeKey)
        return PlannerSettings(frequencySelector: mode, deloadWeeks: weeks, homeModeEnabled: homeMode)
    }

    /// `true` quando o próximo dia sai do `FrequencyAwareSelector` (S5–S7) em vez da rotação.
    func usesFrequencySelector(programDayCount: Int) -> Bool {
        switch frequencySelector {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            return programDayCount >= Self.autoFrequencyMinimumDays
        }
    }
}
