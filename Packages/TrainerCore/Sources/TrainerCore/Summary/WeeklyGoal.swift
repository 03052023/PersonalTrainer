import Foundation

/// Uma linha da tela "Metas da semana" (SPEC RF-52, §7.16; docs/V23-UI-CONTRACT.md §4.3): um número
/// feito contra uma meta, com a marca de tinta (W3) e o "Por quê?" (W5). Puro; a view só formata e
/// desenha (§7.16 W6: nada aqui muda o plano nem a prescrição).
public struct WeeklyGoal: Sendable, Hashable {
    public let kind: WeeklyGoalKind
    /// Só em `planSessions`: de qual plano é a linha, para a cor da `InkMarkView` (DESIGN §9.2) e para
    /// abrir "Retomar"/"Ver a sessão" do plano certo, se a tela precisar.
    public let programID: UUID?
    /// Só em `planSessions`: o objetivo do plano, para o nome da linha e a cor.
    public let planGoal: ProgramGoal?
    /// `nil` = sem dados (W4): o app Saúde não está conectado, ou o aparelho não informa esta métrica.
    /// Nunca `nil` em `planSessions`, `muscles`, `balance` e `mobility`, que não dependem do Saúde.
    public let done: Double?
    /// Sempre > 0.
    public let target: Double
    /// Tópico do "Por quê?" (W5): `goal.*` nas sessões e no equilíbrio/mobilidade, `topic.frequency`
    /// nos músculos, `topic.aerobic`/`topic.steps`/`topic.sleep` nos três de saúde.
    public let referenceTopic: String

    /// `false` quando `done` é `nil` (W4): a tela mostra "sem dados" em vez de um número.
    public let hasData: Bool
    /// 0...1, para a `InkMarkView` (W3). Por padrão é `done ÷ target`, limitado a 1; `muscles` passa um
    /// valor explícito (a soma ponderada de W2.2), diferente do `done`/`target` mostrados em palavras.
    public let fraction: Double
    /// A meta foi cumprida (W3: "Cheia quando a meta é cumprida"). `false` sem dados.
    public let isMet: Bool

    public init(
        kind: WeeklyGoalKind,
        programID: UUID? = nil,
        planGoal: ProgramGoal? = nil,
        done: Double?,
        target: Double,
        referenceTopic: String,
        fraction: Double? = nil
    ) {
        self.kind = kind
        self.programID = programID
        self.planGoal = planGoal
        self.done = done
        self.target = target
        self.referenceTopic = referenceTopic

        let hasData = done != nil
        self.hasData = hasData
        let safeTarget = target > 0 ? target : 1
        let rawFraction = fraction ?? ((done ?? 0) / safeTarget)
        self.fraction = min(1, max(0, rawFraction))
        self.isMet = hasData && (done ?? 0) >= target
    }
}
