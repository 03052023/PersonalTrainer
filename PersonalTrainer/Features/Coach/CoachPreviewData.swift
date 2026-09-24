import Foundation
import TrainerCore

/// Mensagens fixas para os `#Preview` do diálogo. Só dados: os textos seguem os modelos do
/// `CoachFeedBuilder` para a preview mostrar o tamanho real das frases.
enum CoachPreviewData {
    static let expiry = CoachMessage(
        id: "expiry:2026-09-26:2026-09-24",
        rule: .installExpiry,
        itemKey: "expiry",
        title: "O app expira em 2 dias",
        reason: "A instalação atual vale até 26/09 às 21:14; renove pelo Impactor no computador antes disso (reinstalar por cima mantém seus dados).",
        referenceTopic: nil,
        actions: [.howToRenew],
        priority: 0,
        highlightsOnLaunch: true
    )

    static let deload = CoachMessage(
        id: "deload:2026-09-24",
        rule: .deload,
        itemKey: "scheduled",
        title: "Semana mais leve programada",
        reason: "Chegou a semana leve programada no seu plano; nas próximas sessões, uma de cada dia do programa, você fará cerca de 60% das séries com cargas 15% menores, para o corpo se recuperar.",
        referenceTopic: "rule.D",
        actions: [.ok, .keepNormal],
        priority: 100,
        highlightsOnLaunch: true
    )

    static let review = CoachMessage(
        id: "review:addSets:chest:preview:2026-W39",
        rule: .review,
        itemKey: "addSets:chest:preview",
        title: "Mais séries para o peito",
        reason: "Nas últimas 4 semanas o peito teve em média 8 séries por semana, abaixo da faixa de 10 a 20 do seu objetivo.",
        referenceTopic: "topic.volume",
        actions: [.apply, .notNow, .neverAgain],
        priority: 300,
        highlightsOnLaunch: true,
        suggestionID: "addSets:chest:preview:2026-W39"
    )

    static let longevity = CoachMessage(
        id: "longevity:balance:2026-W39",
        rule: .longevity,
        itemKey: CoachInput.balanceKey,
        title: "Equilíbrio: 5 a 10 minutos",
        reason: "Você ainda não marcou equilíbrio nesta semana; a meta é de 2 a 3 vezes por semana, com rotinas curtas como ficar num pé só ou andar em linha reta.",
        referenceTopic: "goal.longevity",
        actions: [.done, .skip],
        priority: 700,
        highlightsOnLaunch: false
    )

    static let all: [CoachMessage] = [expiry, deload, review, longevity]
}
