# Contrato da versão 2.2 (simplificação)

Versão 1 · 2026-09-27. Base: o commit do `main` que traz este arquivo (todos os worktrees `w5-*` partem dele).

**Decisões do dono** (SPEC decisão 18; `docs/design/v22/proposal.json` → `ownerAnswers`, `judge.finalProposal`, `decisionsPerItem`; telas em `docs/design/v22/mockup.html`). Elas prevalecem sobre qualquer proposta:
1. **Flor 6 · Brisa** (`docs/design/icon-v22/render-icon-v22.ps1`) no ícone (padrão, escuro e tingido) e na `FlowerView`.
2. **RIR interno e invisível:** o sistema continua lidando com o RIR, mas a pessoa não vê nem escolhe nada. Saem o seletor, "O que é RIR?", o cartão da primeira vez, o RIR alvo nas prescrições ("RIR 2", "pare com 2 sobrando", "pare N antes do limite", inclusive no VoiceOver), o RIR das séries no Histórico e o campo "RIR alvo" do editor. Séries novas gravam `rir = nil` e `isWarmup = false`. O motor e o esquema não mudam.
3. **Combate:** subtítulo "Potência e resistência"; o nome continua "Combate".
4. **Proposta aprovada inteira:** objetivo = plano (Hipertrofia com 3 formatos); o topo da tela Hoje troca de objetivo; tela Hoje enxuta; sessão como ficha de consulta com "Feito" por exercício e bolinhas por série; ao concluir com exercícios não marcados, oferecer "Marcar como feitos, como previsto"; tela acesa só com a ficha aberta; peso do corpo sem carga (S6, com a regra atual de carga extra no topo da faixa); a chave Aquecimento sai, trocada por uma dica fixa (S7).

**Regras de domínio:** SPEC RF-01, RF-03, RF-04, RF-12, RF-16, RF-17, RF-35, RF-39, RF-41, RF-42 e RF-44 a RF-47. **Aparência:** DESIGN §2, §4, §6, §7, §9 e §13.

**Fora desta versão:** "Como fazer" (RF-40); SchemaV3; qualquer mudança em `Packages/TrainerCore` (Engine, Review, Coach, Sync, Health); tarefas [PROJ] e [SCHEMA] (`project.yml`, workflows, entitlements e `Persistence/Schema/` ficam intocados); mudança em `SessionEvent`, sync ou backup; a regra "nunca pôr carga em peso do corpo" (SPEC §12).

## 0. Como testar sem compilador local

Vale o `docs/V2-FINAL-CONTRACT.md` §0: o Smart App Control bloqueia o Swift nesta máquina e não se mexe nessa configuração.
- Comece todo comando PowerShell com `Set-Location` para o **seu** worktree. Nunca edite `C:\Users\leona\Developer\PersonalTrainer` diretamente.
- Antes de cada push, releia inteiro cada arquivo que você alterou: tipos, imports, `@MainActor`/`Sendable`, inits, `switch` exaustivos, fechamentos de chaves, rótulos de argumento.
- Push: `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"; git push origin HEAD:ci/v5-<key>`. O App build (xcodegen, testes no simulador, IPA) leva de 20 a 30 min.
- Espere com `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\watch-ci.ps1 -Sha <sha completo> -Minutes 9 -Expected <N>` e repita a chamada até ele dizer que todos terminaram. `N = 1`, exceto na tarefa `exercise-info`, que toca `Resources/Seed/` e também dispara o Core tests (`N = 2`).
- Corrija pelas anotações. No máximo 5 rodadas de CI por tarefa. No fim, com o CI verde, `git push origin v5/<key>`.
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Entregue no relatório a lista **Verificado** e **Incerto** (AGENTS R11) e o sha do último run verde.

## 1. Regras desta versão

1. **Escopo exclusivo por arquivo.** Cada arquivo do app e dos testes tem no máximo uma tarefa dona (§3). Criar arquivo novo só dentro das pastas da sua tarefa. Precisou de um arquivo de outra tarefa? Pare e reporte; não edite.
2. **Não edite** `SPEC.md`, `ARCHITECTURE.md`, `AGENTS.md`, `TASKS.md` nem este contrato: o integrador marca o estado. `DESIGN.md` só a tarefa `flower`, e só os números da §2.
3. **Andaime já no `main`** (§2): as assinaturas marcadas como congeladas não mudam. A dona (`exercise-info`) pode completar a implementação e acrescentar funções, mas as saídas fixadas em `PersonalTrainerTests/Features/ExerciseInfo/TodayTargetTextTests.swift` continuam valendo.
4. **Funções compartilhadas de outra pasta** (§2.4): ninguém muda assinatura nem texto de saída. Quem não quer mais usar uma função simplesmente para de chamá-la; o integrador apaga o que ficar sem uso.
5. **RIR** (SPEC RF-41): nenhum texto, rótulo, leitura do VoiceOver ou dica mostra RIR, "com N sobrando" ou "antes do limite". A única marca indireta permitida é a dica de primeira vez da ficha (RF-44 c). Correção de série (`setUpdated`) regrava o `rir` que já estava na série, sem mudar.
6. **AGENTS:** R4 (views não escrevem no `ModelContext`; sessão só pelo `SessionCoordinating`, programa só pelo `ProgramRepositoring`), R8, R9, R11 (nada de `fatalError`, `try!` ou força-unwrap fora de testes), §4 (um tipo público por arquivo, textos pt-BR fixos, `os.Logger`, sem `print`), §7 (nenhuma permissão no launch; a tela acesa não é permissão).
7. **Textos** pt-BR, curtos, sem jargão de academia (DESIGN §6 e §7): "sessão", "Começar", "Concluir", "Feito", "Plano", "Primeira vez", "Carga maior", "Tentar de novo", "Carga menor", "Retorno", "Semana leve", "Sessão concluída".
8. **Testes:** cada tarefa atualiza os testes dos arquivos que muda (a tabela de §3 diz quais arquivos de teste são seus). Nome começa pela regra: `testRF44_dot_logsGoalWithPreviousLoad`. XCTest no app.
9. **Previews** podem mudar à vontade dentro do seu escopo; usem os doubles de `PreviewSupport/` da sua tarefa.

## 2. Assinaturas compartilhadas

### 2.1 "Da última vez" (andaime; dona: `exercise-info`)

`PersonalTrainer/Services/Planning/ExerciseLastSession.swift` (congelado):
```swift
struct ExerciseLastSession: Sendable, Hashable {
    let sessionID: UUID
    let date: Date            // startedAt da sessão
    let sets: [SetResult]     // só séries de trabalho, na ordem de index; nunca vazio
    let wasDeload: Bool
    init(sessionID: UUID, date: Date, sets: [SetResult], wasDeload: Bool)
}
```

