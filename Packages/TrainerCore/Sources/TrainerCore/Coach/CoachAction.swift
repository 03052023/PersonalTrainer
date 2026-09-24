import Foundation

/// What the user answered to a coach message (SPEC §7.11, column "Ações").
/// Raw values are persisted in the coach log (`CoachLogEntry.action`): never rename a case.
///
/// Any answer hides the message it was given to; the period inside `CoachMessage.id`
/// decides when the same rule may speak again. `neverAgain` additionally silences the
/// message's `rule` + `itemKey` for good.
public enum CoachAction: String, Codable, CaseIterable, Sendable {
    /// C1 "Ok".
    case ok
    /// C1 "Seguir normal": the app records `DeloadDecisions.dismissedAt`.
    case keepNormal
    /// C2 "Aplicar": the app applies the `ProgramSuggestion` after confirmation.
    case apply
    /// C2 "Agora não".
    case notNow
    /// C2 "Não sugerir mais isto".
    case neverAgain
    /// C3 "Entendi": the same kind waits 3 days.
    case understood
    /// C3 "Lembrar amanhã": the same kind comes back the next calendar day.
    case remindTomorrow
    /// C4 "Como renovar".
    case howToRenew
    /// C5 "Começar".
    case start
    /// C6 "Ver evolução".
    case seeProgress
    /// C7 "Fazer backup".
    case backupNow
    /// C7 "Depois".
    case later
    /// C8 "Feito".
    case done
    /// C8 "Pular".
    case skip

    /// Button label in pt-BR (AGENTS §4: UI text fixed in code, no localization files).
    public var label: String {
        switch self {
        case .ok: return "Ok"
        case .keepNormal: return "Seguir normal"
        case .apply: return "Aplicar"
        case .notNow: return "Agora não"
        case .neverAgain: return "Não sugerir mais isto"
        case .understood: return "Entendi"
        case .remindTomorrow: return "Lembrar amanhã"
        case .howToRenew: return "Como renovar"
        case .start: return "Começar"
        case .seeProgress: return "Ver evolução"
        case .backupNow: return "Fazer backup"
        case .later: return "Depois"
        case .done: return "Feito"
        case .skip: return "Pular"
        }
    }
}
