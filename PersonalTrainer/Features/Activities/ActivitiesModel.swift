import Foundation
import Observation
import TrainerCore

/// Estado das atividades fora do app (SPEC §7.17, RF-53; DESIGN §9.3): os registros da semana, as fixas e o
/// "Feito" das fixas de hoje. Um só modelo para o Início (Metas da semana), a tela Hoje e a aba Plano; o
/// integrador cria uma instância na raiz.
///
/// Escreve só pelo `OutsideActivityStoring` (AGENTS R4: nada de `ModelContext`). O relógio e o calendário
/// chegam por injeção (SPEC P11). `onChange` roda depois de cada gravação bem-sucedida: o integrador o usa
/// para reler o Início, a tela Hoje e o relatório de saúde.
///
/// Andaime da 2.4 (docs/V24-CONTRACT.md §3.2): a assinatura do `init`, `log` e `refresh()` estão congelados;
/// o resto é da tarefa `activities-ui`.
@Observable
@MainActor
final class ActivitiesModel {
    /// O que está gravado, relido em `refresh()`.
    private(set) var log: OutsideActivityLog = .empty

    private let store: any OutsideActivityStoring
    private let now: () -> Date
    private let calendar: Calendar
    private let onChange: @MainActor () -> Void

    init(
        store: any OutsideActivityStoring,
        now: @escaping () -> Date,
        calendar: Calendar = .autoupdatingCurrent,
        onChange: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.onChange = onChange
    }

    /// Relê o que está gravado. Nunca lança (o store devolve vazio quando não consegue ler).
    func refresh() {
        log = store.load()
    }
}
