# Contrato da versão 2.4: atividades fora do app e pendências

Versão 1 · 2026-10-05. Base: o commit do `main` que traz este arquivo e o andaime T10.0 (§3). Os worktrees `C:\Users\leona\Developer\pt-wt\w8-*` partem dele.

Pedido do dono (2026-10-04): **"gere a próxima versão já com tudo que está pendente de ser incluído"**. A versão 2.3 está no `main` (`6eec103`, App build 37254171858). A 2.4 junta:
- o item 19 das notas do dono (`docs/design/v23-owner-notes.md`): **atividades fora do app**;
- os achados da revisão da 2.3 que ficaram para depois;
- os itens abertos do TASKS das versões 2.1, 2.2 e 2.3 que ainda não estão no código.

Nada de recurso novo além disso. Onde a pendência pedia uma decisão de produto do dono, o arquiteto escolheu a opção conservadora e registrou (SPEC decisão 21; a coluna "Decisão" abaixo).

**Notas do dono que continuam valendo** (itens 1 a 19; os de número maior prevalecem): nenhuma mensagem, citação ou frase de efeito em lugar nenhum do app (itens 15 e 16); passos só com Longevidade ou Cardio (item 18); Tinta e papel só no visual (item 14); carga opcional com a sugestão delicada (item 2); RIR interno e invisível (decisão 18).

## Lista de pendências e decisões

| # | Pendência (origem) | Decisão | Tarefa |
|---|---|---|---|
| 1 | **Atividades fora do app** (notas, item 19): pilates, cross, spinning, aula de luta, futebol etc., avulsas ou fixas na semana, contando nas Metas, no encaixe semanal (WeeklyFit, A5) e na recuperação; JSON sem SchemaV3, no backup | Incluída: SPEC §7.17 (X1–X8), RF-53. Escolhas conservadoras: a fixa só conta depois de "Feito"; pilates, ioga e cross não contam no aeróbico; com um plano só continua sem encaixe (M4); os registros não contam no painel de músculos | `activities-core`, `engine` (S6), `data`, `activities-ui`, `plans-ui` |
| 2 | **A3** da revisão da 2.3 (major): depois de "Tirar este plano", o plano que fica recomeça no Dia A | Incluída: S2 usa a última sessão feita num dia do próprio programa (SPEC S2, S8, RF-45) | `engine` |
| 3 | **A7** da 2.3: halo da LaunchFlower cortado num quadrado | Incluída | `launch` |
| 4 | **B5** da 2.3: ordem de abrir e sumir das pétalas errada com objetivo que não é a Longevidade | Incluída | `launch` |
| 5 | **B6** da 2.3: flor grande da abertura chapada, sem o degradê do ícone | Incluída | `launch` |
| 6 | **B8** da 2.3: o cartão "Hoje" do Início fala diferente da tela Hoje | Incluída: o Início reusa os textos da tela Hoje (RF-49) | `activities-ui` (pasta Landing) |
| 7 | **B9** da 2.3: "Seus dias" mostra as duas chaves com dois planos de força, e o motivo conta 2 por dia | Incluída: as chaves só aparecem com força + aeróbico; os lugares de 2 por dia só contam nesse caso (M5, M9) | `activities-core` (núcleo), `plans-ui` (tela) |
| 8 | **B10** da 2.3: "Dia B — Intervalos 4 × 4" mostra "4 × 3 min" | Conservadora: o nome fica (é o protocolo, e os programas do seed não mudam em quem já os tem); a folha de informações explica a progressão (RF-47) | `session` |
| 9 | **B11** da 2.3: a tela Hoje diz "escolha a carga" e a ficha diz "sem carga" | Incluída: a tela Hoje diz "sem carga" (RF-46) | `session` |
| 10 | **A4** da 2.2: a carga digitada antes da 1ª série se perde ao tocar "Voltar" | Incluída: a carga digitada fica no aparelho, por sessão, até a sessão terminar (RF-44 j) | `session` |
| 11 | **A5** da 2.2: a evolução do exercício mostra "0 kg" e 1RM em peso do corpo | Incluída: sem carga, a evolução mostra as repetições (ou a medida), sem 1RM (RF-46) | `session` |
| 12 | **A7** da 2.2: "Sair sem registrar" deixa a sessão vazia no Histórico | Conservadora: a lista esconde a sessão encerrada sem nenhuma série; nada é apagado (RF-09) | `session` |
| 13 | **B6** da 2.2: a última série recolhe o cartão e corrigir custa um toque a mais | Incluída: o cartão fica aberto até a pessoa marcar outro exercício (RF-44 j) | `session` |
| 14 | Texto do ProgramReviewer (2.2) | O R5 já diz "este plano" (2.3); falta o vocabulário: "um plano de N dias" no R4 e o título "Experimentar um novo plano" | `engine` |
| 15 | **B-2** da 2.1: unidades na aba Plano | As unidades já estão no código; incluído o que faltava: a faixa vai até 50 repetições, 300 s, 100 passos ou 180 min (o limite de 50 recusava o "Longo e leve", 45–75 min) (RF-16) | `plans-ui` (editor), `data` (repositório) |
| 16 | **B-3** da 2.1: seletor de RIR | Cancelada: o RIR é invisível desde a 2.2 | — |
| 17 | **B-5** da 2.1: folha Trocar vazia em modo casa diz "catálogo" | Incluída: "Nenhuma opção de casa parecida com este exercício." (RF-34) | `session` |
| 18 | R5 e Epley sem segundos e passos (2.1) | Incluída: segundos e passos saem de R1 e das sugestões de R5 por exercício (R8). O C6 já filtrava no app | `engine` (núcleo), `data` (passa a medida) |
| 19 | App do Watch sem medida (2.1) | Fora: M3, adiado pelo dono | — |
| 20 | **B11** da 2.1: motivo do C1 com os números | Incluída (C1) | `engine` (núcleo), `data` (passa os números) |
| 21 | Programas Foco inferior e Foco superior (2.1) | Já feito no seed 4 (conferido: 4 dias, 2×/semana em todo grupo em foco, descansos 150/90 s): só marcar `[x]` | — |
| 22 | **C10** (2.1): registro próprio de equilíbrio, mobilidade e dos intervalos do Combate | Incluída pelas atividades: Equilíbrio e Mobilidade são tipos de registro, contam 2×/semana nas Metas, e o "Feito" do C8 grava um (X6). Conservadora nos intervalos do Combate: nenhum exercício novo; a "Aula de luta" registrada cobre | `activities-core`, `data`, `activities-ui` |
| 23 | **C11** (2.1): marcar exercício do seed editado (SchemaV3) | Continua pendente: sem SchemaV3 nem seed novo nesta versão | — |
| 24 | "Como fazer" RF-40, T6.5, T6.7 (2.1) | Já feitos na 2.3: só marcar `[x]`. T6.8 é conferência do dono no aparelho | — |
| 25 | **T6.9** e **CA8-8** (2.1, 2.3): guias dos exercícios fora dos programas | Incluída: as 78 que faltam (os 7 aeróbicos do lote 4 e os 71 do resto do catálogo), em 4 lotes | `guides-4` a `guides-7`, integrador |
| 26 | **F5** (2.3): HealthKit do Cardio | Incluída: a sessão só de aeróbicos vai ao Saúde como treino aeróbico e entra nos minutos (RF-13, F5) | `healthkit` |
| 27 | **F5** (2.3): semana leve em minutos | Incluída (§7.5, F5) | `engine` (núcleo), `data` (passa o aeróbico) |
| 28 | 4 × 4 que cresce em blocos (2.3, item 8) | Incluída (F6). Conservadora: começa em 4 blocos, como no seed já instalado, e vai até 5 | `engine` |
| 29 | Dia D de tiros curtos (2.3, item 8) | Fora (conservadora): mede em segundos e seria um dia opcional, que o app não tem | — |
| 30 | Zonas de FC e VO2máx no Cardio (2.3, item 8) | Incluída só para leitura, no detalhe da sessão no Histórico (F7) | `healthkit` (leitura), `session` (tela), integrador |
| 31 | D1–D5, S1–S10 e os itens da onda de telas da 2.3 com `[ ]` | Já entregues: só marcar `[x]` | — |

**Regras de domínio:** SPEC RF-01, RF-09, RF-13, RF-16, RF-34, RF-44 (e, j), RF-45, RF-46, RF-47, RF-48, RF-49, RF-52, RF-53 (novo), S2, S6, S8, §7.5, R4, R8, C1, C8, §7.10 (A1, A5), §7.14 (F3, F5, F6 e F7 novos), §7.15 (M4, M5, M9), §7.16 (W2, W4), §7.17 (X1–X8, novo) e a decisão 21. **Design:** DESIGN.md 1.5 (§7, §9 item 8, §9.1, §9.2, §9.3 nova, §13 "Na 2.4"). **Arquitetura:** ARCHITECTURE §12 e §17.

**Fora deste contrato:** SchemaV3 e qualquer mudança em `Persistence/Schema/`; mudança em `programs.v2.json` ou `exercises.v2.json`; `SessionEvent` e sync; `project.yml` e workflows; o app do Watch (M3); o dia D do Cardio; registro manual de passos ou de sono; texto livre nas atividades.

