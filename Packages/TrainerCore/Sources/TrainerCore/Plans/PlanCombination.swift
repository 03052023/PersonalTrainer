import Foundation

/// A tabela de consequências de combinar dois objetivos (SPEC §7.15 M7; owner notes itens 10–12). Determinística:
/// cada par de objetivos diferentes tem uma lista fixa, na ordem da SPEC, que não depende da ordem dos
/// argumentos. Frases de até 90 caracteres, em pt-BR, cada uma com o tópico do "Por quê?" no
/// `references.v1.json`. Nada aqui usa frequência cardíaca nem muda a prescrição (P12).
public enum PlanCombination {
    /// As consequências de ter `first` e `second` ativos ao mesmo tempo. Vazio para o mesmo objetivo.
    public static func consequences(_ first: ProgramGoal, _ second: ProgramGoal) -> [PlanConsequence] {
        guard first != second else {
            return []
        }
        let pair: Set<ProgramGoal> = [first, second]
        return rows.first { $0.goals == pair }?.consequences ?? []
    }

    /// Grande sobreposição (Hipertrofia + Força e Força + Combate): os dois planos treinam quase os mesmos
    /// levantamentos, e o app sugere um plano só ou um formato.
    public static func isLargeOverlap(_ first: ProgramGoal, _ second: ProgramGoal) -> Bool {
        guard first != second else {
            return false
        }
        let pair: Set<ProgramGoal> = [first, second]
        return pair == [.hypertrophy, .strength] || pair == [.strength, .combat]
    }

    /// Uma linha da tabela M7.
    struct Row: Sendable {
        let goals: Set<ProgramGoal>
        let consequences: [PlanConsequence]
    }

    /// A tabela M7 da SPEC, par a par, com as frases na ordem dela.
    static var rows: [Row] {
        [
            Row(goals: [.hypertrophy, .strength], consequences: [
                neutral("Os dois treinam quase os mesmos levantamentos.", "topic.combination"),
                positive("Força máxima e massa muscular juntas, com cargas altas e moderadas.", "topic.load"),
                negative("Mais séries para os mesmos músculos: a recuperação fica mais difícil.", "topic.volume"),
            ]),
            Row(goals: [.hypertrophy, .combat], consequences: [
                positive("Potência, pegada e condicionamento somam-se ao ganho de massa.", "goal.combat"),
                neutral("Parte dos exercícios de força se repete nos dois planos.", "topic.combination"),
                negative("Semana mais longa, com mais cansaço.", "topic.combination"),
            ]),
            Row(goals: [.hypertrophy, .longevity], consequences: [
                positive("Equilíbrio e mobilidade entram na semana.", "goal.longevity"),
                neutral("Pouco conflito: os dois usam cargas moderadas.", "topic.combination"),
                negative("Mais dias de treino na semana.", "topic.weekFit"),
            ]),
            Row(goals: [.hypertrophy, .endurance], consequences: [
                positive("Coração mais forte e VO2máx maior.", "topic.vo2max"),
                positive("Recuperação mais rápida entre as séries.", "topic.combination"),
                neutral("Ganho de músculo quase igual, com o cardio separado ou moderado.", "topic.concurrent"),
                negative("Semana mais longa e mais cansaço.", "topic.weekFit"),
                negative("Intervalos fortes na véspera de pernas atrapalham; o encaixe evita.", "topic.concurrent"),
            ]),
            Row(goals: [.strength, .combat], consequences: [
                neutral("Os dois usam a mesma base de força máxima, com 3 a 6 repetições.", "goal.combat"),
                positive("O Combate soma potência, pegada e condicionamento.", "goal.combat"),
                negative("Muito volume nos grandes levantamentos: a recuperação pesa.", "topic.volume"),
            ]),
            Row(goals: [.strength, .longevity], consequences: [
                positive("Equilíbrio e mobilidade entram na semana.", "goal.longevity"),
                neutral("Pouco conflito entre os dois.", "topic.combination"),
                negative("Mais dias de treino na semana.", "topic.weekFit"),
            ]),
            Row(goals: [.strength, .endurance], consequences: [
                positive("Mais condicionamento e coração mais forte.", "topic.vo2max"),
                neutral("Força máxima pouco afetada, com as sessões separadas.", "topic.concurrent"),
                negative("A força explosiva pode cair um pouco com cardio forte no mesmo dia.", "topic.concurrent"),
            ]),
            Row(goals: [.combat, .longevity], consequences: [
                positive("Equilíbrio e mobilidade ajudam a base do Combate.", "goal.longevity"),
                neutral("Pouco conflito entre os dois.", "topic.combination"),
                negative("Mais dias de treino na semana.", "topic.weekFit"),
            ]),
            Row(goals: [.combat, .endurance], consequences: [
                positive("Mais fôlego para esforços longos e curtos.", "topic.cardio"),
                neutral("O Combate já tem condicionamento; o Cardio acrescenta a base aeróbica.", "topic.cardio"),
                negative("Muito esforço forte na semana: o descanso pesa mais.", "topic.combination"),
                negative("A força explosiva pode cair um pouco com cardio forte no mesmo dia.", "topic.concurrent"),
            ]),
            Row(goals: [.longevity, .endurance], consequences: [
                positive("Coração mais forte, somado ao equilíbrio e à mobilidade.", "topic.vo2max"),
                neutral("Pouco conflito: os dois combinam bem.", "topic.combination"),
                negative("Mais dias de atividade na semana.", "topic.weekFit"),
            ]),
        ]
    }

    private static func positive(_ text: String, _ topic: String) -> PlanConsequence {
        PlanConsequence(kind: .positive, text: text, referenceTopic: topic)
    }

    private static func neutral(_ text: String, _ topic: String) -> PlanConsequence {
        PlanConsequence(kind: .neutral, text: text, referenceTopic: topic)
    }

    private static func negative(_ text: String, _ topic: String) -> PlanConsequence {
        PlanConsequence(kind: .negative, text: text, referenceTopic: topic)
    }
}
