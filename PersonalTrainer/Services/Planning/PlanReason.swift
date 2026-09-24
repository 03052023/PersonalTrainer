import Foundation
import TrainerCore

/// Por que o planejador propôs este treino (TASKS CA4-5). A Home transforma isto numa linha de
/// texto ("Pernas: abaixo da meta semanal", "Semana leve"); aqui fica só o dado, sem texto de UI.
///
/// Prioridade em `nextPlan`: semana leve > frequência > sequência. `plan(forDayID:)` sempre
/// devolve `.manual`; se esse plano for de semana leve, `SessionPlan.isDeload` diz.
enum PlanReason: Sendable, Hashable {
    /// SPEC S2: o dia seguinte da sequência (seletor por frequência desligado, ou ligado sem
    /// nenhum grupo do dia escolhido abaixo da meta semanal).
    case rotation
    /// SPEC S4: o dia foi escolhido pela pessoa.
    case manual
    /// SPEC S5–S7: o dia escolhido treina `muscle`, que tem `done` sessões na semana contra a
    /// meta `target` (`done < target`). Entre os grupos do dia abaixo da meta vale o de maior
    /// diferença; empate segue a ordem de `MuscleGroup.allCases` (SPEC §7.4).
    case frequency(muscle: MuscleGroup, done: Int, target: Int)
    /// SPEC §7.5: semana leve. O gatilho vem enquanto ela está programada e nenhuma sessão
    /// leve começou (`DeloadStatus.pending`); durante a passagem (`.active`) é `nil`.
    case deload(DeloadTrigger?)
}
