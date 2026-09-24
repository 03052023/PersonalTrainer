# Contrato da versão 2.1 (rápida)

Versão 1 · 2026-09-24. Escopo decidido pelo dono: modo casa (RF-42, §7.13), medida do exercício (RF-43), RIR explicado (RF-41), textos de saúde para qualquer relógio, e ajustes da revisão final (B7 duração estimada, B10 backup direto, A4/B8 dispensa de saúde nos dois sentidos, A5 importar limpa decisões) e revisão dos programas Foco inferior e Foco superior. **Fora:** "Como fazer" (vai na versão seguinte). **Sem SchemaV3:** medida e "de casa" vêm do catálogo do seed pelo `slug`.

Como testar sem compilador local: `docs/V2-FINAL-CONTRACT.md` §0. `watch-ci.ps1` com `-Minutes 9`, repetindo a chamada. Core tests em push que toca `Packages/**` ou `Resources/Seed/**`; App build em push para `ci/<nome>`.

## Onda A — TrainerCore + seed (duas tarefas paralelas)

### A1 `v4/core-home` (CI: `ci/v4-core-home` para o App build)
Arquivos:
- `Packages/TrainerCore/Sources/TrainerCore/Domain/`: `ExerciseMeasure.swift`, `ExerciseTraits.swift`, `ExerciseTraitsCatalog.swift`, `Equipment.swift` (+ `household`), `ExerciseSubstitution.swift` (afinidade: `household` na família do peso do corpo);
- `.../Engine/HomeSubstitution.swift` e `HomeSwap.swift`;
- testes `HomeSubstitutionTests.swift`, `ExerciseTraitsTests.swift` e ajuste em `SeedBundleTests.swift`;
- `PersonalTrainer/Resources/Seed/exercises.v2.json` e `programs.v2.json`;
- `PersonalTrainer/Services/Seed/SeedLoader.swift`, só se for preciso para inserir os exercícios novos em instalações existentes;
- e **os switches sobre `Equipment` fora do core que deixariam de compilar**: `Features/Catalog/Equipment+DisplayName.swift` e `Features/Session/SubstituteExerciseSheet.swift`, com o rótulo "Objetos de casa".

```swift
public enum ExerciseMeasure: String, Codable, CaseIterable, Sendable { case reps, seconds, steps }
public struct ExerciseTraits: Codable, Sendable, Hashable {
    public let measure: ExerciseMeasure   // padrão .reps
    public let atHome: Bool               // padrão false
    public static let `default`: ExerciseTraits
}
public struct ExerciseTraitsCatalog: Sendable {
    public static let empty: ExerciseTraitsCatalog
    public init(traitsBySlug: [String: ExerciseTraits])
    /// Lê o JSON do catálogo do seed ({"exercises":[{"slug", "measure"?, "atHome"?, ...}]}).
    public static func decode(seedCatalogJSON data: Data) throws -> ExerciseTraitsCatalog
    public func traits(forSlug slug: String) -> ExerciseTraits   // desconhecido → .default
}
public struct HomeSwap: Sendable, Hashable {
    public let originalID: UUID
    public let replacement: ExerciseDefinition?   // nil = sem opção em casa (sai da sessão)
    public var isUnchanged: Bool { get }          // o original já era de casa
}
public enum HomeSubstitution {
    /// §7.13 H1–H3, na ordem dos exercícios do dia. `catalog` = catálogo não arquivado.
    public static func swaps(for dayExercises: [ExerciseDefinition], catalog: [ExerciseDefinition], traits: ExerciseTraitsCatalog) -> [HomeSwap]
    /// Candidatos de casa para trocar um exercício na sessão (mesma regra do RF-34, só entre os de casa).
    public static func candidates(for exercise: ExerciseDefinition, catalog: [ExerciseDefinition], traits: ExerciseTraitsCatalog, excluding: Set<UUID>, limit: Int) -> [ExerciseDefinition]
}
```