## 0. Como testar sem compilador local

Vale o `docs/V2-FINAL-CONTRACT.md` §0. O Smart App Control bloqueia o Swift nesta máquina, e essa configuração não se mexe.

- Comece todo comando PowerShell com `Set-Location` para o **seu** worktree. Nunca edite `C:\Users\leona\Developer\PersonalTrainer` diretamente.
- Antes de cada push, releia inteiro cada arquivo que você alterou: tipos, imports, `@MainActor`/`Sendable`, inits, `switch` exaustivos, rótulos de argumento, fechamentos de chaves, `some View` com um só tipo de retorno.
- Configure o push antes: `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"`.
- CI: `git push origin HEAD:ci/v8-<key>`. Todo push para `ci/**` roda o App build (20 a 30 min). Se o commit toca `Packages/**` ou `PersonalTrainer/Resources/Seed/**`, roda também o Core tests. A coluna "Expected" de §2 diz quantos workflows esperar.
- Espere com `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\watch-ci.ps1 -Sha <sha completo> -Minutes 9 -Expected <N>` e repita a chamada até ele dizer que todos terminaram.
- Corrija pelas anotações. No máximo 5 rodadas de CI por tarefa. No fim, com o CI verde, faça `git push origin v8/<key>`.
- Em `@Test(arguments:)`, declare os casos antes, como constantes com tipo explícito (armadilha do Swift 6.3 no Linux, HANDOFF §2).
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No PowerShell 5.1, passe a mensagem por arquivo (`git commit -F <arquivo>`), gravado em UTF-8 **sem BOM** (`[System.IO.File]::WriteAllText(<arquivo>, <texto>, (New-Object System.Text.UTF8Encoding($false)))`).
- O relatório traz: o que foi feito, os CAs cobertos, a lista **Verificado** e **Incerto** (AGENTS R11), o sha do último run verde e os achados fora do escopo.

## 1. Regras desta rodada

1. **Escopo exclusivo por arquivo** (§4). Arquivo novo só dentro das pastas da sua tarefa. Se precisar de um arquivo de outra tarefa, pare e reporte; não edite.
2. **Não edite** `SPEC.md`, `TASKS.md`, `AGENTS.md`, `DESIGN.md`, `ARCHITECTURE.md`, `docs/HANDOFF.md`, `docs/design/v23-owner-notes.md`, `docs/design/exercise-guides/batches.json` nem este contrato. O arquiteto já os atualizou; o integrador marca o estado.
3. **`App/*` é do integrador** (`RootView.swift`, `AppEnvironment.swift`, `AppEnvironment+Factories.swift`, `PersonalTrainerApp.swift`). Ninguém mais toca. O que cada tarefa entrega para ser ligado está em "Entrega ao integrador".
4. **Congelado** (§3): as assinaturas do andaime, os raw values persistidos (inclusive os de `OutsideActivityKind`), os ids e slugs do seed, `SessionFlowView(sessionID:environment:onClose:)`, `ExerciseInfoSheet(content:references:onSubstitute:onSkip:)`, `LandingViewModel`/`LandingView`/`HomeView`/`ProgramTabView`/`HealthViewModel`/`SessionPlanner`/`CoachService`/`BackupService` (parâmetros novos só no fim e com padrão), as funções públicas de `TodayTargetText` e `MeasureText` (as saídas mudam só onde §4 manda) e o formato das guias. Quem precisar mudar algo congelado para e reporta.
5. **Requisito novo em protocolo** vem com padrão na extensão. Quem implementa usa **exatamente** a assinatura do protocolo: com um rótulo ou tipo diferente, o Swift usa o padrão em silêncio.
6. **Testes que dependem do corpo de outra tarefa** (por exemplo, o S6 com as atividades, o encaixe com fixas, os blocos do F6, os números do C1, a intensidade declarada no `AerobicWeek`) não entram no CI da sua tarefa, porque no seu branch esse corpo ainda é o do andaime. Escreva os testes da sua parte com dados que valem nos dois mundos, e liste em "Para o integrador" o teste cruzado que faltou. O integrador os escreve (§5).
7. **`Engine/`**: só a `engine` mexe, com uma exceção já feita pelo arquiteto no andaime (o parâmetro novo do `FrequencyAwareSelector` e do `DeloadPolicy`, o `RecoveryLoad`, o `DeloadTriggerDetail` e o esboço de `DeloadScheduler.triggerDetail`).
8. **Guias do "Como fazer"** (`guides-4` a `guides-7`): `PersonalTrainer/Resources/Seed/exercise-guides.v1.json` e os dois goldens em `Packages/TrainerCore/Tests/TrainerCoreTests/Fixtures/` são **gerados** por `merge-guides.ps1`. Cada tarefa de guias os regenera no próprio branch para o CI dela. Na integração, um conflito nesses três arquivos se resolve rodando o `merge-guides.ps1` de novo com todos os lotes, nunca à mão.
9. **AGENTS:**
   - R1: `TrainerCore` só usa Foundation. R2/P12: nada de FC no `Engine`, nas atividades, no encaixe nem nas metas. R3: nenhum `Date()` no `TrainerCore`.
   - R4: views não escrevem no `ModelContext`; sessão só pelo `SessionCoordinating`, programa só pelo `ProgramRepositoring`, atividades só pelo `OutsideActivityStoring`.
   - R8: nada de `PersistentIdentifier` fora de `Persistence/`. R9: efeito externo com protocolo + Live + Fake.
   - R11: nada de `fatalError`, `try!` ou força-unwrap fora de testes; lista Verificado/Incerto.
   - §4: um tipo público por arquivo, textos pt-BR fixos, `os.Logger`, sem `print`. §7: nenhuma permissão pedida no launch nem nas Metas da semana; o HealthKit do Cardio usa as permissões que o app já pede (treino e FC).
   - R7: toda regra nova tem teste com o nome da regra (`@Test("X3 …")`, `@Test("F6 …")`, `testS2_…`, `testRF53_…`).
10. **Textos** em pt-BR, curtos, no tom do DESIGN §6 e §7. Nenhum texto novo cita RIR nem FC para prescrever. **Nenhuma citação, frase inspiracional, elogio ou frase de efeito em tela alguma** (itens 15 e 16). Os textos dizem o fato e o que fazer ("Pilates · terça · 50 min · leve", "1 de 2 vezes", "Nada registrado nesta semana."). Nada de "parabéns", "ótimo", "!" ou contagem de "dias seguidos".
11. **Visual:** tokens do `Theme` e componentes do DesignSystem (`paperBackground()`, `inkCard()`, `InkMarkView`, `PrimaryButtonStyle`). Nada de hexadecimal solto, anéis concêntricos, confete, vermelho fora de erro, `figure.*`, halteres fora do "Como fazer" (DESIGN §1, §8, §14).

## 2. Mapa das tarefas

| Chave | TASKS | Worktree | Branch | CI | Expected | Pesada |
|---|---|---|---|---|---|---|
| `activities-core` | T10.1 | `C:\Users\leona\Developer\pt-wt\w8-activities-core` | `v8/activities-core` | `ci/v8-activities-core` | 2 | sim |
| `engine` | T10.2 | `C:\Users\leona\Developer\pt-wt\w8-engine` | `v8/engine` | `ci/v8-engine` | 2 | sim |
| `data` | T10.3 | `C:\Users\leona\Developer\pt-wt\w8-data` | `v8/data` | `ci/v8-data` | 1 | sim |
| `healthkit` | T10.4 | `C:\Users\leona\Developer\pt-wt\w8-healthkit` | `v8/healthkit` | `ci/v8-healthkit` | 1 | não |
| `activities-ui` | T10.5 | `C:\Users\leona\Developer\pt-wt\w8-activities-ui` | `v8/activities-ui` | `ci/v8-activities-ui` | 1 | sim |
| `plans-ui` | T10.6 | `C:\Users\leona\Developer\pt-wt\w8-plans-ui` | `v8/plans-ui` | `ci/v8-plans-ui` | 1 | não |
| `session` | T10.7 | `C:\Users\leona\Developer\pt-wt\w8-session` | `v8/session` | `ci/v8-session` | 1 | sim |
| `launch` | T10.8 | `C:\Users\leona\Developer\pt-wt\w8-launch` | `v8/launch` | `ci/v8-launch` | 1 | não |
| `guides-4` | T10.9a | `C:\Users\leona\Developer\pt-wt\w8-guides-4` | `v8/guides-4` | `ci/v8-guides-4` | 2 | sim |
| `guides-5` | T10.9b | `C:\Users\leona\Developer\pt-wt\w8-guides-5` | `v8/guides-5` | `ci/v8-guides-5` | 2 | sim |
| `guides-6` | T10.9c | `C:\Users\leona\Developer\pt-wt\w8-guides-6` | `v8/guides-6` | `ci/v8-guides-6` | 2 | sim |
| `guides-7` | T10.9d | `C:\Users\leona\Developer\pt-wt\w8-guides-7` | `v8/guides-7` | `ci/v8-guides-7` | 2 | sim |
| integrador | T10.10 | `C:\Users\leona\Developer\pt-wt\w8-integration` | `v8/integration` | `ci/v8-final` | 2 | — |