`SessionPlanning` (requisito novo com padrão na extensão, congelado):
```swift
func lastSession(forExerciseID exerciseID: UUID) throws -> ExerciseLastSession?
// extension SessionPlanning { func lastSession(forExerciseID:) throws -> ExerciseLastSession? { nil } }
```
Sessão `completed` ou `abandoned` mais recente (empate de data pelo `sessionID`) em que o exercício teve ao menos uma série de trabalho, de qualquer programa, com semana leve incluída. A sessão em andamento nunca entra. A implementação em `SessionPlanner` é da `exercise-info`; até ela chegar, o padrão devolve `nil` e as outras tarefas compilam e mostram a folha sem "Da última vez".

### 2.2 Folha "Informações do exercício" (andaime; dona: `exercise-info`)

`PersonalTrainer/Features/ExerciseInfo/ExerciseInfoContent.swift` (congelado):
```swift
struct ExerciseInfoContent: Sendable, Hashable, Identifiable {
    let id: UUID              // PlannedExercise.id ou SessionExerciseModel.uuid (para .sheet(item:))
    let exerciseID: UUID      // ExerciseDefinition.id / SessionExerciseModel.exerciseUUID
    let name: String
    let equipment: Equipment?
    let loadUnit: LoadUnit
    let measure: ExerciseMeasure
    let machineNotes: String?
    let sets: Int
    let targetReps: Int       // meta de hoje já resolvida
    let repMin: Int
    let repMax: Int
    let targetRIR: Int        // só para a frase de primeira vez; nunca exibido
    let load: Double?         // nil = primeira vez sem carga (P2)
    let restSeconds: Int
    let note: PrescriptionNote
    let lastSession: ExerciseLastSession?
    init(id:exerciseID:name:equipment:loadUnit:measure:machineNotes:sets:targetReps:repMin:repMax:targetRIR:load:restSeconds:note:lastSession:)
    init(planned: PlannedExercise, measure: ExerciseMeasure, lastSession: ExerciseLastSession?)
    @MainActor init(sessionExercise: SessionExerciseModel, measure: ExerciseMeasure, lastSession: ExerciseLastSession?)
    var loadDisplay: TodayTargetText.LoadDisplay { get }
}
```

`PersonalTrainer/Features/ExerciseInfo/ExerciseInfoSheet.swift` (assinatura congelada; o conteúdo completo é da `exercise-info`):
```swift
struct ExerciseInfoSheet: View {
    init(content: ExerciseInfoContent,
         references: ReferenceCatalog,
         onSubstitute: (() -> Void)? = nil,   // só na ficha, antes da 1ª série (RF-34)
         onSkip: (() -> Void)? = nil)         // só na ficha, exercício não pulado
}
```
A folha traz a própria `NavigationStack` e o "Fechar". Ela só chama o fechamento: quem apresenta fecha a folha (item `nil`) e faz a ação depois que ela saiu da tela (no `onDismiss`), porque o SwiftUI não abre uma folha sobre outra que está fechando.

### 2.3 Textos da meta de hoje e selo leigo (andaime; dona: `exercise-info`)

`PersonalTrainer/Features/ExerciseInfo/TodayTargetText.swift` e `PrescriptionNote+Badge.swift` (congelados, com as saídas fixadas em `TodayTargetTextTests.swift`):
```swift
enum TodayTargetText {
    enum LoadDisplay: Sendable, Hashable { case hidden, toChoose, load(String), extra(String) }
    static let toChooseText: String                          // "escolha a carga"
    static func goal(targetReps: Int, repMin: Int) -> Int    // > 0 → targetReps; senão repMin
    static func loadDisplay(load: Double?, unit: LoadUnit, equipment: Equipment?) -> LoadDisplay   // RF-46
    static func loadText(_ load: Double, unit: LoadUnit) -> String       // "62,5 kg", "4 placas", "nível 7"
    static func loadLabel(_ display: LoadDisplay) -> String?            // nil em .hidden
    static func amount(_ value: Int, measure: ExerciseMeasure) -> String         // "3 repetições", "15 segundos", "30 passos"
    static func compactAmount(_ value: Int, measure: ExerciseMeasure) -> String  // "3", "15 s", "30 passos"
    static func setsText(_ sets: Int) -> String                                  // "1 série", "3 séries"
    static func row(sets: Int, goal: Int, measure: ExerciseMeasure, load: LoadDisplay) -> String       // "3 séries de 3 · 62,5 kg"
    static func headline(goal: Int, measure: ExerciseMeasure, load: LoadDisplay) -> String            // "3 repetições · 62,5 kg"
    static func spokenRow(sets: Int, goal: Int, measure: ExerciseMeasure, load: LoadDisplay) -> String
    static func spokenHeadline(goal: Int, measure: ExerciseMeasure, load: LoadDisplay) -> String
    static func rest(seconds: Int) -> String                  // "4 min", "2 min 30 s", "45 s", "sem descanso"
    static func detail(sets: Int, restSeconds: Int) -> String // "3 séries · descanso 4 min"
}
extension PrescriptionNote { var badgeText: String? }   // nil em .hold (sem selo)
```
Home, Sessão, Informações e Histórico usam estas funções para a meta e o selo. Assim a mesma frase aparece em todo lugar.

### 2.4 APIs de outras pastas que ficam como estão

| Quem é dono | O que não muda (assinatura e texto de saída) | Quem usa |
|---|---|---|
| `session` | `MeasureText.*`; `LoadFormatter.kilograms(_:)` (as duas; hoje em `SetDraft.swift`: se `SetDraft` sair, `LoadFormatter` vai para `Features/Session/LoadFormatter.swift` igual); `PrescriptionSpeech.text(sets:repMin:repMax:measure:loadText:targetRIR:restSeconds:)` e `.rest(seconds:)`; `RIRText.*`; `SubstituteExerciseSheet.init(exerciseName:suggestions:references:context:onPick:onCancel:)` e `SubstituteContext`; `SessionFlowView.init(sessionID:environment:onClose:)` | Home, Histórico, Programa (`DayEditorView`, `ProgramDetailViewModel`), RootView e testes dessas tarefas |
| `flower` | `FlowerView.init(activeGoal:size:)`; `ProgramGoal.color`, `.symbolName`, `.subtitle`, `.petalIndex` (só o texto do Combate muda) | Home, Programa, Sessão (resumo) |
| `history` | `WeeklyFrequencyCard` (nome, `init(references:)`, `report(sessions:now:calendar:…)`, `visibleEntries`, `chipText`, `muscleName`, `accessibilityText`), agora em `Features/History/`; `HistoryListView.init(references:onDeleteSession:)` | `HomeViewModelTests` (testes da Home), RootView |
| `goal-plan` | `OnboardingView.init(programs:references:onDone:)` continua compilando (parâmetro novo só com padrão); `ProgramTabView.init(programs:catalog:references:now:)` idem; `CatalogListView` não é tocado | RootView |
| `home` | `HomeView.init(model:coach:health:references:onOpenSession:)` continua compilando (parâmetro novo só com padrão); `HomeViewModel.init(planner:coordinator:now:defaults:)` | RootView |
| `settings` | `SettingsView.init(model:coach:health:references:)` e `init(backup:planner:…)`; `SettingsViewModel.init(backup:planner:now:appVersion:defaults:onImported:onDataChanged:)` | RootView |
| ninguém nesta versão | `Features/Coach/*`, `Features/Health/*`, `Features/Catalog/*`, `Features/References/*`, `Features/DesignSystem/Theme.swift`, `PrimaryButtonStyle.swift`, `ExerciseTraitsEnvironment.swift`, `Services/*` (exceto `Services/Planning/*`, da `exercise-info`), `Persistence/**`, `App/**` (integrador) | todos |