Seed:
- Campos `measure` (só quando não for `reps`) e `atHome` em todos os exercícios, seguindo H1. Carregadas medem em `steps`; pranchas e isometrias, em `seconds`.
- Exercícios novos de casa, com UUID novo, `movementPattern` e grupos primários. Por exemplo: flexão inclinada na cadeira, flexão de joelhos, flexão pike, mergulho na cadeira, agachamento com peso do corpo, agachamento búlgaro com cadeira, avanço, avanço reverso, stiff unilateral, ponte unilateral, panturrilha no degrau, remada com mochila, Y-T-W deitado, rosca com mochila, elevação lateral com garrafas, carregar sacolas e superman.
- **Teste de cobertura:** todo exercício de `programs.v2.json` tem equivalente de casa por H2.
- Foco inferior e Foco superior: o grupo em foco 2×/semana e descansos de 150/90 s (§7.9). Não mexa no programa com id da M1 (A/B/C) nem no Completo corpo todo.
- Confira no `SeedLoader` que os exercícios novos entram numa instalação que já tem o seed v2; se exigir subir a versão do seed, suba e teste.

### A2 `v4/health-texts`
Arquivos: `Packages/TrainerCore/Sources/TrainerCore/Health/HealthSuggestions.swift`, `Health/HealthText.swift`, `Coach/CoachText.swift` (se citar Apple Watch), os testes correspondentes e as linhas A3/A4 da SPEC §7.10.
- A sugestão de atualizar o VO2máx só aparece se existe **pelo menos uma** estimativa de VO2máx na janela de leitura (180 dias). Quem usa um relógio que não envia VO2máx ao Saúde nunca recebe essa sugestão.
- Os textos falam em "seu relógio", não em "Apple Watch", exceto quando o recurso só existe no Apple Watch.
- "Use o relógio para dormir" continua, contando sono de qualquer fonte.

## Onda B — app (depois da onda A mesclada e do andaime do arquiteto)

Andaime (arquiteto, no `main`, antes da onda B):
- `Services/ExerciseTraits/ExerciseTraitsLibrary.swift` lê `exercises.v2.json` do bundle e devolve `.empty` em caso de falha;
- `AppEnvironment.traits`;
- `Features/DesignSystem/ExerciseTraitsEnvironment.swift` com `EnvironmentValues.exerciseTraits` (padrão `.empty`), injetado na raiz.

### B1 `v4/home-mode` (dono de `Services/Planning/*`, `Features/Home/*` exceto `PrescriptionRow.swift`, `Features/Settings/*` e `App/RootView.swift`)
- Chave `UserDefaults` `homeModeEnabled`, padrão false, lida em `PlannerSettings`.
- Ligada, `nextPlan` e `plan(forDayID:)` aplicam `HomeSubstitution.swaps`. O alvo vem do original e a prescrição do histórico do exercício de casa, como em `substitutionPlan`.
- `SessionPlan` ganha `isHomeMode`, `homeNotices: [String]` e `estimatedMinutes: Int` (B7). A estimativa soma, por série, reps médias × 3 s (ou os segundos), mais o descanso, mais 2 min por exercício de preparação.
- `substitutes(for:limit:)` usa `HomeSubstitution.candidates` quando a chave está ligada.
- Home: interruptor "Em casa" no cartão do dia, faixa "Em casa" com os avisos, "≈ N min".
- Ajustes: a mesma chave; A5 (importar backup apaga `deload-decisions.json`, `last-review.json` e a chave `coachPendingDeloadSince`, mas mantém o log do diálogo); B10 ("Fazer backup" do C7 abre a exportação direto).
- Testes do planejador para H2–H4 e para a duração.

### B2 `v4/session-measure` (dono de `Features/Session/*`, `Features/Home/PrescriptionRow.swift`, `Features/History/*`)
- RF-41 inteiro (T6.2).
- RF-43 nas telas, lendo `@Environment(\.exerciseTraits)` pelo slug:
  - stepper "Segundos"/"Passos" no lugar de "Repetições";
  - "3 × 20–40 s" na prescrição;
  - histórico e resumo com a unidade.
- Testes das funções de formatação.

### B3 `v4/health-coach` (dono de `Features/Health/*`, `Services/Coach/*` e `Features/Coach/*`)
- A4/B8: dispensar uma sugestão de saúde no feed também a esconde no detalhe de Saúde. A fonte única é o log do diálogo.
- Textos do app que citam "Apple Watch" em contexto genérico passam a dizer "seu relógio".

### Integração, revisão e correção
O arquiteto mescla B1–B3 em `v4/integration`, resolve conflitos e itera no `ci/v4-final`. Depois vêm 2 revisores somente leitura (execução e dados; comportamento contra a SPEC) e um corretor, até ficar verde. Por fim, merge no `main`, TASKS atualizado e o guia de instalação da Amanda com o link do run final.