Nenhuma tarefa depende do código de outra para compilar: o que é compartilhado está no andaime (§3). As telas de uma tarefa podem aparecer "sem" a parte da outra no próprio CI (por exemplo, a `plans-ui` vê o cartão "Também hoje" vazio, e as Metas da `activities-ui` veem o aeróbico das atividades só depois da `activities-core`); o comportamento completo só existe na integração.

## 3. Andaime (no `main`; congelado)

O commit `feat(v2.4 T10.0 scaffold)` trouxe as assinaturas abaixo. As marcadas "esboço" têm o corpo da tarefa dona; as outras já valem (a dona pode corrigir o corpo, sem mudar a assinatura).

### 3.1 TrainerCore

| Símbolo | Arquivo | O que é | Estado | Dona |
|---|---|---|---|---|
| `OutsideActivityKind` (12 casos, raw values da tabela X1) | `Activities/OutsideActivityKind.swift` | `displayName`, `role`, `defaultIntensity: CardioIntensity`, `primaryMuscles`, `countsAsAerobic`, `aerobicActivity`, `defaultMinutes` (a tabela X1) | pronto | `activities-core` |
| `OutsideActivityRole` (`light`, `strength`, `cardio`) | `Activities/OutsideActivityRole.swift` | papel em X4 e X5 | pronto | `activities-core` |
| `OutsideActivityEntry` (Codable) | `Activities/OutsideActivityEntry.swift` | `id`, `kind`, `start`, `minutes`, `intensity: CardioIntensity`, `fixedActivityID: UUID?`, `end` | pronto | `activities-core` |
| `FixedOutsideActivity` (Codable) | `Activities/FixedOutsideActivity.swift` | `id`, `kind`, `weekday: PlanWeekday`, `startMinuteOfDay` (0…1439), `minutes`, `intensity` | pronto | `activities-core` |
| `OutsideActivityLog` (Codable, tolerante) | `Activities/OutsideActivityLog.swift` | `version`, `entries`, `fixed`, `.empty`, `currentVersion` = 1 | pronto | `activities-core` |
| `OutsideActivities` | `Activities/OutsideActivities.swift` | constantes (`minutesRange` 5…300, `maxFixed` 10, `minimumOverlapFraction` 0,5, `longevityWeeklyTarget` 2, `longevityEntryMinutes` 10, `strengthRecoveryHours` 48, `vigorousCardioRecoveryHours` 24, `legMuscles`) e `isValidMinutes`, `entries(_:in:)`, `fixed(_:on:)`, `isLogged(_:on:entries:calendar:)`, `entry(loggingFixed:on:calendar:id:)`, `countsTowardAerobic`, `aerobicSamples(entries:excludingOverlapWith:)`, `aerobicMinutes(entries:week:)`, `fixedDemands(_:)`, `recoveryLoads(entries:)`, `placementSessions(entries:)`, `longevityCounts(entries:week:)`, `longevityEntry(key:at:id:)` | pronto (sem testes; a dona testa e corrige) | `activities-core` |
| `FixedActivityDemand` | `Plans/FixedActivityDemand.swift` | a fixa vista pelo encaixe: `id`, `name`, `weekday`, `role`, `primaryMuscles`, `isLowerBody`, `cardioIntensity`, `minutes` | pronto | `activities-core` |
| `WeekSchedule.fixed` e `fixed(on:)`; `init(slots:notes:fixed: = [])` | `Plans/WeekSchedule.swift` | as fixas da semana, para a aba Plano | pronto (o encaixe ainda não preenche) | `activities-core` |
| `WeeklyFit.fit(_:preferences:fixed: = [])` | `Plans/WeeklyFit.swift` | X4 | **esboço** (ignora `fixed`) | `activities-core` |
| `AerobicWorkoutSample.declaredIntensity: AerobicIntensity?` (no fim do `init`, padrão `nil`) | `Health/AerobicWorkoutSample.swift` | X3 | **esboço** (o `AerobicWeek` ainda não lê) | `activities-core` |
| `WeeklyGoalsInput.outsideAerobicMinutes: Int` (padrão 0) e `longevityCounts: [String: Int]` (padrão `[:]`), no fim do `init` | `Summary/WeeklyGoalsInput.swift` | W2.3, W2.6, X3, X6 | **esboço** (o `WeeklyGoals` ainda não lê) | `activities-core` |
| `RecoveryLoad` (`start`, `muscles`, `hours`) | `Engine/RecoveryLoad.swift` | X5 | pronto | `engine` |
| `FrequencyAwareSelector.init(…, dayMuscles:, recoveryLoads: [RecoveryLoad] = [])` e `recoveryLoads` | `Engine/FrequencyAwareSelector.swift` | S6 com atividades | **esboço** (guarda, não lê) | `engine` |
| `DeloadPolicy.deloadPrescription(from:loadIncrement:isBodyweight:isCardio: = false)` | `Engine/DeloadPolicy.swift` | §7.5 com aeróbicos (F5) | **esboço** (ignora `isCardio`) | `engine` |
| `DeloadTriggerDetail` (`trigger`, `decreasedExercises`, `countedExercises`, `weeksSinceAnchor`, `anchorIsLastDeload`, `weeksBetweenDeloads`) | `Engine/DeloadTriggerDetail.swift` | C1 com números | pronto | `engine` |
| `DeloadScheduler.triggerDetail(normalPrescriptions:histories:sessions:programDayCount:decisions:weeksBetweenDeloads:now:) -> DeloadTriggerDetail?` | `Engine/DeloadScheduler.swift` | C1 com números | **esboço** (devolve `nil`) | `engine` |
| `ExerciseReviewInput.measure: ExerciseMeasure` (no fim do `init`, padrão `.reps`) | `Review/ExerciseReviewInput.swift` | R8 com segundos e passos | **esboço** (não lido) | `engine` |
| `CoachInput.deloadDetail: DeloadTriggerDetail?` (no fim do `init`, padrão `nil`) | `Coach/CoachInput.swift` | C1 com números | **esboço** (não lido) | `engine` |

### 3.2 App

| Símbolo | Arquivo | Estado | Dona |
|---|---|---|---|
| `protocol OutsideActivityStoring: AnyObject { func load() -> OutsideActivityLog; func save(_ log: OutsideActivityLog) throws }` e `OutsideActivityStoreError.storageUnavailable` | `Services/Activities/OutsideActivityStoring.swift` | pronto | `data` |
| `FakeOutsideActivityStore(log:)` (memória; `saveCount`, `saveError`) | `Services/Activities/FakeOutsideActivityStore.swift` | pronto | `data` |
| `@Observable @MainActor final class ActivitiesModel` com `init(store: any OutsideActivityStoring, now: @escaping () -> Date, calendar: Calendar = .autoupdatingCurrent, onChange: @escaping @MainActor () -> Void = {})`, `private(set) var log: OutsideActivityLog` e `func refresh()` | `Features/Activities/ActivitiesModel.swift` | **esboço** (só relê) | `activities-ui` |
| `struct FixedActivitiesSection: View { init(model: ActivitiesModel) }` | `Features/Activities/FixedActivitiesSection.swift` | **esboço** (`EmptyView`) | `activities-ui` |
| `struct TodayActivitiesCard: View { init(model: ActivitiesModel) }` | `Features/Activities/TodayActivitiesCard.swift` | **esboço** (`EmptyView`) | `activities-ui` |

## 4. Tarefas

### 4.1 `activities-core` — atividades fora do app no núcleo (T10.1, pesada)

**Arquivos (exclusivos):**
- `Packages/TrainerCore/Sources/TrainerCore/Activities/*`, `Plans/*`, `Summary/*`, `Health/*`. Pode criar arquivos nessas pastas.
- `PersonalTrainer/Resources/Seed/references.v1.json`: só o que está no ponto 6.
- Testes: `Tests/TrainerCoreTests/OutsideActivitiesTests.swift` (novo), `WeeklyFitTests.swift`, `PlansScaffoldTests.swift`, `PlanCombinationTests.swift`, `WeeklyGoalsTests.swift`, `HealthAerobicWeekTests.swift`, `HealthCalculatorTests.swift`, `HealthSuggestionsTests.swift`, `ReferenceCatalogTests.swift` e, se a contagem de referências estiver lá, `SeedBundleTests.swift`.