### 2.5 Assinaturas novas que o integrador liga (§4)

```swift
// home — HomeView ganha, no fim e com padrão:
HomeView(model:coach:health:references:onOpenSession:onChangeGoal: (() -> Void)? = nil)
//   nil: o topo mostra o objetivo, mas não é botão. Com sessão em andamento o botão fica desabilitado.

// goal-plan — folha nova (Features/Program/GoalSheet.swift):
struct GoalSheet: View {
    enum Mode: Sendable, Hashable { case change, firstUse }
    init(programs: any ProgramRepositoring,
         catalog: (any CatalogRepositoring)?,       // nil: sem a prévia "Dia A: …"
         references: ReferenceCatalog,
         mode: Mode = .change,
         isSessionInProgress: Bool = false,         // true: "Trocar" bloqueado, com a frase do motivo
         onFinish: @escaping (_ didChange: Bool) -> Void)
}
// goal-plan — parâmetros novos com padrão:
OnboardingView(programs:references:catalog: (any CatalogRepositoring)? = nil, onDone:)
ProgramTabView(programs:catalog:references:now:planner: (any SessionPlanning)? = nil,
               coordinator: (any SessionCoordinating)? = nil)
//   planner: marca "próxima" no dia de nextPlan(now:); coordinator: bloqueia a troca com sessão em andamento.
```

## 3. Tarefas

Resumo (todas [CI], sem [PROJ] nem [SCHEMA]):

| Chave | TASKS | Worktree | Branch | CI | Pesada |
|---|---|---|---|---|---|
| `session` | T7.1 | `C:\Users\leona\Developer\pt-wt\w5-session` | `v5/session` | `ci/v5-session` | sim |
| `exercise-info` | T7.2 | `…\pt-wt\w5-exercise-info` | `v5/exercise-info` | `ci/v5-exercise-info` | não |
| `home` | T7.3 | `…\pt-wt\w5-home` | `v5/home` | `ci/v5-home` | não |
| `goal-plan` | T7.4 | `…\pt-wt\w5-goal-plan` | `v5/goal-plan` | `ci/v5-goal-plan` | sim |
| `settings` | T7.5 | `…\pt-wt\w5-settings` | `v5/settings` | `ci/v5-settings` | não |
| `flower` | T7.6 | `…\pt-wt\w5-flower` | `v5/flower` | `ci/v5-flower` | não |
| `history` | T7.7 | `…\pt-wt\w5-history` | `v5/history` | `ci/v5-history` | não |

### 3.1 `session` — a ficha da sessão (T7.1; SPEC RF-44, RF-04, RF-46, RF-12; DESIGN §13)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Session/*`: tudo o que está na pasta; pode criar arquivos novos (por exemplo `ExerciseSheetCard.swift`, `SetDotsView.swift`, `LoadEntryField.swift`) e apagar os que saem da sessão (`SetEntryView.swift`, `CurrentExercisePanel.swift`, `ExerciseProgressList.swift`, `RIRPicker.swift`, `RIRIntroCard.swift`, `RIRExplainerSheet.swift`, e `LoadStepper`/`RepsStepper` se ficarem sem uso). Mantém as APIs de §2.4 (`MeasureText`, `LoadFormatter`, `PrescriptionSpeech`, `RIRText`, `SubstituteExerciseSheet`, `SessionFlowView.init`).
- `PersonalTrainer/PreviewSupport/SessionPreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/ActiveSessionViewModelTests.swift` e `PersonalTrainerTests/Features/Session/*` (pode criar, por exemplo, `SessionSheetMarkingTests.swift`).

**O que fazer:**
1. **Ficha** (`ActiveSessionView` reescrita, RF-44 a): `List` ou `ScrollView` com um cartão por exercício, na ordem, conforme o mockup "Sessão: a ficha" e o DESIGN §13. O cartão tem número, nome (botão que abre a folha de §2.2), selo `note.badgeText` (botão que abre `WhySheet(topic: ReferenceCatalog.topic(for: note), catalog:)`; some quando é `nil` ou quando o catálogo não tem referência), a meta em SF Rounded (`TodayTargetText.amount` + " · " + carga, com a carga sublinhada em `accent` quando é tocável: `.load` ou `.extra`), as bolinhas, "✓ Feito" e `TodayTargetText.detail(sets:restSeconds:)`. Estados: pendente, atual (o primeiro pendente, borda de 1,5 pt em `accent`), feito (linha compacta "✓ 5, 5, 4 · 60 kg"; peso do corpo sem carga: "✓ 5, 5, 4"; cargas diferentes: "✓ 5 × 60 kg, 4 × 57,5 kg") e pulado ("Pulado", esmaecido).
2. **Paleta da sessão:** `SessionFlowView` aplica `.tint(Theme.accent)` e o fundo `Theme.background` na ficha e no resumo (o cover fica fora do tint da raiz).
3. **Dica fixa** no topo da lista (RF-44 d): "Aqueça com 1 ou 2 séries leves antes dos exercícios com carga. Não precisa marcar." A chave Aquecimento sai; toda série nova grava `isWarmup = false`.
4. **Descanso preso no topo** (RF-44 f), por exemplo com `.safeAreaInset(edge: .top)`: `RestTimerView` compacta (anel de 48 pt, "Descanso", "A seguir: série 3 do agachamento" ou o nome do próximo exercício, "+30 s", "Pular").
5. **ViewModel** (`ActiveSessionViewModel`), nomes normativos:
   ```swift
   func goal(for exercise: SessionExerciseModel) -> Int                  // TodayTargetText.goal
   func loadDisplay(for exercise: SessionExerciseModel) -> TodayTargetText.LoadDisplay  // já com a carga escolhida
   func workingLoad(for exercise: SessionExerciseModel) -> Double?       // o que a próxima bolinha grava
   func setWorkingLoad(_ load: Double, for sessionExerciseID: UUID)      // teclado; só em memória
   func needsLoadChoice(_ exercise: SessionExerciseModel) -> Bool        // primeira vez sem carga, não peso do corpo, sem carga > 0 escolhida
   func canMark(_ exercise: SessionExerciseModel) -> Bool                // sessão aberta, não pulado, !needsLoadChoice
   func markSet(sessionExerciseID: UUID)                                 // bolinha vazia
   func markExerciseDone(sessionExerciseID: UUID)                        // "Feito"
   func markRemainingAsPrescribed()                                      // "Marcar como feitos, como previsto"
   var currentExerciseID: UUID? { get }                                  // primeiro pendente
   var pendingExercises: [SessionExerciseModel] { get }                  // não pulados com séries de trabalho < prescribedSets
   func requestFinish() -> SessionFinishRequest                          // .finished (concluiu direto) ou .needsConfirmation(pendingNames:hasAnySet:)
   func infoContent(for exercise: SessionExerciseModel) -> ExerciseInfoContent   // lastSession via planner, erro → nil + log
   func skip(sessionExerciseID: UUID)
   ```
   Saem `completeSet`, `confirmZeroLoadSet`, `cancelZeroLoadSet`, `needsZeroLoadConfirmation` e o rascunho `currentDraft` como API de tela (pode ficar interno se ajudar). Continuam `beginSubstitution`/`substituteSelectedExercise` (RF-34, só antes da 1ª série), `beginEditingSet`, `saveEditedSet`, `deleteSet`, `finish`, `abandon`, `sheetDidDismiss` e o pedido de permissão de notificação na primeira série gravada (AGENTS §7).
