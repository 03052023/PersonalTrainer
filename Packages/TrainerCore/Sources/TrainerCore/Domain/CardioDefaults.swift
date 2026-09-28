import Foundation

/// Padrões de um aeróbico novo num dia do plano (SPEC §7.14 F1–F3, RF-48; docs/V23-CORE-CONTRACT.md
/// §2.1). Os aeróbicos medem em minutos (`ExerciseMeasure.minutes`) e não seguem a tabela de
/// repetições do objetivo (§7.9): um exercício novo com padrão `cardio` na edição do plano recebe
/// estes valores, e trocar o objetivo com padrões não os reescreve.
public enum CardioDefaults {
    /// Faixa de minutos de uma sessão contínua: 20 min é um começo possível e 40 min fica perto da
    /// sessão moderada que, 3 a 5 vezes por semana, soma os 150 min da OMS (SPEC §7.14 F2).
    public static let minutes: ClosedRange<Int> = 20...40
    /// Uma série: a sessão contínua é um bloco só (SPEC §7.14 F1).
    public static let sets: Int = 1
    /// Descanso entre séries, em segundos: só vale se a pessoa acrescentar séries (intervalos).
    public static let restSeconds: Int = 60
}