**O que fazer** (SPEC §7.17, §7.15 M4/M5, §7.16 W2/W4, §7.10 A1):
1. **X1–X8 em `OutsideActivities`:** confira cada corpo do andaime contra a SPEC e cubra com testes de tabela. Corrija o que divergir, sem mudar assinatura.
2. **A1 com intensidade declarada (X3):** em `AerobicWeek.minutes(of:zones:)`, os minutos sem FC usam `workout.declaredIntensity ?? workout.activity.defaultIntensity`. Leve não conta, como já acontece.
3. **Encaixe com fixas (X4)** em `WeeklyFit`/`WeeklyFitSearch`:
   - cada `FixedActivityDemand` entra em toda semana da órbita, no dia dela, como um lugar fixo que nenhuma escolha move;
   - **estrutura do dia:** uma fixa de força ocupa o lugar de força (nenhuma força de plano naquele dia); uma fixa de aeróbico ocupa o lugar de aeróbico; uma força de plano com uma fixa de aeróbico (ou um aeróbico de plano com uma fixa de força) no mesmo dia seguem a regra de duas sessões de M4 (`allowsTwoSessionsPerDay`, ou "Cardio leve depois da força" com aeróbico leve ou moderado e força que não é de pernas); uma fixa leve não ocupa lugar;
   - **48 h e véspera de pernas** entre uma fixa e uma sessão de plano em dias seguidos (domingo → segunda conta), com os grupos e a intensidade da fixa; duas fixas entre si nunca invalidam a semana;
   - **avisos:** `noFullRestDay` conta os dias com qualquer fixa (também a leve); `strengthBeforeCardio` vale no dia com força e aeróbico em que ao menos um é de plano;
   - **critérios de escolha:** contam as fixas como as outras sessões (elas são iguais em toda escolha, então só empurram as sessões de plano para longe delas);
   - `WeekSchedule.fixed` = as fixas recebidas, na ordem de `OutsideActivities.fixedDemands`; os `PlannedSlot` continuam só de planos;
   - os motivos e as saídas de M5 rodam a mesma busca com as fixas.
4. **B9 (M5):** em `WeeklyFit.problems`, os lugares de `notEnoughDays` contam 2 por dia só com `allowsTwoSessionsPerDay` **e** planos que misturam força e aeróbico (algum plano com sessão `.strength` e algum com `.cardio`); senão, 1 por dia.
5. **Metas (W2.3, W2.6, W4):** em `WeeklyGoals`:
   - aeróbico: `done = health?.aerobic.moderateEquivalentMinutes` ou, sem `health`, `outsideAerobicMinutes` quando for maior que 0; sem os dois, `nil` ("sem dados");
   - equilíbrio e mobilidade: `done = max(longevityCounts[chave] ?? 0, longevityDone.contains(chave) ? 1 : 0)`, `target = OutsideActivities.longevityWeeklyTarget` (2).
6. **Referências** (confira o DOI no Crossref antes do commit; se não bater, pare e reporte):
   - `ainsworth-2011-compendium`: Ainsworth BE, Haskell WL, Herrmann SD, Meckes N, Bassett DR Jr, Tudor-Locke C, Greer JL, Vezina J, Whitt-Glover MC, Leon AS; 2011; "2011 Compendium of Physical Activities: a second update of codes and MET values"; Medicine and Science in Sports and Exercise; `10.1249/MSS.0b013e31821ece12`; nível `consensus`; resumo em pt-BR de uma frase (o compêndio dá o gasto de cada atividade; pilates e ioga ficam no leve, spinning e futebol no vigoroso);
   - tópico `topic.activities` com `bull-2020-who`, `ainsworth-2011-compendium` e `schumann-2022-concurrent`, e a explicação em cerca de 3 frases: o que conta no aeróbico e por quê (OMS), por que pilates, ioga e cross não contam, e que as atividades entram na recuperação e na semana sem mudar a carga;
   - a explicação de `topic.cardio` ganha uma frase sobre os blocos (no topo, entra mais um bloco, até 5) e outra sobre a semana leve encurtar os minutos; a de `goal.longevity` diz que equilíbrio e mobilidade contam as vezes registradas, contra 2 por semana;
   - nada de frase de efeito (item 16).

**Testes** (Swift Testing, nome pela regra): `X1 a tabela dos 12 tipos` (papel, intensidade, duração, aeróbico, grupos); `X1 duração aceita`; `X2 o Feito grava o registro com a hora da fixa`, `X2 uma vez por dia`, `X2 fixas do dia em ordem`; `X3 aeróbico conta moderado 1 e forte 2, leve não`, `X3 pilates, ioga e cross não contam`, `X3 cobertura de 50 % por um treino do Saúde` (49 % conta, 50 % não), `X3 intensidade declarada no AerobicWeek`; `X4` em tabela (cross fixo na terça impede força de plano na segunda e na quarta com grupo em comum; spinning forte fixo impede pernas no dia seguinte; pilates fixo não impede nada, mas tira o descanso completo; duas fixas que se chocam não invalidam; força de plano + fixa de aeróbico no mesmo dia só com as chaves; `WeekSchedule.fixed`; determinismo; saídas com fixas); `X5 cargas de recuperação` (força 48 h, aeróbico forte 24 h, leve nada); `X5 sessões de inferior para A5`; `X6 contagem de equilíbrio e mobilidade na semana`, `X6 registro do C8`; `W2.3 sem Saúde usa os minutos das atividades`, `W4 sem Saúde e sem atividades fica sem dados`, `W2.6 conta as vezes contra 2`, `W2.6 Feito antigo vale 1`; `M5 dois planos de força contam 1 por dia` (B9); `topic.activities e a referência nova existem` (lendo o JSON por `#filePath`).

**Entrega ao integrador:** nada a ligar.

**Aceite:** Core tests e App build verdes em `ci/v8-activities-core`; CA10-1 e CA10-2.

### 4.2 `engine` — motor, revisão e diálogo (T10.2, pesada)

**Arquivos (exclusivos):**
- `Packages/TrainerCore/Sources/TrainerCore/Engine/*`, `Review/*`, `Coach/*`.
- Testes: `RotationSelectorTests.swift`, `FrequencyAwareSelectorTests.swift`, `DoubleProgressionRuleTests.swift`, `CardioProgressionTests.swift`, `DeloadPolicyTests.swift`, `DeloadSchedulerTests.swift`, `Review*Tests.swift`, `Coach*Tests.swift` e arquivos novos de teste com o nome da regra.

**O que fazer:**
1. **S2 (A3):** em `RotationSelector`, a referência é a sessão mais recente (`completed` ou `abandoned`, com ≥ 1 série de trabalho; empate pelo id, como hoje) **cujo `programDayID` é um dia do programa**. Sem nenhuma, D1. O caso "o dia dessa sessão não existe mais → D1" deixa de existir: a sessão de um dia apagado é ignorada, e vale a anterior. Atualize o comentário do tipo. O `FrequencyAwareSelector` herda a correção pelo desempate da rotação.
2. **S6 com atividades (X5):** em `FrequencyAwareSelector`, `musclesTrainedWithinRecoveryWindow` soma os grupos de cada `RecoveryLoad` com `now − start < hours` (uma carga no futuro conta como recém-feita, como as sessões; `hours` não positivo ou NaN é ignorado). S5 não muda: as cargas nunca contam para a meta semanal.
3. **F6 (blocos dos intervalos)** em `DoubleProgressionRule`, exatamente como a SPEC §7.14 F6: só aeróbico (`movementPattern == .cardio`) com `target.sets ≥ 2` e L = 0; `B` = séries de trabalho da referência (P3), limitado a `[S, 5]`; sem histórico ou em P9, `B = S`; no topo com ≥ B blocos e B < 5 → `sets = B + 1`, `targetReps = repMin`, nota `increase`; com 5 no topo, fica; fora disso, P5–P7 sobre os minutos com `sets = B`. Com L > 0, F3 como hoje. Constante pública `DoubleProgressionRule.maxIntervalBlocks = 5`.
4. **Semana leve no aeróbico (F5, §7.5):** em `deloadPrescription(…, isCardio: true)`: `sets = ⌈0,6 × sets⌉` (mínimo 1), como hoje; com 1 série, `targetReps = max(1, ⌈0,6 × repMin⌉)`; com mais de uma, `targetReps = repMin`; carga como hoje. Com `isCardio` falso, nada muda.
5. **C1 com números (B11):** `DeloadScheduler.triggerDetail` com a mesma conta e o mesmo rearme de `status` (pode extrair o que é comum para não duplicar); `nil` fora de `.pending(.manyDecreases)` e `.pending(.scheduled)`. No `CoachFeedBuilder`, o motivo do C1 usa `input.deloadDetail` quando ele bate com o gatilho:
   - (a) "Em 4 de 7 exercícios a carga precisou baixar; " + o conteúdo de hoje;
   - (b) "Já são 6 semanas desde a última semana leve; " (ou "desde a primeira sessão; ") + o conteúdo;
   - sem detalhe, ou com o pedido manual, o texto de hoje. Os singulares certos ("1 exercício", "1 semana").
6. **R8 com segundos e passos:** no `ProgramReviewer`, um exercício com `measure` `.seconds` ou `.steps` fica fora de R1 (sem progresso nem estagnação, e fora da base dos 50 % de R5) e das sugestões de R5 por exercício (faixa vizinha e troca), como o aeróbico; continua em R2, R3 e R4.
7. **Vocabulário:** o motivo do R4 diz "um plano de N dias"; o título do C2 de troca diz "Experimentar um novo plano".
8. Nada de FC no `Engine` (o `check-boundaries.sh` procura `heartRate`, `heart_rate` e `bpm`, sem diferenciar maiúsculas, inclusive em comentários).