6. **O que cada toque grava** (sempre pelo `SessionCoordinating.logSet/updateSet/deleteSet/skipExercise`):

   | Toque | Grava | Descanso |
   |---|---|---|
   | Bolinha vazia (`markSet`) | 1 `setLogged`: `index` = maior gravado + 1; `load` = carga escolhida no teclado ?? carga da última série deste exercício nesta sessão ?? `prescribedLoad` ?? 0 (0 só em peso do corpo; nos outros, `canMark` é falso); `reps` = meta de hoje (RF-04: não copia as repetições da anterior); `rir = nil`; `isWarmup = false`; `now()` | inicia `restSeconds` (> 0) |
   | "Feito" (`markExerciseDone`) | um `setLogged` como acima para cada série que falta até `prescribedSets`; nada se já estiver completo | não inicia |
   | Bolinha cheia | abre "Corrigir série" (`EditSetSheet`): carga (em peso do corpo, "Carga extra"), repetições (`MeasureText.title`) e "Apagar série"; salvar = `updateSet` com o `rir` que a série já tinha; apagar = `deleteSet` | — |
   | Carga (teclado) | nada gravado; `setWorkingLoad` vale para as próximas bolinhas do exercício (P10) | — |
   | "Marcar como feitos, como previsto" | `markExerciseDone` em cada pendente com `canMark`; os de primeira vez sem carga ficam de fora | não inicia |

   Depois de marcar, a borda de "atual" passa ao próximo pendente. `.sensoryFeedback(.success)` ao marcar (DESIGN §10).
7. **Primeira vez com carga** (RF-44 c): no lugar da carga, a caixa "Escolha uma carga que daria para levantar umas N vezes. Hoje faça M.", com M = meta de hoje e N = M + `prescribedRIR` do snapshot, e um campo de carga com `.keyboardType(.decimalPad)` que aceita vírgula ou ponto, valor > 0 e ≤ 1000. Em segundos ou passos, a frase não usa N ("Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça M."). Bolinhas e "Feito" em cinza até haver carga. Sai o alerta "Registrar com 0 kg?". Peso do corpo pula este passo e grava 0 (RF-46).
8. **Informações do exercício:** tocar no nome abre `ExerciseInfoSheet(content: model.infoContent(for:), references:, onSubstitute: (só com canSubstitute), onSkip: (só se não pulado))`. "Trocar" fecha a folha e, no `onDismiss`, abre a `SubstituteExerciseSheet` de hoje. "Pular" fecha a folha e pula direto (a própria folha já é a confirmação).
9. **Concluir** (RF-44 e): o botão "Concluir" da barra chama `requestFinish()`. Tudo marcado → `finish()` e resumo, sem diálogo. Faltando algo → `confirmationDialog` "Faltam N exercícios" com os nomes ("Caminhada do fazendeiro e isometria de pescoço ainda não foram marcados."): com alguma série gravada, "Marcar como feitos, como previsto" (marca e conclui), "Encerrar só com o que marquei" (`finish`) e "Voltar ao treino"; sem nenhuma série, "Marcar como feitos, como previsto", "Sair sem registrar" (`abandon`) e "Voltar ao treino". "Voltar" (minimizar) continua como está.
10. **Tela acesa** (RF-44 g): `UIApplication.shared.isIdleTimerDisabled = true` quando a ficha aparece com o app ativo; `false` ao sumir, ao minimizar, ao concluir e quando o `scenePhase` sai de `.active`. O resumo não mantém a tela acesa.
11. **Resumo** (`SessionSummaryView`, RF-44 h, RF-12): título "Sessão concluída" ("Sessão encerrada" se abandonada), `FlowerView` com o objetivo ativo (`planner.activeProgramGoal()`), o nome do dia, Duração, "Exercícios X de Y" (feitos = ≥ 1 série de trabalho; Y = exercícios da sessão), Séries (de trabalho), FC média/máx só quando houver e "A próxima sessão já está pronta: Dia B — …" (`planner.nextPlan(now:)?.programDayName`, omitido em falha). Sem tonelagem, sem verde nem laranja do sistema; "Fechar" com `.buttonStyle(.primary)`. A pétala se enche devagar, com Reduzir Movimento respeitado.
12. **Acessibilidade:** bolinhas com alvo de 44 pt e rótulos ("Série 2 de 3, feita, 5 repetições" / "Série 3 de 3, marcar como feita"); "Feito" com "Marcar as séries que faltam de Agachamento livre como feitas"; a meta lida com `TodayTargetText.spokenHeadline`; Dynamic Type sem cortar o nome.
13. **Saem da sessão:** chips, steppers na tela principal, seletor de RIR, "O que é RIR?", cartão do RIR, chave Aquecimento, "Série X de Y", "Pular" vermelho, o alerta de 0 kg e o diálogo "Finalizar/Abandonar" quando tudo está marcado.

**Testes (tabela, XCTest):** `RF44_dot_firstSetUsesPrescribedLoadAndGoal`, `RF44_dot_nextSetCopiesLoadAndReturnsToGoal` (RF-04), `RF44_dot_usesChosenLoad`, `RF44_dot_rirNilAndNotWarmup`, `RF44_dot_startsRest_feitoDoesNot`, `RF44_feito_logsOnlyMissingSets`, `RF44_markRemaining_skipsSkippedAndUnloaded`, `RF44_firstTime_requiresLoadAboveZero`, `RF46_bodyweight_logsZeroWithoutAsking`, `RF44_finish_allDone_finishesDirectly`, `RF44_finish_pending_asksWithNames`, `RF44_finish_nothingMarked_offersLeaveWithoutRecording`, `RF19_edit_keepsStoredRIR`. Atualize ou apague os testes que falam de `completeSet`, `SetDraft`, `RIRText` e steppers conforme o que sair; os de `MeasureText`, `PrescriptionSpeech` e `RIRText` continuam enquanto essas APIs existirem.

