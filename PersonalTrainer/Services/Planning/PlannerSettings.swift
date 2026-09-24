import Foundation
import TrainerCore

/// Ajustes que mudam o planejamento (SPEC RF-39 e §7.5 b), lidos a cada plano.
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
    /// SPEC RF-39: "padrão: ligado quando o programa tem ≥ 4 dias".
    static let autoFrequencyMinimumDays = 4
    /// SPEC §7.5 (b): "a cada N semanas de treino (padrão 6)".
    static let defaultDeloadWeeks = DeloadPolicy.defaultWeeksBetweenDeloads

    var frequencySelector: FrequencySelectorMode
    /// N de SPEC §7.5 (b). Zero ou negativo desliga o gatilho por tempo; (a) e (c) continuam.
    var deloadWeeks: Int

    init(
        frequencySelector: FrequencySelectorMode = .auto,
        deloadWeeks: Int = PlannerSettings.defaultDeloadWeeks
    ) {
        self.frequencySelector = frequencySelector
        self.deloadWeeks = deloadWeeks
    }

    /// Lê as duas chaves. `integer(forKey:)` devolve 0 para chave ausente, o que desligaria (b)
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
        return PlannerSettings(frequencySelector: mode, deloadWeeks: weeks)
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