**Testes:** `S2` em tabela (sessão de outro programa não reinicia; tirar o segundo plano mantém a rotação do outro; dia apagado → vale a sessão anterior; sem sessão do programa → D1; S4 continua); `S6 com cargas de atividades` (cross há 30 h exclui os dias com grupo em comum; aeróbico forte há 20 h exclui pernas, há 25 h não; leve não existe como carga; S5 não muda); `F6` em tabela (4 × 3 → 4 × 4 → 5 × 3 → 5 × 4 → fica; incompleto mantém B; pausa volta a S; com nível vale F3; força com várias séries não muda); `F5 semana leve no aeróbico` (1 série: 45 → 27; intervalos: 5 blocos → 3, minutos no mínimo); `C1 motivo com números` (os dois gatilhos, singulares, sem detalhe, manual); `triggerDetail igual ao status` (os mesmos cenários do `DeloadSchedulerTests`, com o rearme); `R8 segundos e passos fora de R1 e de R5`; os testes que conferem os textos antigos mudam para os novos.

**Entrega ao integrador:** nada a ligar (a `data` passa os dados novos).

**Aceite:** Core tests e App build verdes em `ci/v8-engine`; CA10-3 e CA10-4.

### 4.3 `data` — armazenamento, backup, planejador e diálogo (T10.3, pesada)

**Arquivos (exclusivos):**
- `PersonalTrainer/Services/Activities/*` (novo `LiveOutsideActivityStore.swift`; o protocolo e o Fake do andaime ficam com você).
- `Services/Backup/*`, `Services/Planning/*`, `Services/Coach/*`, `Persistence/Repositories/ProgramRepository.swift`.
- Testes: `PersonalTrainerTests/Services/OutsideActivityStoreTests.swift` (novo), `Services/BackupServiceTests.swift`, `Services/SessionPlanner*Tests.swift`, `Services/Coach*Tests.swift`, `Persistence/ProgramRepositoryTests.swift` e, só nas expectativas ligadas a esta tarefa, `Integration/FullLoopTests.swift`.

**O que fazer:**
1. **`LiveOutsideActivityStore`** (X8), no padrão do `LiveDeloadDecisionsStore`: `Application Support/PersonalTrainer/outside-activities.json`, escrita atômica, datas no padrão do `JSONEncoder`, arquivo ausente = `.empty`, ilegível = `.empty` com log, `save` sem pasta → `OutsideActivityStoreError.storageUnavailable`. `static func defaultFileURL() -> URL?` e `init(fileURL: URL? = LiveOutsideActivityStore.defaultFileURL())`.
2. **Backup (X8):** `BackupDocument` ganha `var outsideActivities: OutsideActivityLog?` (no fim do `init`, padrão `nil`; o `schemaVersion` continua 1). `BackupService` ganha `activities: (any OutsideActivityStoring)? = nil` no fim do `init`:
   - a exportação leva `activities?.load()`;
   - a importação, depois de conferir as contagens, grava `document.outsideActivities ?? .empty` (uma falha vai para o log e não desfaz a importação, que já terminou);
   - o retrato de antes leva as atividades, e o `restore` as devolve;
   - um backup sem o campo importa com a lista vazia.
3. **Planejador** (`SessionPlanner`, parâmetro novo `activities: any OutsideActivityStoring = FakeOutsideActivityStore()` no fim do `init`):
   - o `FrequencyAwareSelector` recebe `recoveryLoads: OutsideActivities.recoveryLoads(entries: activities.load().entries)` (X5);
   - `weekSchedule(now:)` e `fitCheck(programIDs:preferences:now:)` passam `fixed: OutsideActivities.fixedDemands(activities.load().fixed)` ao `WeeklyFit.fit` (X4);
   - a semana leve passa `isCardio: exercise.movementPattern == .cardio` ao `DeloadPolicy.deloadPrescription` (F5);
   - o `reviewInput` passa `measure: traits.traits(for: exercise).measure` a cada `ExerciseReviewInput` (R8);
   - novo requisito em `SessionPlanning`, com padrão `nil` na extensão: `func deloadTriggerDetail(now: Date) throws -> DeloadTriggerDetail?`. O `SessionPlanner` o implementa com as mesmas entradas do `deloadStatus` (principal, M2) e `DeloadScheduler.triggerDetail`;
   - confira que o snapshot da sessão grava `prescription.sets` (e não `target.sets`) como séries previstas: o F6 muda o número de blocos pela prescrição. Se não grava, corrija no planejador e reporte;
   - atualize o comentário de `sessions(_:of:isMultiPlan:)`: desde a 2.4, S2 olha só os dias do plano dentro do próprio motor (A3).
4. **Diálogo** (`CoachService`, parâmetro novo `activities: any OutsideActivityStoring = FakeOutsideActivityStore()` no fim do `init`):
   - o "Feito" do C8 também grava `OutsideActivities.longevityEntry(key: message.itemKey, at: now)` no store (X6); uma falha vai para o log e a marca do C8 continua;
   - o `CoachInput` recebe `deloadDetail: try? planner.deloadTriggerDetail(now:)` (C1).
5. **Repositório (B-2):** `ProgramRepository.updateTarget` aceita a faixa até 300 (o editor limita por medida, na `plans-ui`), com a mensagem "A faixa deve ir de 1 a 300, com o mínimo menor que o máximo.".

**Testes:** `testX8_storeRoundTrip`, `testX8_missingFileIsEmpty`, `testX8_unreadableFileIsEmpty`; `testX8_backupExportsActivities`, `testX8_importReplacesActivities`, `testX8_oldBackupImportsWithoutActivities`, `testX8_failedImportRestoresActivities`; `testX6_coachDoneLogsLongevityEntry`; `testB2_repositoryAcceptsMinutesUpTo300`; `testF5_deloadPassesCardioFlag` (pelo que der para observar sem o corpo da `engine`); `testRF53_plannerReadsActivitiesStore` (o `FakeOutsideActivityStore` é lido; o efeito no S6 e no encaixe fica para o integrador).

**Entrega ao integrador:** `LiveOutsideActivityStore()`; os parâmetros `activities:` do `SessionPlanner`, do `CoachService` e do `BackupService`.

**Aceite:** App build verde em `ci/v8-data`; CA10-5.

### 4.4 `healthkit` — Cardio no Saúde e FC por minuto (T10.4)

**Arquivos (exclusivos):**
- `PersonalTrainer/Services/HealthKit/*`.
- Testes: `PersonalTrainerTests/Services/HealthKitWorkoutRecorderTests.swift`, `Services/FakeHealthDataReaderTests.swift`, `Services/FakeServicesTests.swift` (se quebrar) e arquivos novos com o nome da regra.

**O que fazer** (SPEC RF-13, §7.14 F5 e F7):
1. **Tipo do treino:** `enum WorkoutRecordKind: Sendable, Hashable { case strength; case aerobic(AerobicActivity) }` e o mapeamento do slug (`brisk-walk` → caminhada; `easy-run`, `run-intervals` → corrida; `stationary-bike`, `bike-intervals` → ciclismo; `rowing-machine` → remo; `elliptical` → elíptico; `stair-climb` → escada; `jump-rope` → pular corda; `bodyweight-circuit` → HIIT). No Live, cada um vira o `HKWorkoutActivityType` certo (`walking`, `running`, `cycling`, `rowing`, `elliptical`, `stairClimbing`, `jumpRope`, `highIntensityIntervalTraining`).
2. **`HealthKitServicing`**, requisitos novos com padrão na extensão:
   - `saveWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date, sessionUUID: UUID) async throws -> UUID` (padrão: `saveStrengthWorkout`);
   - `findOverlappingWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date) async throws -> UUID?` (padrão: força → `findOverlappingStrengthWorkout`; aeróbico → `nil`);
   - `heartRateMinutes(start: Date, end: Date) async throws -> [Double]` (padrão `[]`): a FC média de cada minuto do intervalo, como o leitor de saúde já agrega.
   Live e Fake implementam os três.
3. **Gravador:** uma sessão em que todo exercício com série de trabalho é aeróbico (`movementPattern == .cardio`) grava `.aerobic` do primeiro aeróbico com série; senão, `.strength`, como hoje. O vínculo com um treino de outro app procura o mesmo tipo (força com força; no aeróbico, qualquer treino aeróbico que cubra ≥ 50 % da sessão). Sessões antigas não são regravadas.
4. **Leitura:** confira que o `LiveHealthDataReader` lê os tipos que o app passa a gravar (os oito acima) como aeróbicos (A1). O pular corda entra como HIIT (forte pelo tipo, A1).
5. Nenhuma permissão nova: o app já pede escrita de treino e leitura de FC. Nada é pedido no launch.

**Testes:** `testF5_cardioSessionRecordsAerobicKind`, `testF5_mixedSessionRecordsStrength`, `testF5_slugMappingTable`, `testF5_linksOverlappingAerobicWorkout`, `testF7_fakeHeartRateMinutes`.

**Entrega ao integrador:** `heartRateMinutes(start:end:)` para o `\.cardioHeartRate` do Histórico (§4.7).

**Aceite:** App build verde em `ci/v8-healthkit`; CA10-6.