**Aceite:** App build verde; CA7-1, CA7-2, CA7-3 e CA7-8 cobertos por testes; lista Verificado/Incerto (tela acesa, descanso preso no topo, teclado numérico, Dynamic Type grande).

### 3.2 `exercise-info` — informações do exercício e "da última vez" (T7.2; SPEC RF-47, RF-41; DESIGN §13)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/ExerciseInfo/*` (andaime: `ExerciseInfoContent.swift`, `ExerciseInfoSheet.swift`, `TodayTargetText.swift`, `PrescriptionNote+Badge.swift`; pode criar, por exemplo, `ExerciseInfoText.swift`).
- `PersonalTrainer/Services/Planning/*` (`SessionPlanning.swift`, `SessionPlanner.swift`, `ExerciseLastSession.swift`; os demais só se precisar).
- `PersonalTrainer/Resources/Seed/references.v1.json`: só o texto de `explanations` das chaves `note.*` (dispara o Core tests: `-Expected 2`).
- Testes: `PersonalTrainerTests/Features/ExerciseInfo/*` e `PersonalTrainerTests/Services/SessionPlannerLastSessionTests.swift` (novo).

**O que fazer:**
1. `SessionPlanner.lastSession(forExerciseID:)` (§2.1): sobre o `history(forExerciseUUID:)` que já existe (concluídas e abandonadas), a entrada mais recente com série de trabalho; `sets` só com as de trabalho, na ordem; `wasDeload` da entrada. Sem `@Query`, sem `Date()`.
2. A folha completa (mockup "Informações do exercício"), só leitura, título em New York, seções em `surface`:
   - **Hoje**, em frase: "3 séries de 3 repetições com 62,5 kg. Descanso de 4 min entre as séries."; peso do corpo: "3 séries de 5 repetições, com o peso do corpo."; com carga extra: "… com + 2,5 kg extra."; primeira vez com carga: "4 séries de 6 repetições. Na primeira vez você escolhe a carga."; segundos e passos na unidade certa.
   - **Por que esta carga** (título "Por que 62,5 kg" quando há carga; "Por que assim hoje" sem carga), uma frase por nota com os números da última sessão (`lastSession`) e da faixa: `increase` ("Na última vez você fez 5, 5 e 5 com 60 kg, o máximo de 3 a 5. A carga sobe 2,5 kg e as repetições recomeçam em 3."), `hold` (a carga fica e a meta sobe para N), `retry`, `decrease`, `returning` ("Faz mais de 3 semanas…"), `deload`, `calibrate` (com carga: a frase de primeira vez da RF-41; peso do corpo: "Primeira vez: faça M com boa técnica; a próxima sessão se ajusta."). Sem `lastSession`, frase sem números. Embaixo, o `WhyButton` da nota.
   - **Da última vez · qua, 23 set** (data pt-BR curta): "5, 5, 5 · 60 kg"; peso do corpo sem carga: "5, 5, 5"; cargas diferentes: "5 × 60 kg, 4 × 57,5 kg"; semana leve: "(semana leve)". Some quando `lastSession == nil`.
   - **Notas da máquina** quando `machineNotes` não é vazio.
   - **Ações** só com os fechamentos: "Máquina ocupada? Trocar por outro parecido" e "Pular este exercício", em `accent` (nunca vermelho).
   - Nada de RIR, "pare N antes do limite" nem placeholder de "Como fazer".
   - As frases saem de funções puras testáveis (por exemplo `ExerciseInfoText`), não do `body`.
3. `references.v1.json`: reescreva as explicações `note.calibrate`, `note.retry`, `note.decrease` e `note.deload` sem a sigla "RIR" e sem números de repetições em reserva ("deixe uma folga", "sem chegar ao limite"), mantendo o sentido e as referências. Não mude chaves, tópicos nem referências; `topic.rir` e `rule.*` ficam.
4. `TodayTargetText` e `badgeText`: assinaturas e saídas de §2.3 continuam; pode acrescentar funções.

**Testes:** `RF47_lastSession_picksLatestFinishedWithWorkingSets` (ignora em andamento, sem série de trabalho e aquecimentos; inclui semana leve e abandonada; empate por id), `RF47_today_sentencePerMeasureAndLoad`, `RF47_why_sentencePerNote`, `RF47_lastTime_formatsLoadsAndBodyweight`, `RF41_texts_haveNoRIR` (nenhuma frase contém "RIR", "sobrando" ou "antes do limite"). Os testes de `TodayTargetTextTests` continuam passando.

**Aceite:** App build e Core tests verdes; CA7-4 e CA7-5 cobertos.

### 3.3 `home` — a tela Hoje enxuta (T7.3; SPEC RF-01, RF-45, RF-46; DESIGN §9)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Home/*`, **exceto** `WeeklyFrequencyCard.swift` (é da `history`, que o move). Pode criar arquivos (por exemplo `CoachMessagesView.swift`).
- `PersonalTrainer/PreviewSupport/HomePreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/HomeViewModelTests.swift` (a seção de `WeeklyFrequencyCard` fica como está), `HomeModeTests.swift` e `PersonalTrainerTests/Features/Home/*` (inclui `PrescriptionRowMeasureTests.swift`, movido no andaime).

**O que fazer:**
1. `HomeView` ganha `onChangeGoal: (() -> Void)? = nil` no fim do `init` (§2.5).
2. **Topo** (`GoalHeaderView`, DESIGN §9.1): botão com a flor, o nome em New York, o subtítulo (`goal.subtitle`) e a pílula "Trocar ›" (`accentSoft`/`accent`); sem objetivo, "Escolher ›" e o subtítulo "Escolha um objetivo". Desabilitado com sessão em andamento (e com `onChangeGoal == nil`, só leitura). VoiceOver: "Objetivo: Combate. Potência e resistência." com a dica "Toque duas vezes para trocar de objetivo".
3. **Cartão** (`PlanCard`, DESIGN §9.2): rótulo pequeno "Hoje" ("Sessão escolhida" quando o dia foi escolhido à mão), `DayPickerMenu`, a linha "5 exercícios · ≈ 55 min" com a chave "Em casa" ao lado (em Dynamic Type grande, embaixo; `ViewThatFits`), `PlanBanner` só quando existe e a faixa do modo casa só quando há avisos (`homeNotices`). Saem o selo do objetivo com "Por quê?", o nome do programa e o texto fixo da faixa "Em casa". `PlanCard.detailText(for:)` e `detailAccessibilityText(for:)` ficam sem o nome do programa ("5 exercícios · ≈ 55 min").
4. **Linhas** (`PrescriptionRow`): número (posição + 1), nome, selo `note.badgeText` como botão que abre o `WhySheet` da nota (some se `nil` ou sem referência) e a meta `TodayTargetText.row(sets:goal:measure:load:)` com `loadDisplay(load:unit:equipment:)` (leitura: `spokenRow`). Tocar na linha abre `ExerciseInfoSheet` (`.sheet(item:)` na `HomeView`, sem ações de sessão). Saem RIR, descanso e o link "Por quê?" de cada linha. `PrescriptionRow.summary`/`spokenSummary` passam ao formato novo (ou saem, com os testes); `noteText` dá lugar a `badgeText`.
5. `HomeViewModel.infoContent(for planned: PlannedExercise, measure: ExerciseMeasure) -> ExerciseInfoContent`, com `planner.lastSession(forExerciseID:)` (erro → `nil` + log).
6. **Diálogo:** só a primeira mensagem (`CoachFeedSection` com `Array(coach.messages.prefix(1))`) e, com mais de uma, o link "Ver todas (N)" para uma tela com todas (a mesma `CoachFeedSection`, dentro da `NavigationStack` da Home). Não edite `Features/Coach`.
7. Sai o `WeeklyFrequencyCard` da Home (não apague o arquivo). O cartão de Saúde continua depois do diálogo.
8. Textos: "Escolha os exercícios dele na aba Programa." → "na aba Plano"; estado vazio "Nenhum programa ativo" → "Escolha um objetivo", com o texto "Toque em Escolher, no topo, para ver a próxima sessão."

**Testes:** `PlanCard.detailText` sem programa; `RF01_row_goalInWords` (inclui peso do corpo sem carga, carga extra, primeira vez, segundos e passos); selo leigo e sem selo em `hold`; `RF47_home_infoContentUsesLastSession` com o double do planner; `RF45_header_disabledWithActiveSession`.

**Aceite:** App build verde; CA7-6 coberto.

### 3.4 `goal-plan` — objetivo = plano (T7.4; SPEC RF-45, RF-35, RF-16, RF-41; DESIGN §13)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Program/*`: tudo; pode criar (`GoalSheet.swift`, `GoalSheetModel.swift`, `GoalPlanCatalog.swift`, `PlanTabModel.swift`…) e apagar (`GoalPickerView.swift`, `ProgramListViewModel.swift`, se ficarem sem uso).
- `PersonalTrainer/PreviewSupport/ProgramPreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/ProgramViewModelTests.swift` e `PersonalTrainerTests/Features/Program/*` (novos).
- Usa sem editar: `FlowerView` e `GoalStyle` (da `flower`), `CatalogListView`, `SubstituteExerciseSheet`, `WhyButton`, `ProgramRepositoring` (todo o repositório fica como está: renomear, duplicar, apagar e `setGoal` continuam para o backup e o diálogo).

**O que fazer:**
1. **`GoalPlanCatalog`** (puro, testado): a partir de `[ProgramTemplate]` (ordem do repositório), os 5 objetivos na ordem das pétalas (`petalIndex`: Longevidade, Hipertrofia, Força, Combate, Resistência muscular), cada um com o plano e, na Hipertrofia, os formatos. Ids do seed (`programs.v2.json`):

   | Objetivo | Formato | Id |
   |---|---|---|
   | Hipertrofia | Corpo todo | `14E3FAC0-8424-4360-AF9D-20D18DCB0E45` |
   | Hipertrofia | Mais pernas e glúteos | `C7DDB9BA-1897-40D8-BDC8-A14EB6219FDD` |
   | Hipertrofia | Mais tronco e braços | `ADE28A46-680B-4701-A51F-992519A8AD63` |
   | Hipertrofia | (antigo Empurrar/Inferior/Puxar, escondido) | `26262EE7-89B0-4048-93F9-1720FD9CBE40` |
   | Força | — | `32FA941A-31C4-4D4F-86F5-F3EA366BBB49` |
   | Resistência muscular | — | `CBE66162-1F29-41BE-9FF6-7A9E34C179BA` |
   | Longevidade | — | `2F776C4F-4E46-47AB-9150-7DC04C4A980B` |
   | Combate | — | `C1EB32E3-D082-411E-9DB8-5D2AEFFE5B21` |

   Regra (RF-45): para um objetivo G sem formatos, o plano é o programa ativo se `effectiveGoal == G`; senão, o do seed; senão, o primeiro com `effectiveGoal == G`; senão, nenhum (a linha aparece como "Sem plano pronto" e não é escolhível). Na Hipertrofia, os formatos são os 3 do seed que existirem, nessa ordem; se o ativo é de Hipertrofia e não é um deles (cópia ou o antigo E/I/P), ele entra como formato extra com o próprio nome, marcado como atual; sem nenhum formato, vale o primeiro programa de Hipertrofia como formato único. Dias: "3 dias", ou "3 ou 4 dias" na Hipertrofia (mínimo e máximo dos formatos).
2. **`GoalSheet`** (§2.5; mockup "Escolher o objetivo"): `NavigationStack` própria; "Cancelar" no modo `.change`; título "Seu objetivo" ou "Qual é o seu objetivo?" (`.firstUse`); a flor grande com o objetivo selecionado; 5 linhas (flor pequena com a pétala do objetivo, nome, subtítulo, dias, "· atual"); a linha tocada ganha borda `accent` e mostra os formatos em chips (só Hipertrofia com mais de um), a prévia "Dia A: …" com os nomes dos exercícios (pelo `catalog`, com arquivados; sem `catalog`, sem prévia), o `WhyButton(topic: goal.referenceTopic)` e, no Combate, o aviso "O app prepara o corpo para a luta, mas não ensina técnica. Técnica exige aula presencial." (SPEC §7.9). Embaixo, a frase "Suas cargas ficam guardadas: cada exercício tem o próprio histórico. A próxima sessão será o Dia A." e o botão principal "Trocar para Hipertrofia" (ou "Trocar para Mais pernas e glúteos" quando só muda o formato), desabilitado quando a escolha é a atual ou com `isSessionInProgress` (com a frase "Termine a sessão em andamento para trocar."). No `.firstUse`, o botão é "Começar" (ativa se precisar) e há "Pular" na barra; o gesto de fechar fica desligado. Trocar = `programs.activate(programID:)` uma vez; erro → alerta; sucesso → `onFinish(true)`. Cancelar → `onFinish(false)`.
3. **Primeiro uso** (`OnboardingView`, RF-45): um passo só, com o conteúdo da `GoalSheet` em `.firstUse`; "Começar" e "Pular" gravam `hasCompletedOnboarding` e chamam `onDone`. Mantém `init(programs:references:onDone:)` e ganha `catalog:` com padrão `nil` (§2.5). O `OnboardingViewModel` de dois passos sai ou é trocado pelo modelo da folha.
4. **Aba Plano** (`ProgramTabView`, mockup "Plano"): título "Plano"; no topo, a flor, o nome do objetivo, "3 dias por semana" e "Trocar objetivo" (abre a `GoalSheet` em `.change`, com `isSessionInProgress = coordinator?.activeSession != nil`); "Sua semana" com um cartão por dia (nome do dia, selo "próxima" no dia de `planner?.nextPlan(now:)?.programDayID`, os nomes dos exercícios separados por " · "); por último, "Ajustar exercícios" (abre a edição de dias de hoje: `ProgramDetailView` só com a seção Dias, `DayEditorView`, `TargetEditorSheet`) e "Catálogo de exercícios" (`CatalogListView(catalog:)`). Sem programa ativo: "Escolha um objetivo" com o botão que abre a folha. Relê ao aparecer e depois da folha.
5. **Saem da interface:** a lista de programas, Ativar/Duplicar/Apagar por gesto, "Renomear programa", o `GoalPickerView` dentro do programa e o diálogo "Aplicar padrões?". Nada é apagado do banco.
6. **Editor sem RIR** (RF-16, RF-41): `TargetEditorSheet` sem o stepper "RIR alvo" (o valor gravado volta igual em `updateTarget`) e sem textos de RIR; `ProgramDetailViewModel.targetSummary` e a linha do `DayEditorView` sem "RIR N" (aproveite para mostrar a unidade da medida, pendência B-2: "3 × 20–40 s · 1 min").