### 4.5 `activities-ui` — telas das atividades, Metas e Início (T10.5, pesada)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Activities/*` (os três do andaime e arquivos novos), `Features/Landing/*`, `Features/Health/*`.
- `PreviewSupport/LandingPreviewSupport.swift`, `PreviewSupport/HealthPreviewSupport.swift` e o novo `PreviewSupport/ActivitiesPreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/Activities/*` (novo), `Features/Landing/*`, `Features/HealthViewModelTests.swift`.

**Assinaturas congeladas para o integrador** (além de §3.2):

```swift
// LandingViewModel: parâmetro novo, no fim do init atual.
//     activityLog: @escaping @MainActor () -> OutsideActivityLog = { .empty }
// LandingView: parâmetro novo, no fim do init atual.
//     activities: ActivitiesModel? = nil
// HealthViewModel: parâmetro novo, no fim do init atual, e um método.
//     activityLog: @escaping @MainActor () -> OutsideActivityLog = { .empty }
//     func activitiesDidChange()   // recalcula com a última leitura do Saúde, sem reler o HealthKit
```

**O que fazer** (SPEC RF-53, §7.17, RF-49, RF-52; DESIGN §9, §9.1, §9.2 e §9.3):
1. **`ActivitiesModel`:** as listas da semana (`OutsideActivities.entries(_:in:)` na semana de §7.4 no calendário injetado), as fixas, as fixas de hoje e se já têm "Feito", e as ações registrar, editar e apagar um registro, marcar "Feito" numa fixa (uma vez por dia, X2), acrescentar, editar e apagar uma fixa (até 10). Tudo grava pelo store, valida X1 (`isValidMinutes`), chama `onChange` depois de cada gravação bem-sucedida e, numa falha, mostra a mensagem em pt-BR sem perder o que a pessoa escolheu.
2. **Folha de registro** (DESIGN §9.3 ponto 2): tipo em chips, duração de 5 em 5 min, intensidade com as frases do teste da fala, "Quando" (dia e hora; padrão agora menos a duração, arredondado a 5 min) e a chave "Toda semana". Com "Toda semana", grava a fixa daquele dia da semana e hora e, se o "Quando" já passou, também o registro do dia com o id da fixa (é o "Feito" dela). No modo fixa (aberto pela aba Plano), dia da semana e hora no lugar do "Quando". Editar abre a mesma folha preenchida.
3. **`FixedActivitiesSection`** e **`TodayActivitiesCard`**: os corpos do DESIGN §9.3 ponto 3 e §9 item 8.
4. **Metas da semana:** a seção "Fora do app" (DESIGN §9.3 ponto 1) quando a `LandingView` recebe o modelo; o `WeeklyGoalsInput` com `outsideAerobicMinutes` (`OutsideActivities.aerobicMinutes`, só sem relatório de saúde) e `longevityCounts` (`OutsideActivities.longevityCounts`), lidos de `activityLog`; equilíbrio e mobilidade em "1 de 2 vezes"; sem o app Saúde, com minutos das atividades, a linha "Aeróbico só das atividades registradas no app.".
5. **Início (B8 e X2):** o rótulo do cartão "Hoje" usa `TodayPlansText.sessionLabel`/`shortDayTitle` (de `Features/Home`, só leitura; não edite); numa sessão só de aeróbico, o subtítulo é `TodayPlansText.detailText(for:)`; e, com uma fixa de hoje ainda sem "Feito", a linha "Também hoje: Pilates às 19h" (várias: "Também hoje: Pilates às 19h e Futebol às 21h").
6. **Saúde (X3, X5):** o `HealthViewModel`, antes do `HealthCalculator`, soma a `input.aerobicWorkouts` os `OutsideActivities.aerobicSamples(entries:excludingOverlapWith: input.aerobicWorkouts)` e a `input.recentSessions` os `OutsideActivities.placementSessions(entries:)`, lidos de `activityLog`. `activitiesDidChange()` refaz a conta com a última leitura (sem leitura, não faz nada). Nunca pede permissão.

**Testes:** `testRF53_registerAndDelete`, `testRF53_validationRejectsOutOfRange`, `testX2_markDoneOncePerDay`, `testX2_everyWeekCreatesFixedAndTodayEntry`, `testX2_fixedLimitIsTen`, `testRF53_onChangeAfterSave`, `testRF53_saveFailureKeepsDraft`, `testRF53_textsTable` (linhas da semana, fixas, "Também hoje"); `testRF49_alsoTodayLine`, `testRF49_labelUsesTodayTexts` (B8), `testRF49_cardioSubtitle`; `testW26_longevityTimesText`; `testX3_healthMergesActivities` (com um registro moderado de caminhada, que dá o mesmo resultado com ou sem a intensidade declarada do núcleo).

**Entrega ao integrador:** `ActivitiesModel`; os parâmetros novos de `LandingViewModel`, `LandingView` e `HealthViewModel`.

**Aceite:** App build verde em `ci/v8-activities-ui`; CA10-7 e CA10-8.

### 4.6 `plans-ui` — tela Hoje, aba Plano e editor (T10.6)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Program/*`, `Features/Home/*`.
- `PreviewSupport/ProgramPreviewSupport.swift`, `PreviewSupport/HomePreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/Program/*`, `Features/Home/*`, `Features/HomeViewModelTests.swift`, `Features/HomeModeTests.swift`, `Features/ProgramViewModelTests.swift`, `Features/RecoveryContextDerivationTests.swift`, menos as duas asserções de "escolha a carga", que são da `session` (§4.7).

**O que fazer:**
1. **Tela Hoje:** `HomeView` ganha `activities: ActivitiesModel? = nil` no fim do `init`; com o modelo, `TodayActivitiesCard(model:)` embaixo das sessões (e no dia de descanso, embaixo da frase), nos dois modos (um plano e dois). Não muda mais nada na tela.
2. **Aba Plano:** `ProgramTabView` ganha `activities: ActivitiesModel? = nil` no fim do `init`; com o modelo, `FixedActivitiesSection(model:)` depois dos planos e antes de "Ajustar exercícios". Em "Sua semana" (dois planos), cada dia mostra as fixas de `schedule.fixed(on:)` depois das sessões ("Ter · Dia B — Inferior + Pilates"; dia só com fixa: "Ter · Pilates"), pelos textos de `PlanWeekText`.
3. **B9 (M9):** `PlanFitFlowModel` expõe `showsDayToggles`: verdadeiro só quando um dos dois planos é de Cardio (`endurance`, o único plano de aeróbico) e o outro não é, o mesmo critério do `mixesCardioAndStrength` interno das saídas de M5 lido pelo objetivo; as duas chaves de "Seus dias" (no fluxo de adicionar e na aba Plano) só aparecem com ele verdadeiro. Com um plano só ou com dois de força, ficam escondidas, e o que já estava gravado nas preferências continua.
4. **B-2 (RF-16):** o `TargetDraft` limita o máximo da faixa pela medida (repetições 50, segundos 300, passos 100, minutos 180) e a mensagem de validação diz a unidade ("A faixa de minutos deve ter o mínimo menor que o máximo, entre 1 e 180.").

**Testes:** `testRF53_todayShowsActivitiesCard` (pela estrutura do modelo da tela, se der; senão, Verificado), `testX4_weekTextShowsFixed`, `testB9_dayTogglesOnlyWithCardioAndStrength`, `testRF16_rangeLimitByMeasure` (tabela), `testRF16_validationMessageByMeasure`.

**Entrega ao integrador:** os parâmetros `activities:` de `HomeView` e `ProgramTabView`.

**Aceite:** App build verde em `ci/v8-plans-ui`; CA10-9.

### 4.7 `session` — ficha, informações e Histórico (T10.7, pesada)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Session/*`, `Features/ExerciseInfo/*`, `Features/History/*`.
- `PreviewSupport/SessionPreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/Session/*`, `Features/ActiveSessionViewModelTests.swift`, `Features/ExerciseInfo/*`, `Features/History/*`.

**Assinatura congelada para o integrador:**

```swift
// Features/History/CardioHeartRateLookup.swift (novo)
struct CardioHeartRateLookup: Sendable {
    var minuteHeartRates: @MainActor @Sendable (Date, Date) async -> [Double]   // FC média por minuto do intervalo
    var zones: @MainActor @Sendable () -> HeartRateZones?                       // as zonas do painel de saúde
    var latestVo2Max: @MainActor @Sendable () -> Vo2MaxSummary?                 // o último VO2máx com a faixa
    static let none: CardioHeartRateLookup                                       // tudo vazio: a seção não aparece
}
extension EnvironmentValues { var cardioHeartRate: CardioHeartRateLookup }      // padrão .none
```

Se o compilador recusar os fechos `@Sendable` no `EnvironmentKey`, use o macro `@Entry` ou isole a chave no `MainActor`, sem mudar o que o integrador passa (os três fechos), e registre em Incerto.