**Testes:** `RF45_catalog_eachGoalResolvesToSeed`, `RF45_catalog_activeCopyAppearsAsExtraFormat`, `RF45_catalog_legacyHiddenUnlessActive`, `RF45_catalog_missingSeedFallsBackToFirstByGoal`, `RF45_catalog_goalsInPetalOrder`, `RF45_sheet_activatesOnce`, `RF45_sheet_blockedDuringSession`, `RF45_sheet_currentSelectionDisablesButton`, `RF16_editor_keepsStoredRIR`, `targetSummary` sem RIR.

**Aceite:** App build verde; CA7-7 coberto.

### 3.5 `settings` — Ajustes simplificados (T7.5; SPEC RF-39, RF-42; mockup e proposta, item 6)

**Arquivos (exclusivos):** `PersonalTrainer/Features/Settings/*`, `PersonalTrainer/PreviewSupport/SettingsPreviewSupport.swift`, `PersonalTrainerTests/Features/SettingsViewModelTests.swift`, `PersonalTrainerTests/Features/SettingsHomeModeImportTests.swift`.

**O que fazer:**
1. À vista, nesta ordem: "Semana leve" ("Fazer semana leve agora", com a confirmação de hoje), "Backup" (exportar e importar, como hoje), "Saúde" ("Perfil de saúde") e "Avisos" (aviso de validade, "Como renovar" e o rodapé com a data).
2. "Mais opções" (`NavigationLink` para uma tela nova na pasta): "Escolher o dia pela semana" (o mesmo seletor `plannerFrequencySelector`, com Automático, Ligado e Desligado, e o rodapé "Ligado, o app escolhe o dia que treina os músculos que ficaram para trás na semana. No automático, liga em planos de 4 dias ou mais."), "Semana leve a cada N semanas" (o stepper de hoje), "Referências científicas" e "Versão".
3. Sai a seção "Onde treinar": a chave "Em casa" fica só no cartão da tela Hoje (RF-42). A chave `homeModeEnabled` continua existindo (a Home grava). A limpeza do import (A5) e o "Fazer backup" direto (B10) não mudam.
4. Os `init` de `SettingsView` e `SettingsViewModel` de §2.4 continuam compilando.

**Testes:** ajuste os testes de modo casa que dependiam do Ajustes; os de importação continuam.

**Aceite:** App build verde; CA7-9 coberto.

### 3.6 `flower` — flor Brisa (T7.6; SPEC decisão 18; DESIGN §2, §4)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/DesignSystem/FlowerView.swift` e `GoalStyle.swift`.
- `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, `AppIcon-dark.png`, `AppIcon-tinted.png` (o `Contents.json` só se for preciso).
- `docs/design/render-app-icon.ps1` (reescrito) e `docs/design/candidates/AppIcon-checks.png` (refeito).
- `DESIGN.md`: só os números da §2 (geometria e contrastes medidos).
- Teste novo: `PersonalTrainerTests/Features/DesignSystem/FlowerAndGoalStyleTests.swift`.

**O que fazer:**
1. **Gerador** (`docs/design/render-app-icon.ps1`, PowerShell 5.1 + System.Drawing, UTF-8 com BOM): leve para ele o modelo de pétala (`Get-Petal`, `Get-Center`, `Get-Flower`, `Render-Icon`) e os parâmetros de `$Candidates['brisa']` de `docs/design/icon-v22/render-icon-v22.ps1`, e gere 3 PNG de 1024 px, opacos, sem máscara e determinísticos (rodar duas vezes dá o mesmo SHA-256): padrão (igual ao `v22-6-brisa.png`), escuro (pétalas `#E3DED3`, miolo `#D3C4AB`, fundo `#18222F` → `#101822`, sem halo) e tingido (tons de cinza puros sobre preto, pétalas claras e miolo cinza médio, como o tingido atual). Refaça a folha `AppIcon-checks.png` (os 3 ícones, 60 px sobre claro e escuro, a flor do app a 56 pt nos dois fundos). Rode com `powershell -NoProfile -ExecutionPolicy Bypass -File docs/design/render-app-icon.ps1` e confira as imagens abrindo os PNG.
2. **`FlowerView`:** a `PetalShape` passa a desenhar a geometria Brisa por pétala (a pétala de índice `i` usa `per[i]` da Brisa, o giro geral de −5° e o `dAng` de cada uma): espinha em Bézier cúbica (b1, b2, b3), perfil de largura (tm, alpha, w0), `lean`, `asym`/`asymK`, `tilt` e ondulação (`wobP`, `wobM`), e o miolo levemente irregular (harmônicos da Brisa). Escala: o raio externo da flor inteira = `size / 2`, como o `Draw-AppFlower` do gerador. Mantém o `init(activeGoal:size:)`, a pétala ativa preenchida com a cor do objetivo, as outras em contorno de 1,5 pt em `textSecondary`, o miolo `Theme.flowerCenter`, a animação com Reduzir Movimento e o rótulo de acessibilidade. Nada de `Date()` nem aleatório; amostragem modesta (48 a 64 pontos por flanco) e caminhos unitários calculados uma vez (`static let`) e escalados.
3. **`GoalStyle.subtitle`:** Combate = "Potência e resistência". Cores, símbolos e `petalIndex` não mudam.
4. **DESIGN §2:** troque os números da geometria e dos contrastes pelos que o gerador medir (vão mínimo, raio externo, tamanho do símbolo).

**Testes:** `testS1_combatSubtitle` (os 5 subtítulos), `testS10_petalPaths_areInsideRectAndNonEmpty` (tamanhos 26, 56 e 92), `testS10_petalPaths_areDeterministic`.

**Aceite:** App build verde (o `actool` aceita os 3 PNG); `compare`/checks gerados; CA7-10 coberto.

### 3.7 `history` — "Esta semana" e Histórico sem RIR (T7.7; SPEC RF-17, RF-12, RF-41, RF-46)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/History/*`.
- `PersonalTrainer/Features/Home/WeeklyFrequencyCard.swift` → `git mv` para `PersonalTrainer/Features/History/WeeklyFrequencyCard.swift`, com o nome do tipo e a API de §2.4 iguais (os testes dele continuam em `HomeViewModelTests.swift`, da `home`, e passam sem mudança).
- Testes: `PersonalTrainerTests/Features/History/*`.

**O que fazer:**
1. `HistoryListView`: "Esta semana" (`WeeklyFrequencyCard(references:)`) no topo da lista, antes das sessões; `init` igual.
2. `SessionExerciseSection`: prescrição sem RIR, com `TodayTargetText.row` e `loadDisplay` ("3 séries de 10 · 60 kg"; peso do corpo sem carga); séries sem RIR ("1 · 60 kg × 10"; peso do corpo com carga 0: "1 · 10 repetições"); selo `badgeText` (sem selo em `hold`); leitura do VoiceOver sem RIR. Os aquecimentos antigos continuam com "Aquecimento" e `thermometer.medium`.
3. `SessionDetailView` continua com a tonelagem (RF-12: agora só aqui), duração, séries e FC.
4. Não mude a `HomeView` (a `home` tira o cartão de lá).

**Testes:** `SessionExerciseSection` sem RIR, com o selo leigo e peso do corpo sem carga; `HistoryTests.noteText` → `badgeText`.

**Aceite:** App build verde; CA7-11 coberto.

## 4. Integração (T7.8, `v5/integration`, `C:\Users\leona\Developer\pt-wt\w5-integration`)

Ordem sugerida de merge (sem arquivos em comum, os merges são limpos): `flower`, `settings`, `history`, `exercise-info`, `home`, `goal-plan`, `session`. O integrador é dono de `PersonalTrainer/App/RootView.swift` e `App/AppEnvironment*.swift` e liga:
1. **Aba:** `Label("Plano", systemImage: "list.bullet.rectangle")` e `ProgramTabView(programs:catalog:references:now:planner: environment.planner, coordinator: environment.coordinator)`.
2. **Trocar objetivo pela Home:** `HomeView(…, onChangeGoal: { … })` abre a `GoalSheet(programs: environment.programs, catalog: environment.catalog, references: environment.references, mode: .change, isSessionInProgress: homeModel.activeSessionID != nil, onFinish:)` numa `.sheet` da raiz; `blocksCoachSheet = true` enquanto ela está aberta (liberado no `onDismiss`); com `didChange`, `homeModel.refresh()` e `refreshCoach()`.
3. **Primeiro uso:** `OnboardingView(programs:references:catalog: environment.catalog, onDone:)`.
4. **Diálogo:** `coach.onChooseProgramRequested` abre a mesma `GoalSheet` em vez de trocar de aba.
5. **Nada muda** em `SessionFlowView` (a sessão aplica tint e fundo por dentro), `HistoryListView`, `SettingsView` e `AppEnvironment` (não há serviço novo; a tela acesa é da view).
6. **Código morto:** apague o que ficou sem uso (`RIRText`, `PrescriptionSpeech`, `RIRExplainerSheet`, `GoalPickerView`, `ProgramListViewModel`, testes deles) e, se quiser, mova os testes de `WeeklyFrequencyCard` de `HomeViewModelTests.swift` para `PersonalTrainerTests/Features/History/`. Confira com grep que "RIR" não aparece em texto de tela (DESIGN §7).
7. Marque as tarefas no TASKS e rode `ci/v5-final` até ficar verde. Depois, revisão adversarial somente leitura com duas lentes (execução e dados: gravação por toque, P7, semana leve, HealthKit; comportamento contra a SPEC e o DESIGN: RIR invisível, textos, acessibilidade) e um corretor, até verde. Por fim, merge no `main`, TASKS e HANDOFF atualizados e o IPA do run final para o guia de instalação da Amanda.

## 5. Critérios de aceitação da versão

| CA | Verificação |
|----|-------------|
| CA7-1 | Na ficha, uma bolinha vazia grava 1 série com a meta de hoje, a carga de RF-04, `rir = nil` e `isWarmup = false`, e inicia o descanso; "Feito" grava só as séries que faltam (testes RF44). |
| CA7-2 | Concluir com tudo marcado vai direto ao resumo; com pendentes, o diálogo lista os nomes e "Marcar como feitos, como previsto" marca e conclui; sem nada marcado, "Sair sem registrar" abandona (testes RF44). |
| CA7-3 | Primeira vez com carga: bolinhas e "Feito" só com carga > 0; peso do corpo grava 0 sem pergunta (testes RF44 e RF46). |
| CA7-4 | "Da última vez" vem do `SessionPlanning`, pega a sessão concluída ou abandonada mais recente com série de trabalho e ignora a em andamento (teste RF47). |
| CA7-5 | A folha de informações abre da tela Hoje e da ficha; só na ficha tem "Trocar" (antes da 1ª série) e "Pular". |
| CA7-6 | Tela Hoje: topo com "Trocar", linhas com a meta em palavras, selo só com novidade (abre o "Por quê?"), só a mensagem principal do diálogo, sem "Esta semana", sem RIR, sem descanso e sem nome do programa. |
| CA7-7 | Trocar de objetivo leva 3 toques a partir da Home, fica bloqueado com sessão em andamento e a próxima sessão é o Dia A; a aba se chama Plano e não lista programas (testes RF45). |
| CA7-8 | Nenhuma tela, rótulo ou leitura do VoiceOver mostra RIR, "sobrando" ou "antes do limite" (grep no integrador; teste RF41 das frases). |
| CA7-9 | Ajustes: semana leve, backup, perfil de saúde e avisos à vista; "Escolher o dia pela semana", semanas entre semanas leves, referências e versão em "Mais opções"; sem "Treinar em casa". |
| CA7-10 | Ícone Brisa nas 3 aparências e a `FlowerView` com a mesma geometria; Combate com "Potência e resistência". |
| CA7-11 | Histórico com "Esta semana" no topo, sem RIR, com os selos leigos e a tonelagem no detalhe. |
| CA7-12 | No aparelho: a sessão abre na paleta do app (sem o preto e o azul do sistema), a tela não apaga com a ficha aberta, e a migração não perde nada (dados antigos com RIR e aquecimento continuam no Histórico e no backup). |

## 6. Incertezas conhecidas (só o CI e o aparelho confirmam)

- `isIdleTimerDisabled` ligado e desligado nos momentos certos (troca de app, bloqueio, minimizar).
- Descanso preso no topo com `.safeAreaInset` numa lista que rola, e o teclado numérico com vírgula (pt-BR) no campo de carga.
- Folha aberta a partir de outra folha (informações → "Trocar"): abrir a segunda só no `onDismiss` da primeira.
- Alvos de 44 pt nas bolinhas com Dynamic Type grande, sem cortar os nomes longos ("Caminhada do fazendeiro com halteres").
- A geometria Brisa portada para Swift a 26, 56 e 92 pt, e os PNG escuro e tingido no `actool`.