**O que fazer:**
1. **A4 (RF-44 j):** a carga escolhida no teclado (`chosenLoads`) fica gravada no `UserDefaults` injetado (`loadHintDefaults`), numa chave por sessão (`session.chosenLoads.<uuid da sessão>`), e volta quando a ficha é recriada. A chave some quando a sessão é concluída ou encerrada, e ao abrir uma sessão que não está mais em andamento.
2. **B6 (RF-44 j):** o cartão do exercício que acabou de ser concluído (pela bolinha, pelo "Feito" ou pelo botão grande) entra aberto e só recolhe quando a pessoa marca uma série de outro exercício. "Recolher" continua.
3. **B-5 (RF-34):** `SubstituteExerciseSheet` ganha `isHomeMode: Bool = false` no fim do `init`; sem opções em modo casa, "Nenhuma opção de casa parecida com este exercício."; a ficha passa o modo casa da sessão.
4. **B11 (RF-46):** `TodayTargetText.toChooseText` passa a "sem carga".
5. **B10 e F6 (RF-47):** nos intervalos do Cardio (aeróbico com mais de uma série), a seção "Hoje" das informações acrescenta "Cada bloco sobe 1 min por sessão até {repMax} min. No topo, entra mais um bloco, até 5."; o selo da nota `increase` num aeróbico sem nível diz "Mais um bloco" (com nível, "Nível maior"); nos outros exercícios, como hoje. O `badgeText` de `PrescriptionNote+Badge.swift` fica como está; acrescente uma função (por exemplo `badgeText(isCardio:hasLevel:)`) e use-a na ficha e nas informações. A linha da tela Hoje (`Features/Home/PrescriptionRow.swift`, da `plans-ui`) passa a usá-la na integração (§5).
6. **A5 (RF-46):** em `ExerciseProgressView`, quando nenhuma série do exercício teve carga (> 0), o gráfico mostra a melhor marca da sessão na medida dele (repetições, segundos, passos ou minutos), sem "0 kg", sem 1RM estimado e sem a explicação de Epley; o resto como hoje.
7. **A7 (RF-09):** `HistoryListView.filterVisible` também tira as sessões `abandoned` sem nenhuma série (`SetLogModel`); nada é apagado.
8. **F7:** no `SessionDetailView` de uma sessão em que todo exercício com série é aeróbico, uma seção "Coração" lê o `\.cardioHeartRate`: com FC (`minuteHeartRates` não vazio e `zones` não nulo), "Leve 6 min · Moderada 22 min · Forte 12 min" (cada minuto pela `HeartRateZones.intensity(forHeartRate:)`; minuto sem leitura fica fora) numa barra de tinta fina em `Theme.health`; e, com `latestVo2Max`, "VO2máx: 42,1 (bom)". Sem FC e sem VO2máx, a seção não aparece. Só leitura, sem conselho. A conta fica numa função pura testável (`CardioZoneText` ou parecido).

**Testes:** `testRF44j_chosenLoadSurvivesRecreation`, `testRF44j_chosenLoadClearedWhenFinished`, `testRF44j_justFinishedCardStaysOpenUntilOtherMark`, `testRF34_homeModeEmptyText`, `testRF46_todayRowSaysSemCarga`, `testRF47_intervalsProgressionText`, `testF6_badgeMoreBlocks`, `testRF46_progressWithoutLoadUsesMeasure`, `testRF09_emptyAbandonedHidden`, `testF7_zoneMinutesTable`, `testF7_noHeartRateNoSection`. Os testes existentes de "escolha a carga" mudam para "sem carga". **Exceção de escopo** (só estas duas asserções, que testam a saída da `TodayTargetText` pela linha da tela Hoje): `PersonalTrainerTests/Features/Home/PrescriptionRowMeasureTests.swift` (a frase "3 séries de 8 repetições, escolha a carga") e `PersonalTrainerTests/Features/HomeViewModelTests.swift` (`"3 séries de 8 · escolha a carga"`). A `plans-ui` não toca nessas linhas.

**Entrega ao integrador:** `CardioHeartRateLookup` e `\.cardioHeartRate`.

**Aceite:** App build verde em `ci/v8-session`; CA10-10.

### 4.8 `launch` — fidelidade da abertura (T10.8)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Launch/*`.
- `PersonalTrainer/Resources/Assets.xcassets/LaunchFlower.imageset/*`.
- `docs/design/v23-animation/render-launch-assets.ps1` e `docs/design/v23-animation/launch-assets-check.png`.
- Testes: `PersonalTrainerTests/Features/Launch/LaunchTimelineTests.swift`.
- **Não** toque em `project.yml`.

**O que fazer** (achados A7, B5 e B6 da revisão da 2.3; protótipo `docs/design/v23-animation/launch.html`):
1. **A7:** o halo da `LaunchFlower` não pode sair cortado: gere a imagem com tela de pelo menos 2 × 430k (cerca de 308 pt), mantendo a escala das pétalas, ou desenhe o halo só até a borda com alfa 0 nela. Regere os PNG (@2x, @3x, claro e escuro) pelo script e confira de novo a folha `launch-assets-check.png`. O primeiro quadro da `Canvas` continua igual à tela de lançamento.
2. **B5:** a linha do tempo recebe o índice real da pétala do objetivo, numa sobrecarga interna `frame(at:reduceMotion:dark:goalPetalIndex: Int?)` que a assinatura com `hasGoal` chama com o índice designado. A ordem de abrir é sempre a do protótipo (`ORDER`, anti-horário a partir do topo); a de sumir tira a pétala do objetivo e a põe no fim. Sai a troca de estado entre pétalas do `LaunchOverlay`.
3. **B6:** na `Canvas`, cada pétala grande ganha o degradê da base para a ponta, com as misturas do script (claro: base 5 % para `#1C2B40`, ponta 35 % para `#FFFFFF`; escuro: 6 % e 30 %), no espaço da pétala, antes do `concatenate`; o miolo, degradê vertical misturado 18 % com o topo do fundo. Os hexadecimais ficam na paleta da abertura (`LaunchPalette` ou parecido), como hoje.

**Testes:** `testRF50_goalPetalOneOpensAfterPetalZero` (com o objetivo 1, a pétala 0 começa a abrir antes da 1); `testRF50_fadeOrderPutsGoalLast` (para os 5 objetivos); os de hoje continuam.

**Entrega ao integrador:** nada novo (mesma assinatura do `launchOverlay`).

**Aceite:** App build verde em `ci/v8-launch`; folha conferida; CA10-11.

### 4.9 `guides-4` a `guides-7` — "Como fazer" do resto do catálogo (T10.9a a T10.9d, pesadas)

Uma tarefa por lote de `docs/design/exercise-guides/batches.json` (já escrito pelo arquiteto):

| Chave | Lote | Exercícios |
|---|---|---|
| `guides-4` | 4 | 17: os 7 aeróbicos fora dos programas (CA8-8), tronco, carregadas e pescoço |
| `guides-5` | 5 | 21: empurrar e ombros |
| `guides-6` | 6 | 18: puxar e potência |
| `guides-7` | 7 | 22: pernas e quadril |

**Arquivos (exclusivos):** `docs/design/exercise-guides/batch-<N>.json` (novo) e as folhas `sheet-<N>.png` e `sheet-<N>-dark.png`. **Gerados** (regra §1.8): `PersonalTrainer/Resources/Seed/exercise-guides.v1.json` e `Packages/TrainerCore/Tests/TrainerCoreTests/Fixtures/exercise-guides-golden.v1.json` e `exercise-guides-vocabulary-golden.v1.json`, só pelo `merge-guides.ps1`.

**O que fazer** (SPEC RF-40, §7.12 E1–E10; DESIGN §12; `docs/design/exercise-guides/AUTHORING.md`, que é o roteiro):
1. Escreva as guias do seu lote em `batch-<N>.json`, com o formato e o vocabulário congelados (`docs/V23-CORE-CONTRACT.md` §2.5–§2.7). Use só as cenas e os acessórios que existem: um objeto de casa (mochila, garrafa, sacola, cadeira, toalha) usa o acessório mais próximo do vocabulário (por exemplo, a mochila como peso na mão ou nas costas). Um exercício que não lê bem em 2D sai como `motion: "static"`, com setas (E7). Não mexa em `render-exercise-guides.ps1`, `merge-guides.ps1`, `TrainerCore/Guide` nem nos lotes dos outros.
2. Textos: 3 passos e 2 erros por guia, com palavras próprias, em pt-BR, no tom do DESIGN §6 (E2); `works` nos aeróbicos ("coração e pulmões, com as pernas") e no pescoço.
3. Rode `render-exercise-guides.ps1 -Check -Data batch-<N>.json` até sair só `ok <slug>`, gere a folha com `-Sheet <N>` e **abra os PNG** para conferir cada figura (pose possível, mão no implemento, seta, fantasma), no claro e no escuro.
4. Rode `merge-guides.ps1` (regera o arquivo do seed e os goldens com todos os lotes presentes no seu branch) e faça o commit do lote, das folhas e dos gerados.
5. CI em `ci/v8-guides-<N>` (Expected 2): o `ExerciseGuideTests` valida o bundle e o `GuideGoldenTests` confere que o Swift desenha o mesmo que a folha.

**Aceite:** Core tests e App build verdes; `-Check` limpo; folhas prontas para o dono; CA10-12 (parte do lote).

## 5. Integração (T10.10)

No worktree `C:\Users\leona\Developer\pt-wt\w8-integration` (branch `v8/integration`, a partir da base):

1. Mescle, nesta ordem, com `--no-ff`: `v8/activities-core`, `v8/engine`, `v8/data`, `v8/healthkit`, `v8/activities-ui`, `v8/plans-ui`, `v8/session`, `v8/launch`, `v8/guides-4`, `v8/guides-5`, `v8/guides-6`, `v8/guides-7`. Os escopos são disjuntos, menos os arquivos gerados das guias: em conflito neles, fique com qualquer lado e rode `merge-guides.ps1` no fim, com os 8 lotes, e faça o commit do resultado. Qualquer outro conflito é sinal de arquivo fora do escopo: resolva mantendo as duas partes e registre.
2. **Guias:** depois do `merge-guides.ps1`, tire o `.disabled` do `CA8-8` em `ExerciseGuideCoverageTests.swift` e acrescente `CA6-2 todo exercício do catálogo do seed tem guia` (os 133). Confira que o `merge-guides.ps1` não lista nenhum slug sem guia.
3. **`App/*`:**
   - `AppEnvironment`: `let activities: any OutsideActivityStoring` (`LiveOutsideActivityStore()` no app; `FakeOutsideActivityStore()` nos previews), passado ao `SessionPlanner`, ao `CoachService` e ao `BackupService` (`activities:`);
   - um `ActivitiesModel(store: environment.activities, now: environment.now, calendar: .autoupdatingCurrent, onChange: { … })` na raiz (`@State`), com `refresh()` ao aparecer e ao voltar ao primeiro plano; o `onChange` chama `health.activitiesDidChange()`, `landing.refresh()` e o refresh da tela Hoje;
   - `HealthViewModel(…, activityLog: { environment.activities.load() })`; `LandingViewModel(…, activityLog: { environment.activities.load() })`; `LandingView(…, activities: activitiesModel)`; `HomeView(…, activities: activitiesModel)`; `ProgramTabView(…, activities: activitiesModel)`;
   - `.environment(\.cardioHeartRate, CardioHeartRateLookup(minuteHeartRates: { start, end in (try? await environment.healthKit.heartRateMinutes(start: start, end: end)) ?? [] }, zones: { … HeartRateZones.make(physiology:restingHeartRate:now:calendar:) com a `physiology` e o `report?.recovery.restingHR7` do `HealthViewModel` … }, latestVo2Max: { health.report?.vo2Max }))` na raiz das abas.
4. **Ligações entre pastas:** a `PrescriptionRow` da tela Hoje usa o selo novo dos intervalos ("Mais um bloco", §4.7 ponto 5).
5. **Testes cruzados** (os que §1.6 deixou para cá), no arquivo de teste da pasta certa: `testS2_removingSecondPlanKeepsRotation` (app, A3); `testX5_crossYesterdayAvoidsSharedDay` (planejador com o S6 de verdade); `testX4_fitCheckIncludesFixedActivities`; `testF6_plannedSetsFollowBlocks` (o snapshot grava os blocos da prescrição); `testC1_reasonHasNumbers` (diálogo com o planejador real); `testW23_goalsUseActivitiesWithoutHealth`; `testX3_healthCountsDeclaredVigorous`; e os que as tarefas listaram em "Para o integrador". Testes do app que esperavam o comportamento antigo de uma regra que mudou noutra tarefa (S2 com dia apagado ou de outro programa → Dia A; o Dia B sempre com 4 blocos; o motivo do C1 sem números) mudam para o novo, citando a regra.
6. **Conferência de mensagens** (itens 15 e 16): procure em `PersonalTrainer/Features/**` e em `references.v1.json` textos novos que sejam citação, elogio ou frase de efeito ("parabéns", "ótimo", "incrível", "!", "sequência", "dias seguidos") e registre o que achou; o que for de uma tarefa volta para ela.
7. `git push origin HEAD:ci/v8-final` (Expected 2) até verde.
8. Revisão estática adversarial, correção, CI verde e merge no `main` (o workflow decide). Depois: TASKS (T10.x `[x]`), HANDOFF, IPA do run final e a página e o PDF da Amanda; as folhas dos lotes 4 a 7 vão para o dono (T6.8).

## 6. Critérios de aceitação

| CA | Verificação |
|----|-------------|
| CA10-1 | X1–X6 em testes de tabela no TrainerCore: tipos, fixas, aeróbico com a cobertura de 50 %, recuperação, equilíbrio e mobilidade; nenhum `Date()` nem FC. |
| CA10-2 | Encaixe com fixas (X4) e B9 em testes de tabela, determinístico; Metas com as atividades (W2.3, W2.6, W4); `topic.activities` e Ainsworth 2011 conferidos no Crossref. |
| CA10-3 | S2 pelos dias do programa (A3); S6 com as cargas das atividades (X5); F6 e a semana leve no aeróbico (F5) em testes de tabela. |
| CA10-4 | C1 com os números do gatilho; R1 e R5 sem segundos e passos; "plano" no R4 e no C2. |
| CA10-5 | Atividades no JSON, no backup (exporta, importa, backup antigo, restauração), no planejador e no "Feito" do C8; faixa até 300 no repositório. |
| CA10-6 | Sessão só de aeróbicos vai ao Saúde como treino aeróbico do tipo certo, com vínculo pelo tipo; FC por minuto disponível; nenhuma permissão nova. |
| CA10-7 | Registrar, editar, apagar e "Feito" (uma vez por dia); "Toda semana"; até 10 fixas; validação; textos de fato, sem frase de efeito. |
| CA10-8 | Metas com "Fora do app", aeróbico das atividades sem o Saúde e "1 de 2 vezes"; Início com os textos da tela Hoje (B8) e "Também hoje"; Saúde com as atividades. |
| CA10-9 | "Também hoje" na tela Hoje; "Atividades fixas" e as fixas em "Sua semana" na aba Plano; chaves de "Seus dias" só com força + aeróbico (B9); faixa por medida no editor (B-2). |
| CA10-10 | Carga digitada sobrevive ao "Voltar" (A4); cartão aberto depois da última série (B6); "sem carga" na tela Hoje (B11); Trocar em casa (B-5); progressão dos intervalos explicada (B10, F6); evolução sem carga (A5); sessão vazia fora do Histórico (A7); zonas e VO2máx no detalhe do aeróbico (F7). |
| CA10-11 | Abertura: halo inteiro (A7), ordem das pétalas do protótipo com qualquer objetivo (B5) e degradê nas pétalas e no miolo (B6). |
| CA10-12 | As 133 guias do catálogo no bundle, válidas (E1–E10), com os goldens; `CA8-8` e o `CA6-2` do catálogo ligados; folhas dos lotes 4 a 7 para o dono. |
| CA10-13 | (integração) Tudo ligado na raiz, testes cruzados, conferência de mensagens; App build e Core tests verdes em `ci/v8-final`. |

## 7. Incertezas conhecidas

- **Fixa sem "Feito":** a fixa entra no encaixe desde que existe, mas só conta nas metas e na recuperação com "Feito". Se o dono preferir que a fixa conte sozinha depois da hora dela, é uma regra nova (X2), com teste.
- **Cross fora do aeróbico:** escolha conservadora (X3). Se o dono quiser, o cross pode contar uma parte da aula como forte; isso pede um número que a literatura não fixa para a aula inteira.
- **Com um plano só, sem encaixe:** a fixa não muda o dia da sessão; o S6 só age com o seletor por frequência ligado (programas de 4 dias ou mais, RF-39).
- **Registros e o relatório de saúde:** o relatório só é recalculado quando o `HealthViewModel` lê de novo ou quando o `ActivitiesModel` avisa (`activitiesDidChange`). Se o aviso falhar, o cartão de Saúde mostra os minutos novos só na próxima leitura.
- **Horário de verão:** o "Feito" de uma fixa usa o começo do dia mais a hora dela, sem tratar a troca de horário (o Brasil não tem horário de verão desde 2019).
- **F6 no seed instalado:** o Dia B tem 4 blocos de 3–4 min; o caminho é 4 × 3 → 4 × 4 → 5 × 3 → 5 × 4. O "de 3 para 4 e depois 5 blocos" do dono começaria em 3 blocos, o que exigiria mudar o programa já gravado; fica registrado.
- **HealthKit do Cardio:** só o aparelho confirma o tipo do treino no app Saúde, a leitura do pular corda como HIIT e que o relógio não grava em dobro quando a pessoa usa o app Exercício junto.
- **Zonas no Histórico:** dependem de o relógio ter gravado FC no intervalo da sessão e da idade (ou FCmáx) informada; sem isso, a seção não aparece.
- **Guias de objetos de casa:** o vocabulário congelado não tem mochila, garrafa nem sacola; o desenho usa o acessório mais próximo. As folhas dos lotes 4 a 7 vão para o dono revisar (T6.8).
- Só o aparelho confirma: o degradê da abertura a 120 Hz, o halo no fundo claro e escuro, e a folha de registro com Dynamic Type grande.
