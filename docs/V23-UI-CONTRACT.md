# Contrato da versão 2.3: onda de telas

Versão 1 · 2026-09-28. Base: o commit do `main` que traz este arquivo, com o andaime T9.0 (`473345a`, `29d1256` e `cfb6b39`). Os worktrees `C:\Users\leona\Developer\pt-wt\w7-*` partem dele.

O núcleo da 2.3 (`docs/V23-CORE-CONTRACT.md`: carga opcional no motor, minutos, Equilibrado, Cardio e as 55 guias do "Como fazer") já está no `main`: merge `f0bcce4`, com Core tests 36388566363 e App build 36388568579 verdes. O andaime também está verde: `473345a` (Core tests 36390822121, App build 36390822220), `29d1256` (Core tests 36412508798, App build 36412508859) e `cfb6b39` (App build 36413506369). Este contrato cobre as telas.

**Pedidos do dono** (`docs/design/v23-owner-notes.md`, itens 1 a 18; SPEC decisão 20). Eles prevalecem sobre qualquer proposta, e os itens 15 a 18 prevalecem sobre os anteriores:

| # | Decisão | Onde entra |
|---|---|---|
| 1 | O objetivo `endurance` se chama **Cardio**, com o subtítulo "Coração forte e mais condicionamento" (o raw value não muda). | andaime (feito), `plans-core` (seed e textos) |
| 2 | **Carga opcional**: marcar série e exercício nunca pede carga; o app sugere com delicadeza ("Anotar a carga ajuda a sugerir quando subir"), no máximo uma vez por exercício, com dispensa. | `session` |
| 3, 6, 13 | **Abertura** do protótipo aprovado (`docs/design/v23-animation/launch.html`, com amanhecer de areia e pétala do objetivo), tela de lançamento azul-marinho com a flor ([PROJ]), Reduzir Movimento, nunca bloqueia, só a frio. O resultado da crítica vale: sem vibração. | `launch` |
| 14 | **Pólen**: entra, discreto, na abertura (pedido explícito do dono). | `launch` |
| 4, 9, 11 | **Mais de um plano ao mesmo tempo**, com o encaixe na semana (dias, 2 sessões por dia, 48 h por grupo, A5, descanso), as saídas quando não cabe (cada uma com a semana resultante) e as consequências positivas, negativas e neutras. A tela Hoje mostra as sessões do dia. | `plans-core`, `plans-ui` |
| 8 | **Plano Cardio para o VO2máx**: A base contínua, B 4 × 4, C longo e leve (o D, tiros curtos, fica fora nesta versão). | `plans-core` |
| 7 | Sem cardio obrigatório nos outros planos. | nada muda |
| 10, 12 | O "Por quê?" explica Hipertrofia × Força e Força × Combate; Força + Combate e Hipertrofia + Força são "grande sobreposição". | `plans-core` |
| 14 | **Direção visual A · Tinta e papel** (`docs/design/v23-aesthetics/directions.html`), só no visual (itens 15 e 16). | `ink` |
| 14 | **Desenhos do "Como fazer" aprovados**: entram as folhas e os botões. | `session` |
| 14, 15 | **Tela inicial nova** antes do treino do dia: a flor pintada, uma saudação, um resumo calmo da semana e o caminho para a tela Hoje. **Sem mensagem do dia** e sem citação (item 15). | `home` |
| 16 | **Sem mensagens em nenhum lugar do app**: nenhuma citação, frase inspiracional, mensagem estoica ou budista, "mensagem do dia" ou frase de efeito, em tela alguma. Os avisos funcionais do diálogo (§7.11 C1–C8) continuam. | todas (§1 regra 7) |
| 17 | **Tela "Metas da semana"**, aberta pelo Início: sessões de cada plano, músculos, aeróbico, sono e, com Longevidade, equilíbrio e mobilidade; marcas de tinta, "sem dados" em vez de falha. | `home` |
| 18 | **Passos só com Longevidade ou Cardio**, nas Metas e em qualquer outro lugar (cartão e detalhe de Saúde, sugestão de passos baixos). | `home` |

Não há tarefa de mensagens: a versão anterior deste rascunho previa uma, e ela foi cortada pelos itens 15 e 16. Nenhuma tarefa cria arquivo de citações.

**Regras de domínio:** SPEC RF-01, RF-17, RF-31, RF-40, RF-44, RF-45, RF-46, RF-47, RF-48, RF-49 a RF-52, §7.3 S8, §7.14, §7.15 (M1 a M9), §7.16 (W1 a W7) e decisões 18 a 20. **Design:** DESIGN.md 1.4 (§3, §4, §6, §8, §9, §10, §13 e §14).

**Fora deste contrato:** SchemaV3 e qualquer mudança em `Persistence/Schema/`, `SessionEvent`, sync e formato do backup (o backup só passa a aceitar 2 planos ativos na validação); HealthKit do Cardio e semana leve em minutos (SPEC F5, próxima onda); zonas de FC no Cardio; o dia D (tiros curtos) do Cardio; blocos que crescem no 4 × 4 (exige regra nova no motor); app do Watch.

## 0. Como testar sem compilador local

Vale o `docs/V2-FINAL-CONTRACT.md` §0. O Smart App Control bloqueia o Swift nesta máquina, e essa configuração não se mexe.

- Comece todo comando PowerShell com `Set-Location` para o **seu** worktree. Nunca edite `C:\Users\leona\Developer\PersonalTrainer` diretamente.
- Antes de cada push, releia inteiro cada arquivo que você alterou: tipos, imports, `@MainActor`/`Sendable`, inits, `switch` exaustivos, rótulos de argumento, fechamentos de chaves, `some View` com um só tipo de retorno.
- Configure o push antes: `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"`.
- CI: `git push origin HEAD:ci/v7-<key>`. Todo push para `ci/**` roda o App build (20 a 30 min). Se o commit toca `Packages/**` ou `PersonalTrainer/Resources/Seed/**`, roda também o Core tests. A coluna "Expected" de §2 diz quantos workflows esperar.
- Espere com `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\watch-ci.ps1 -Sha <sha completo> -Minutes 9 -Expected <N>` e repita a chamada até ele dizer que todos terminaram.
- Corrija pelas anotações. No máximo 5 rodadas de CI por tarefa. No fim, com o CI verde, faça `git push origin v7/<key>`.
- Em `@Test(arguments:)`, declare os casos antes, como constantes com tipo explícito (armadilha do Swift 6.3 no Linux, HANDOFF §2).
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No PowerShell 5.1, passe a mensagem por arquivo (`git commit -F <arquivo>`), gravado em UTF-8 **sem BOM** (`[System.IO.File]::WriteAllText(<arquivo>, <texto>, (New-Object System.Text.UTF8Encoding($false)))`): aspas dentro de `-m` quebram o comando, e o `Set-Content -Encoding utf8` põe um BOM no assunto.
- O relatório traz: o que foi feito, os CAs cobertos, a lista **Verificado** e **Incerto** (AGENTS R11), o sha do último run verde e os achados fora do escopo.

## 1. Regras desta rodada

1. **Escopo exclusivo por arquivo** (§4). Arquivo novo só dentro das pastas da sua tarefa. Se precisar de um arquivo de outra tarefa, pare e reporte; não edite.
2. **Não edite** `SPEC.md`, `TASKS.md`, `AGENTS.md`, `DESIGN.md`, `ARCHITECTURE.md`, `docs/HANDOFF.md`, `docs/design/v23-owner-notes.md` nem este contrato. O arquiteto já os atualizou; o integrador marca o estado.
3. **`App/*` é do integrador** (`RootView.swift`, `AppEnvironment.swift`, `AppEnvironment+Factories.swift`, `PersonalTrainerApp.swift`). Ninguém mais toca. O que cada tarefa entrega para ser ligado está em "Entrega ao integrador".
4. **Congelado** (§3): as assinaturas do andaime, os nomes dos tokens do `Theme`, os raw values persistidos, os ids e slugs do seed, `ExerciseInfoSheet(content:references:onSubstitute:onSkip:)`, `ExerciseInfoContent(planned:measure:lastSession:)`, `SessionFlowView(sessionID:environment:onClose:)`, `HomeView` e `ProgramTabView` (parâmetros novos só com padrão), as funções públicas de `TodayTargetText` e `MeasureText` (as saídas podem mudar só onde §4 manda), o tipo `WeeklyFrequencyCard` com as funções estáticas dele e o formato das guias. Quem precisar mudar algo congelado para e reporta.
5. **Requisito novo em protocolo** vem com padrão na extensão, como no andaime. Quem implementa o requisito usa **exatamente** a assinatura do protocolo: com um rótulo ou tipo diferente, o Swift usa o padrão em silêncio.
6. **AGENTS:**
   - R1: `TrainerCore` só usa Foundation. R2/P12: nada de FC no `Engine`, no encaixe, nas metas nem na intensidade do cardio (teste da fala). R3: nenhum `Date()` no `TrainerCore`.
   - R4: views não escrevem no `ModelContext`; sessão só pelo `SessionCoordinating`, programa só pelo `ProgramRepositoring`.
   - R8: nada de `PersistentIdentifier` fora de `Persistence/`. R9: efeito externo com protocolo + Live + Fake.
   - R11: nada de `fatalError`, `try!` ou força-unwrap fora de testes; lista Verificado/Incerto.
   - §4: um tipo público por arquivo, textos pt-BR fixos, `os.Logger`, sem `print`. §7: nenhuma permissão pedida no launch nem nas Metas da semana.
   - R7: toda regra nova tem teste com o nome da regra (`@Test("M4 …")`, `@Test("W2 …")`, `testM6_…`, `testRF49_…`).
7. **Textos** em pt-BR, curtos, no tom do DESIGN §6 e §7. Nenhum texto novo cita RIR (RF-41, decisão 18) nem FC para prescrever. **Nenhuma citação, frase inspiracional, mensagem estoica ou budista, "mensagem do dia", elogio ou frase de efeito em tela alguma** (itens 15 e 16; DESIGN §6): nem no Início, nem na abertura, na sessão, no resumo, nos estados vazios ou no Ajustes. Os textos dizem o fato e o que fazer ("Hoje é dia de descanso.", "3 de 4 sessões"). Os avisos funcionais do diálogo (C1–C8) continuam como estão.
8. **Visual:** use os tokens do `Theme` e os componentes do DesignSystem (`paperBackground()`, `inkCard()`, `FlowerView`, `EnsoRingView`, `InkMarkView`, `MountainWashView`, `PrimaryButtonStyle`). Nada de hexadecimal solto, anéis concêntricos, confete, vermelho fora de erro, halteres fora do "Como fazer" (DESIGN §1, §9, §12, §14).

## 2. Mapa das tarefas

| Chave | TASKS | Worktree | Branch | CI | Expected | Pesada |
|---|---|---|---|---|---|---|
| `ink` | T9.1 | `C:\Users\leona\Developer\pt-wt\w7-ink` | `v7/ink` | `ci/v7-ink` | 1 | não |
| `launch` | T9.2 [PROJ] | `C:\Users\leona\Developer\pt-wt\w7-launch` | `v7/launch` | `ci/v7-launch` | 1 | não |
| `home` | T9.3 | `C:\Users\leona\Developer\pt-wt\w7-home` | `v7/home` | `ci/v7-home` | 2 | não |
| `session` | T9.4 | `C:\Users\leona\Developer\pt-wt\w7-session` | `v7/session` | `ci/v7-session` | 1 | sim |
| `plans-core` | T9.5 | `C:\Users\leona\Developer\pt-wt\w7-plans-core` | `v7/plans-core` | `ci/v7-plans-core` | 2 | sim |
| `plans-ui` | T9.6 | `C:\Users\leona\Developer\pt-wt\w7-plans-ui` | `v7/plans-ui` | `ci/v7-plans-ui` | 1 | sim |
| integrador | T9.7 | `C:\Users\leona\Developer\pt-wt\w7-integration` | `v7/integration` | `ci/v7-final` | 2 | — |

Nenhuma tarefa depende do código de outra para compilar: o que é compartilhado está no andaime (§3), com padrões. As telas de uma tarefa podem aparecer "sem" a parte da outra no próprio CI (por exemplo, a `plans-ui` vê o encaixe sempre "cabe", e as Metas da `home` veem as sessões dos planos vazias); o comportamento completo só existe na integração.

## 3. Andaime (já no `main`; congelado)

Os commits `feat(v2.3 T9.0 scaffold)` trouxeram as assinaturas abaixo. As bodies marcadas "stub" são da tarefa dona; as outras já valem.

### 3.1 `TrainerCore/Plans` (dona: `plans-core`)

| Tipo | O que é | Estado |
|---|---|---|
| `PlanWeekday` (Int, 0 = segunda … 6 = domingo) | `shortName` ("Seg"), `name` ("segunda"), `next`, `distance(to:)` (0…3, semana que se repete), `of(_:calendar:)` | pronto |
| `CardioIntensity` (`light`, `moderate`, `vigorous`) | `classify(slug:sets:repMax:)`: intervalos (sets ≥ 2) ou `run-intervals`/`bike-intervals`/`jump-rope` → forte; repMax ≥ 60 → leve; senão moderado. `rank` | pronto |
| `PlanSessionKind` (`strength`, `cardio`) | | pronto |
| `PlanSessionDemand` | `programDayID`, `dayName`, `kind`, `primaryMuscles`, `isLowerBody`, `cardioIntensity`, `estimatedMinutes` | pronto |
| `PlanDemand` | `programID`, `goal`, `name`, `sessions` (na ordem da rotação; `sessions[0]` é a sessão do começo da semana, M3), `sessionsPerWeek`, `isCardio`, `lowerBodyGroups`, `from(program:exercises:sessionsPerWeek:minutesPerDay:)` (começa pelo primeiro dia; quem chama roda para a fase) | pronto |
| `WeekPreferences` (Codable) | `availableDays`, `allowsTwoSessionsPerDay`, `allowsLightCardioAfterStrength`, `sessionsPerWeek: [UUID: Int]`, `defaultAvailableDays` (seg a sáb), `.default` | pronto |
| `PlannedSlot` | `weekday`, `programID`, `indexInWeek`, `kind`, `orderInDay` e, com padrão, `programDayID: UUID?`, `dayName: String`, `cardioIntensity: CardioIntensity?` (o dia previsto nesta semana) | pronto |
| `WeekSchedule` | `slots` (ordenados), `notes`, `.empty`, `slots(on:)`, `restDays` | pronto |
| `FitNote` | `noFullRestDay`, `strengthBeforeCardio(PlanWeekday)` | pronto |
| `FitProblem` | `notEnoughDays(needed:available:)`, `muscleRecovery`, `cardioBeforeLegs` | pronto |
| `FitChange` | `addDays([PlanWeekday])`, `allowTwoSessionsPerDay`, `allowLightCardioAfterStrength`, `fewerSessions(programID:perWeek:)`, `applied(to:)` | pronto |
| `FitAlternative` | `changes`, `preferences`, `schedule` | pronto |
| `FitResult` | `schedule?`, `problems`, `alternatives`, `fits`, `.unchecked` | pronto |
| `WeeklyFit.fit(_:preferences:) -> FitResult` | M4 e M5 | **stub** (devolve `.unchecked`) |
| `PlanConsequenceKind`, `PlanConsequence` (`kind`, `text`, `referenceTopic`) | | pronto |
| `PlanCombination.consequences(_:_:)`, `isLargeOverlap(_:_:)` | M7 | **stub** (vazio / `false`) |
| `ActivePlanOrder` | `maxActivePlans` = 2, `goalPriority`, `rank(of:)`, `sorted(_:)` (M1) | pronto |
| `PlanWeekProgress` | `programID`, `goal`, `completed`, `perWeek` (W2) | pronto |

A dona pode acrescentar tipos, membros e arquivos em `Plans/`; não muda nem tira o que está acima. `PlansScaffoldTests.swift` é dela.

### 3.2 DesignSystem (dona: `ink`)

| Símbolo | Estado |
|---|---|
| `Theme`: tokens `background`, `surface`, `textPrimary`, `textSecondary`, `accent`, `onAccent`, `accentSoft`, `inkMuted`, `line`, `goalHypertrophy`, `goalStrength`, `goalEndurance`, `goalLongevity`, `goalCombat`, `health`, `destructive`, `flowerCenter` | valores da direção A já aplicados (DESIGN §3); a `ink` ajusta só com os contrastes do DESIGN §3 |
| `FlowerView(activeGoal:size:)` e `FlowerView(activeGoals:size:)`; `activeGoals` (o principal primeiro), `activeGoal` | pronto; o desenho em aguada é da `ink` |
| `BrisaGeometry` (`internal`): `unitPetalOutlines`, `unitCenterOutline`, `path(for:in:)`; `BrisaPetalShape`, `BrisaCenterShape` | congelado (a abertura usa) |
| `View.paperBackground()` | stub: fundo liso |
| `View.inkCard(cornerRadius: CGFloat = 16)` | stub: `surface` com canto |
| `EnsoRingView(progress: Double, diameter: CGFloat = 48)` | stub: arco simples |
| `InkMarkView(progress: Double, tint: Color = Theme.inkMuted, hasData: Bool = true)` | stub: trilho e preenchimento simples; ocupa a largura que receber, 6 pt de altura |
| `MountainWashView()` | stub: não desenha nada |
| `GoalFlowerAnchorKey` e `View.publishesGoalFlowerAnchor()` | pronto; congelado |
| `PrimaryButtonStyle` / `.primary` | como está |

`GoalStyle.swift` (cor, símbolo, subtítulo, pétala) fica com a `plans-ui`; o subtítulo do Cardio já está no andaime.

### 3.3 App: planejamento e programas (dona: `plans-core`)

`SessionPlanning` ganhou, com padrões na extensão:

```swift
func activeProgramGoals() throws -> [ProgramGoal]                    // padrão: [activeProgramGoal()]
func todayOverview(now: Date) throws -> TodayOverview                 // padrão: nextPlan(now:) como sessão única
func nextPlan(forProgramID programID: UUID, now: Date) throws -> SessionPlan?   // padrão: nextPlan se o programa bater
func days(ofProgramID programID: UUID) throws -> [ProgramDayTemplate] // padrão: activeProgramDays()
func weekSchedule(now: Date) throws -> WeekSchedule?                  // padrão: nil
func weekPreferences() -> WeekPreferences                             // padrão: .default
func saveWeekPreferences(_ preferences: WeekPreferences) throws       // padrão: nada
func fitCheck(programIDs: [UUID], preferences: WeekPreferences, now: Date) throws -> FitResult  // padrão: .unchecked
func planWeekProgress(now: Date) throws -> [PlanWeekProgress]         // padrão: []
func weeklyFrequency(now: Date) throws -> WeeklyFrequencyReport       // padrão: completedSessionSummaries() com a meta 2×, semana na segunda, calendário do aparelho
```

DTOs em `Services/Planning/` (congelados; a `plans-core` pode acrescentar membros com padrão):

```swift
struct TodaySession: Sendable, Hashable, Identifiable { let plan: SessionPlan; let goal: ProgramGoal; let isDoneToday: Bool; var id: UUID }  // id = programID
struct TodayOverview: Sendable, Hashable {
    let sessions: [TodaySession]; let otherSessions: [TodaySession]; let isRestDay: Bool; let fitsWeek: Bool
    init(sessions:otherSessions: = [] isRestDay: = false fitsWeek: = true); static let empty; var nextPending: TodaySession?
}
```

`ProgramRepositoring` ganhou `addActivePlan(programID:)` e `removeActivePlan(programID:)`, com padrão que lança `invalidParameters`. `activate(programID:)` continua deixando um plano só.

### 3.4 Cardio (feito no andaime)

`ProgramGoal.endurance.displayName` = "Cardio"; `subtitle` = "Coração forte e mais condicionamento"; o programa `09AB286E-…` se chama "Cardio"; a explicação `goal.endurance` começa por "Cardio". Os testes que dependiam do nome já mudaram. O resto do plano (VO2máx, resumo, referências) é da `plans-core`.

## 4. Tarefas

### 4.1 `ink` — sistema visual Tinta e papel (T9.1)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/DesignSystem/*`, **menos** `GoalStyle.swift` (da `plans-ui`) e `GoalFlowerAnchor.swift` (congelado). Pode criar arquivos novos na pasta.
- `PersonalTrainer/Resources/Assets.xcassets/PaperFiber.imageset/*` (novo).
- `docs/design/v23-ink/*` (novo): o gerador da textura e as folhas de conferência.
- Passada de pele nas pastas que nenhuma outra tarefa tem: `Features/Settings/*`, `Features/Coach/*` e `Features/References/*`. Só troque fundo e cartões (`.background(Theme.background)` → `.paperBackground()`; o fundo `surface` dos cartões → `.inkCard()`), sem mexer em lógica, texto ou navegação. `Features/History/*` e `Features/Health/*` são da `home`.
- Testes: `PersonalTrainerTests/Features/DesignSystem/InkDesignTests.swift` (novo).

**O que fazer** (DESIGN §3, §4, §14; directions.html, direção A):
1. **Paleta:** confira os valores da direção A no `Theme` e deixe os hexadecimais acessíveis a teste (por exemplo, uma tabela interna de pares claro/escuro que o `dynamic` usa). Mantenha Aumentar Contraste (`textSecondary` → `textPrimary`; cartões com borda de 1 pt em `textSecondary`).
2. **Papel:** `PaperFiber` = PNG de 256 px, ladrilhável, gerado por script PowerShell determinístico (fibras de washi, gerador com semente fixa, nada de aleatório de verdade), com versões clara e escura no mesmo imageset. `paperBackground()` desenha `Theme.background` e a fibra ladrilhada a 4 %, só no fundo, ignorando as áreas seguras; some com Aumentar Contraste (`colorSchemeContrast == .increased`).
3. **Cartões:** `inkCard()` = `surface`, canto contínuo, fio de 0,5 pt em `Theme.line` (1 pt em `textSecondary` com Aumentar Contraste). Sem sombra.
4. **Flor em aguada** (`FlowerView`, mesmas duas formas de `init`): pétalas fora dos objetivos com lavagem de tinta a 7 % e contorno fino no tom das legendas; pétala de cada objetivo ativo em pigmento, mais escura na base e mais clara na ponta (nōtan, degradê pelo eixo da pétala); miolo areia. A partir de 120 pt, uma borda de tinta levemente mais escura dá o "pintado" (sem desfoque, sem textura animada). Tudo determinístico; a mesma flor a 26, 56, 92 e 168 pt. O rótulo do VoiceOver continua.
5. **Ensō** (`EnsoRingView`): traço de pincel aberto (vão de cerca de 30°), que começa mais grosso e afina, pintado de 0 até `progress`; o trilho não pintado em `Theme.line`; os últimos 8 % do traço pintado em "branco voador" (3 fios finos com falhas fixas). `Canvas`, sem animação própria (quem chama anima o `progress` no ritmo de 1 s).
6. **Marca de tinta** (`InkMarkView`): o mesmo pincel do ensō, reto, da esquerda para a direita, pintado até `progress` na cor `tint`, com o trilho em `Theme.line`; com `hasData` falso, só o trilho pontilhado. Mesma assinatura do andaime; decorativa (`accessibilityHidden`).
7. **Aguada de montanha** (`MountainWashView`): duas silhuetas de montanha em curvas, em `textPrimary` a 7 % e 4 %, com a base esmaecendo por degradê. Parada. Ocupa o quadro que receber.
8. **Botão principal:** `PrimaryButtonStyle` continua com 56 pt, `accent` e `onAccent`; ajuste só o canto e o estado pressionado, se preciso.
9. **Folha de conferência** (sem simulador, é o único jeito de ver): `docs/design/v23-ink/ink-sheet.png` e `ink-sheet-dark.png`, desenhadas pelo script com os mesmos números do Swift: a flor em 56 e 168 pt com 0, 1 e 2 objetivos, o ensō em 0, 0,5 e 1, a marca de tinta em 0, 0,6, 1 e sem dados, a aguada, um cartão sobre o papel e as amostras da paleta com os contrastes. Abra os PNG e confira.
10. **Pele** nas pastas sem dono (acima).

**Testes:** `testDESIGN3_textTokensPassAA` (texto ≥ 4,5:1 contra `background` e `surface`, claro e escuro, pela fórmula da WCAG sobre os hexadecimais); `testDESIGN3_goalColorsPassAA`; `testDESIGN3_accentOnAccentSoftPassesAA`; `testFlower_activeGoalsOrder` (o primeiro é o principal; `activeGoal` = primeiro; vazio sem objetivo); `testEnso_progressIsClamped`; `testInkMark_progressIsClamped`.

**Entrega ao integrador:** nada a ligar (os componentes já são usados pelas outras tarefas).

**Aceite:** App build verde em `ci/v7-ink`; folhas conferidas; CA9-1.

### 4.2 `launch` — abertura com a flor e tela de lançamento (T9.2 [PROJ])

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Launch/*` (novo): por exemplo `LaunchTimeline.swift`, `LaunchFrame.swift`, `LaunchPollen.swift`, `LaunchCurve.swift` (Bézier cúbica igual à do protótipo), `LaunchFlowerGeometry.swift`, `LaunchOverlay.swift`.
- `project.yml` (**[PROJ]**, só as chaves abaixo).
- `PersonalTrainer/Resources/Assets.xcassets/LaunchBackground.colorset/*` e `LaunchFlower.imageset/*` (novos).
- `docs/design/v23-animation/render-launch-assets.ps1` (novo) e a folha `launch-assets-check.png`.
- Testes: `PersonalTrainerTests/Features/Launch/LaunchTimelineTests.swift` (novo).

**O que fazer** (SPEC RF-50; DESIGN §10; protótipo `docs/design/v23-animation/launch.html`, que é a fonte dos números):
1. **Tela de lançamento ([PROJ]):** em `project.yml`, `UILaunchScreen: {UIColorName: LaunchBackground, UIImageName: LaunchFlower}` e `UIStatusBarHidden: true`. Nada mais muda no arquivo. `LaunchBackground` = `#24354C` (escuro `#141D29`); `LaunchFlower` = a flor Brisa com o halo, fundo transparente, 256 pt de largura (@2x e @3x, claro e escuro), gerada pelo script a partir da mesma geometria do ícone (`docs/design/render-app-icon.ps1`).
2. **`LaunchTimeline`**, função pura do tempo, com os números do protótipo (`TL`, `D.warm`, `D.handoff`, `D.pollen`, `ORDER`, curvas): `static func frame(at t: Double, reduceMotion: Bool, dark: Bool, hasGoal: Bool) -> LaunchFrame`. O `LaunchFrame` traz giro, respiro, halo, por pétala (cresce, desliza, opacidade), miolo (escala, opacidade), amanhecer, véu de areia (`warm`), cor da pétala do objetivo (`goalTint`), florzinha (`goalHeader`), conteúdo, escala da tela (`todayScale`), barra de status visível e os 8 grãos de pólen (posição, raio, opacidade). Total 0,92 s; com Reduzir Movimento, 0,60 s.
3. **Pólen** (item 14): os 8 grãos do protótipo (`D.pollen`: ângulo, início, vida, raio inicial e final, tamanho, opacidade, curva e `curl`), na cor `#F5EBD7` (escuro `#E6DAC3`), desenhados na `Canvas` junto da flor grande. Com Reduzir Movimento, não aparecem (é movimento). Números fixos, nada sorteado.
4. **Sem vibração.** A crítica do protótipo cortou (vibrar quer dizer "feito", DESIGN §10), o dono mandou não sobrepor o resultado dela (item 13) e só pediu o pólen de volta (item 14).
5. **Sem texto:** a abertura não mostra palavra nenhuma (item 16).
6. **`LaunchOverlay`** como modificador, com esta assinatura congelada para o integrador:

   ```swift
   extension View {
       /// Abertura a frio (SPEC RF-50). `goals`: objetivos ativos, o principal primeiro (tinge a pétala dele).
       /// Com `isEnabled` falso, devolve o conteúdo sem nada por cima e com a barra de status visível.
       func launchOverlay(goals: [ProgramGoal], isEnabled: Bool, onFinished: @escaping () -> Void) -> some View
   }
   ```
   - `TimelineView(.animation(paused:))` dá o relógio; uma `Canvas` desenha fundo, amanhecer, véu, flor grande (caminhos de `BrisaGeometry`, montados uma vez), miolo e pólen, como no trecho SwiftUI do protótipo.
   - O conteúdo de baixo recebe `.scaleEffect(todayScale)` e já está montado e aceitando toques desde o primeiro quadro: a camada tem `allowsHitTesting(false)`, e um `simultaneousGesture` de toque no conteúdo adianta a abertura para o fim em 0,15 s (o toque também chega ao botão tocado).
   - A florzinha de verdade (`FlowerView(activeGoals:size:)`) aparece na moldura publicada pela tela inicial (`overlayPreferenceValue(GoalFlowerAnchorKey.self)`), como no protótipo. Sem moldura publicada, ela não aparece e o resto segue igual.
   - `.statusBarHidden(!frame.statusBarVisible)` durante a abertura; no fim, `false`. Sem objetivo, nada cora (`hasGoal` falso). No modo escuro, sem véu de areia.
   - Ao terminar (ou depois do salto), a camada sai da hierarquia e chama `onFinished` uma vez.

**Testes** (XCTest, tabela de tempos): `testRF50_firstFrameMatchesLaunchScreen` (t = 0: azul cheio, flor inteira, sem conteúdo); `testRF50_endFrame` (t = 0,92: conteúdo 1, escala 1, pétalas 0, barra visível); `testRF50_reduceMotion` (sem giro, sem respiro, sem pólen, fim em 0,60); `testRF50_darkHasNoWarmVeil`; `testRF50_noGoalNoTint`; `testRF50_pollenGrainsLiveOnlyInTheirWindow` (cada grão com opacidade 0 fora de `t0…t0+life`); `testRF50_deterministic`; `testRF50_goalPetalFadesLast`.

**Entrega ao integrador:** `launchOverlay(goals:isEnabled:onFinished:)` e as chaves do `project.yml`.

**Aceite:** App build verde em `ci/v7-launch`; `launch-assets-check.png` conferida; CA9-2.

### 4.3 `home` — o Início, as Metas da semana e os passos (T9.3)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Landing/*` (novo): por exemplo `LandingView.swift`, `LandingViewModel.swift`, `LandingText.swift`, `WeekMarksView.swift`, `WeeklyGoalsView.swift`, `WeeklyGoalRow.swift`, `WeeklyGoalsText.swift`.
- `PersonalTrainer/Features/History/*`: tirar o `WeeklyFrequencyCard` do `HistoryListView` (RF-17) e a pele (`paperBackground()`, `inkCard()`). O tipo `WeeklyFrequencyCard`, o `init(references:)` e as funções estáticas ficam (são testados em `HomeViewModelTests`, da `plans-ui`), e as Metas podem usar `muscleName`, `visibleEntries` e `weekRangeText`.
- `PersonalTrainer/Features/Health/*`: os passos só com Longevidade ou Cardio (W7) e a pele.
- `PersonalTrainer/PreviewSupport/LandingPreviewSupport.swift` (novo) e `PreviewSupport/HealthPreviewSupport.swift`.
- TrainerCore (novos): `Sources/TrainerCore/Summary/WeeklyGoalKind.swift`, `WeeklyGoal.swift`, `WeeklyGoalsInput.swift`, `WeeklyGoals.swift` e `Tests/TrainerCoreTests/WeeklyGoalsTests.swift`.
- Testes do app: `PersonalTrainerTests/Features/Landing/*` (novo), `Features/HealthViewModelTests.swift`, `Features/History/*`.

**Assinaturas congeladas para o integrador:**

```swift
@Observable @MainActor final class LandingViewModel {
    init(
        planner: any SessionPlanning,
        coordinator: any SessionCoordinating,
        now: @escaping () -> Date,
        calendar: Calendar = .autoupdatingCurrent,
        healthReport: @escaping @MainActor () -> HealthReport? = { nil },      // nil = sem o app Saúde (W4)
        loadHealth: @escaping @MainActor () async -> Void = {},                 // lê o Saúde se já autorizado; nunca pede
        longevityDone: @escaping @MainActor () -> Set<String> = { [] }          // CoachInput.balanceKey / mobilityKey desta semana (C8)
    )
    func refresh()
}

struct LandingView: View {
    init(model: LandingViewModel, references: ReferenceCatalog,
         onOpenToday: @escaping () -> Void, onOpenSession: @escaping (UUID) -> Void)
}

// HealthViewModel (Features/Health): parâmetro novo, no fim do init atual.
//     showsSteps: @escaping @MainActor () -> Bool = { true }

// TrainerCore
public enum WeeklyGoals {
    public static func goals(_ input: WeeklyGoalsInput) -> [WeeklyGoal]      // W2–W4, W7
    public static func showsSteps(activeGoals: [ProgramGoal]) -> Bool        // W7: Longevidade ou Cardio entre os ativos
}
```

Sugestão para o resto da API do `TrainerCore` (é só da `home`; pode ajustar, com um tipo público por arquivo):

```swift
public enum WeeklyGoalKind: String, Sendable, Hashable, CaseIterable { case planSessions, muscles, aerobic, steps, sleep, balance, mobility }
public struct WeeklyGoal: Sendable, Hashable {
    public let kind: WeeklyGoalKind
    public let programID: UUID?; public let planGoal: ProgramGoal?        // só em planSessions
    public let done: Double?                                               // nil = sem dados (W4)
    public let target: Double                                              // > 0
    public let referenceTopic: String                                      // W5
    public var hasData: Bool; public var fraction: Double; public var isMet: Bool   // W3
}
public struct WeeklyGoalsInput: Sendable, Hashable {
    public let plans: [PlanWeekProgress]; public let activeGoals: [ProgramGoal]
    public let frequency: WeeklyFrequencyReport; public let health: HealthReport?
    public let longevityDone: Set<String>; public let targets: HealthTargets   // padrão HealthTargets()
}
```

**O que fazer:**
1. **Início** (SPEC RF-49; DESIGN §9.1 e §14), de cima para baixo, com muito espaço livre (ma):
   - `MountainWashView` no canto de cima, atrás de tudo (cerca de 55 % da largura, 140 pt de altura);
   - a data em `textSecondary` ("segunda-feira, 28 de setembro", pt-BR, fuso da pessoa);
   - a flor grande (`FlowerView(activeGoals:size: 168)`) centralizada, com `.publishesGoalFlowerAnchor()`;
   - a saudação em New York: "Bom dia" (5h00–11h59), "Boa tarde" (12h00–17h59), "Boa noite" (18h00–4h59); embaixo, os objetivos ativos em `textSecondary` ("Hipertrofia · Cardio"; sem objetivo, "Escolha um objetivo para começar");
   - "Esta semana": 7 marcas de segunda a domingo (`WeekMarksView`: ponto de tinta cheio nos dias com sessão concluída com ao menos uma série; hoje com um anel fino; os outros vazios) e a frase "2 sessões nesta semana." / "1 sessão nesta semana." / "Nenhuma sessão nesta semana ainda.". Nada de meta, "faltam" ou porcentagem. O bloco inteiro é um botão (com "›" discreto) que empurra as **Metas da semana** numa `NavigationStack` própria da tela;
   - o caminho para hoje, num `inkCard()` com o rótulo pequeno "Hoje" e o único botão proeminente da tela.
   - **Nenhuma mensagem, citação ou frase de efeito** (itens 15 e 16). Não crie arquivo de citações.
2. **Estados do caminho** (dados de `todayOverview(now:)` e `coordinator.activeSession`):
   - sessão em andamento: "Sessão em andamento: Dia A — Superior" e o botão **"Retomar a sessão"** → `onOpenSession(id)`;
   - sessões hoje: os nomes dos dias pendentes ligados por " + " ("Dia A — Superior + Dia B — Base contínua"); uma sessão: "5 exercícios · ≈ 55 min"; duas: "2 sessões · ≈ 85 min"; botão **"Ver a sessão de hoje"** → `onOpenToday()`;
   - todas feitas hoje: "Tudo feito por hoje." e o botão **"Ver o dia"**;
   - dia de descanso (dois planos): "Hoje é dia de descanso." e o botão **"Ver o dia"**;
   - sem objetivo: "Escolha um objetivo para ver a sua primeira sessão." e o botão **"Escolher um objetivo"** → `onOpenToday()` (a folha "Seu objetivo" abre pela tela Hoje).
3. Sem diálogo, sem cartão de Saúde, sem números grandes, sem anéis concêntricos (DESIGN §9.6). Fundo `paperBackground()`.
4. **VoiceOver:** a flor escondida (os objetivos já estão em texto); as marcas da semana num elemento só ("Esta semana: sessão na segunda e na quarta"); o botão com o rótulo do estado.
5. O modelo relê em `refresh()` (o integrador chama ao aparecer, ao voltar para a aba e ao voltar ao primeiro plano). Falha de leitura vira log e a frase "Não foi possível ler a semana." no lugar das marcas; o botão para a tela Hoje continua.
6. **Metas da semana** (SPEC RF-52, §7.16 W1–W7; DESIGN §9.2):
   - `WeeklyGoals.goals` em `TrainerCore`, função pura: as metas na ordem de W2, a fração e "cheia" de W3, "sem dados" de W4, os tópicos de W5 e os passos de W7. Entradas: `planWeekProgress(now:)`, `activeProgramGoals()`, `weeklyFrequency(now:)`, `healthReport()`, `longevityDone()` e `HealthTargets()`;
   - a tela: título "Metas da semana" em New York e o intervalo da semana; uma linha por meta com o nome, o número em palavras ("3 de 4 sessões", "6 de 10 grupos 2 vezes", "95 de 150 min", "média de 6.200 por dia", "média de 7 h 20 min", "Feito nesta semana" / "Ainda não marcado nesta semana"), o `WhyButton` do tópico e a `InkMarkView` (cor do objetivo nas sessões de cada plano; `inkMuted` no resto; `hasData` falso em "sem dados"); embaixo dos músculos, os grupos com meta em duas colunas ("Peito 1 de 2"); no fim, "Aeróbico, passos e sono vêm do app Saúde." quando alguma dessas metas está sem dados;
   - ao abrir, chama `loadHealth()` e relê. Nunca pede permissão ao Saúde (AGENTS §7);
   - sem plano ativo, a linha de sessões diz "Escolha um objetivo para ter metas de treino.";
   - VoiceOver: cada linha é um elemento ("Hipertrofia: 3 de 4 sessões nesta semana"); a marca é decorativa.
7. **Histórico sem o painel** (RF-17): o `HistoryListView` perde o `WeeklyFrequencyCard` e fica só com as sessões; pele de papel.
8. **Passos só com Longevidade ou Cardio** (W7, item 18): `HealthViewModel` ganha `showsSteps` (assinatura acima). Com ele falso, `visibleSuggestions` tira `.lowSteps` (isso também tira a sugestão do feed do diálogo, que lê essa lista), o `HealthCardView` não mostra a linha de passos e o `HealthDetailView` não mostra a seção de passos. O padrão `{ true }` mantém o comportamento de hoje para testes e previews.

**Testes:** TrainerCore (Swift Testing, nome pela regra): `W2 a ordem das metas` (um plano; dois planos com o principal primeiro; com Longevidade, equilíbrio e mobilidade no fim), `W2 sessões por plano contra o previsto`, `W2 músculos: fração pela soma e grupos cumpridos`, `W3 fração limitada e cheia ao passar da meta`, `W4 sem o app Saúde, aeróbico e sono sem dados`, `W4 passos e sono nulos sem dados`, `W5 os tópicos existem no references.v1.json` (lendo por `#filePath`, como o `SeedBundleTests`), `W7 passos só com Longevidade ou Cardio` (tabela com os 5 objetivos, dois planos e nenhum). App: `testRF49_greetingByHour` (limites 4h59, 5h00, 11h59, 12h00, 17h59, 18h00); `testRF49_weekMarks_mondayToSunday` (sessões concluídas com série em [segunda 0h, próxima segunda 0h) no calendário do teste; abandonadas e sem série fora); `testRF49_weekSentence`; `testRF49_path_inProgress`, `_todaySessions`, `_twoSessions`, `_allDone`, `_restDay`, `_noGoal`; `testRF52_goalsScreenReadsHealthWithoutAsking` (o `loadHealth` é chamado; nada pede autorização); `testRF52_noPlanShowsChooseGoal`; `testW7_healthHidesStepsSuggestionWithoutLongevityOrCardio`; `testRF17_historyHasNoWeeklyPanel` (se der para testar pela estrutura; senão, fica no Verificado).

**Entrega ao integrador:** `LandingViewModel` e `LandingView` (com as Metas dentro); `HealthViewModel(showsSteps:)` e `WeeklyGoals.showsSteps(activeGoals:)`.

**Aceite:** App build e Core tests verdes em `ci/v7-home`; CA9-3 e CA9-4.

### 4.4 `session` — sessão guiada, carga opcional, Cardio na ficha e "Como fazer" (T9.4, pesada)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Session/*`, `Features/ExerciseInfo/*`, `Features/ExerciseGuide/*` (novo), `Services/ExerciseGuides/*` (novo).
- `Features/Catalog/*`: só o botão "Como fazer" e a adoção de `paperBackground()`/`inkCard()`.
- `PreviewSupport/SessionPreviewSupport.swift` e `PreviewSupport/CatalogPreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/Session/*`, `Features/ActiveSessionViewModelTests.swift`, `Features/ExerciseInfo/*`, `Features/ExerciseGuide/*` (novo), `Services/ExerciseGuideLibraryTests.swift` (novo) e, se quebrar, `Features/CatalogViewModelTests.swift`.

**Assinaturas congeladas para o integrador e para as outras telas:**
- `SessionFlowView(sessionID:environment:onClose:)`, `ExerciseInfoSheet(content:references:onSubstitute:onSkip:)` e `ExerciseInfoContent(planned:measure:lastSession:)` continuam iguais. `ExerciseInfoContent` pode ganhar campos (por exemplo `slug`), preenchidos por esse `init`.
- `EnvironmentValues.exerciseGuides: ExerciseGuideCatalog` (padrão `.empty`), em `Features/ExerciseGuide/ExerciseGuidesEnvironment.swift`.
- `ExerciseGuideLibrary.load(bundle: Bundle) -> ExerciseGuideCatalog`, em `Services/ExerciseGuides/`: lê `exercise-guides.v1.json` e `exercises.v2.json` do bundle, valida com `ExerciseGuideValidator.validate(_:exercises:)` e, se falhar, registra no log e devolve `.empty` (E8).

**O que fazer:**
1. **Sessão guiada** (SPEC RF-44 i; DESIGN §13). Depois de "Começar", um **botão grande preso embaixo** guia a sessão; a lista de cartões continua em cima, para consulta.
   - A lógica fica numa função pura testável (`SessionGuide`): o passo atual é o primeiro exercício pendente (nem feito nem pulado), com a série seguinte dele. Acima do botão, em uma linha: "Agora: Agachamento livre · série 2 de 3" e a meta de hoje em SF Rounded ("10 repetições · 60 kg"; "30 min · dá para conversar, mas não para cantar").
   - O botão diz **"Marcar série"** (exercício com várias séries), **"Marcar como feito"** (exercício de uma série, como o aeróbico contínuo) ou, com tudo feito, **"Concluir a sessão"** (o mesmo "Concluir" de hoje, que vai direto ao resumo).
   - Tocar marca a série como a bolinha vazia faria (`markSet`, RF-04, RF-44 b) e inicia o descanso. Durante o descanso, o botão continua ativo (marcar adianta), e a linha mostra "A seguir: série 3". Ao terminar um exercício, a lista rola até o próximo.
   - Bolinhas, "Feito", carga, "Informações do exercício", Pular e Trocar continuam nos cartões, como caminho secundário. O cartão atual tem a borda `accent`.
2. **Carga opcional** (SPEC RF-44 c, RF-46; item 2):
   - `canMark` não depende de carga; sem carga, a série grava 0;
   - num exercício com equipamento e carga 0 ou vazia, o cartão mostra **"sem carga"** no lugar do número (toque abre o teclado);
   - sai a caixa "Escolha uma carga…" que bloqueava; a dica de RF-41 fica só na folha de informações;
   - "Marcar como feitos, como previsto" marca todos os pendentes, com ou sem carga (sai o `needingLoad`);
   - **sugestão delicada:** depois da primeira série marcada sem carga num exercício com equipamento que não é peso do corpo nem aeróbico, aparece embaixo do cartão, uma vez só na vida daquele exercício, a linha "Anotar a carga ajuda a sugerir quando subir." com **"Anotar carga"** (abre o teclado) e **"Agora não"**. Mostrada uma vez (com ou sem resposta), nunca mais volta para aquele exercício. Guarde os ids já mostrados em `UserDefaults` (suite injetável no `ActiveSessionViewModel`, padrão `.standard`).
3. **Cardio na ficha e na tela Hoje** (SPEC §7.14 F1, F2; RF-43):
   - `TodayTargetText.row`/`headline`/`spoken*` com `.minutes`: uma série → "30 min"; mais de uma → "4 × 3 min" (nunca "1 série de 30 min");
   - no lugar da carga, a frase da intensidade (`CardioIntensity.classify` com o slug, as séries e o `repMax` do snapshot): leve "Leve: a conversa é fácil"; moderado "Moderado: dá para conversar, mas não para cantar"; forte "Forte: só dá para dizer poucas palavras";
   - o nível da máquina (`LoadUnit.level`) é opcional, como a carga: "sem nível", que se toca para pôr um;
   - nos intervalos (mais de uma série), o descanso se chama "Recuperação andando" ("4 séries · recuperação andando 3 min") e aparece a linha fixa "Antes, aqueça 10 minutos andando devagar.";
   - nada de FC, zonas ou ritmo em números.
4. **"Como fazer"** (SPEC RF-40, §7.12 E1–E10; DESIGN §12; T6.5 e T6.7):
   - `GuideIllustrationView`: `TimelineView(.animation(paused:))` + `Canvas`, com a pose de `GuideKinematics.skeleton(of:at:)`, o tempo de `GuideTiming.frameTime(of:atSeconds:)`, as partes que se movem de `GuideMotion.movingSegments(of:)` em `accent` forte e o resto em `accent` misturado ao fundo, o lado de lá mais claro, cena e acessórios em `textSecondary`/tom de estrutura, a seta de `GuideMotion.cuePath(of:)` em `textPrimary` e o fantasma tracejado da posição inicial no quadro final. Mesmo desenho do renderizador (`docs/design/exercise-guides/render-exercise-guides.ps1`): mesmas espessuras e proporções.
   - `GuideStaticFramesView`: com Reduzir Movimento ou `motion: "static"`, os quadros parados lado a lado, com a inicial em fantasma e as legendas numeradas.
   - `ExerciseGuideSheet`: título em New York, "Trabalha: …" (o `works` da guia ou os grupos primários do catálogo), a ilustração com **Pausar**/**Continuar**, as legendas, os 3 passos e os 2 erros; para o VoiceOver, a ilustração é um elemento só com o `a11y` da guia, seguido dos passos e dos erros; Dynamic Type.
   - `ExerciseGuideButton` ("Como fazer", `play.circle`), só quando existe guia para o slug (E1; na sessão vale o exercício realizado, inclusive o substituto): no cartão da ficha, ao lado do nome; na folha "Informações do exercício", uma seção "Como fazer" com o botão (é assim que a tela Hoje chega à guia); no catálogo, na linha do exercício ou no editor.
   - A animação para ao fechar a folha, com Pausar e com Reduzir Movimento (E7).
5. **Descanso em ensō:** o `RestTimerView` usa `EnsoRingView(progress:)` com a fração do descanso que já passou, o tempo no centro, "+30 s" e "Pular" como hoje.
6. **Papel:** `paperBackground()` na ficha, no resumo e nas folhas; `inkCard()` nos cartões.
7. O resumo "Sessão concluída" continua como está: sem citação, sem elogio, sem frase de efeito (itens 15 e 16).

**Testes:** `testRF44i_guideStepsFollowPendingExercises` (tabela: início, série do meio, exercício de uma série, pulados, tudo feito); `testRF44i_guideButtonTitles`; `testRF44c_markWithoutLoadLogsZero`; `testRF44c_markRemainingIncludesExercisesWithoutLoad`; `testRF46_loadHintShowsOncePerExercise` (duas sessões; dispensa; peso do corpo e aeróbico nunca); `testF1_cardioRowTexts` (tabela: "30 min", "4 × 3 min", intensidades, "recuperação andando"); `testE8_bundleGuidesLoadAndValidate` (55 guias); `testE8_invalidFileFallsBackToEmpty`; `testE1_guideButtonOnlyWithGuide`; `testRF40_worksText`. Os testes existentes de `needingLoad` mudam para o comportamento novo.

**Entrega ao integrador:** `\.exerciseGuides` com `ExerciseGuideLibrary.load(bundle: .main)` na raiz.

**Aceite:** App build verde em `ci/v7-session`; CA9-5 a CA9-7.

### 4.5 `plans-core` — encaixe semanal, Cardio VO2máx e vários planos nos dados (T9.5, pesada)

**Arquivos (exclusivos):**
- TrainerCore: `Sources/TrainerCore/Plans/*`; testes novos (`WeeklyFitTests.swift`, `PlanCombinationTests.swift`) e os existentes que esta tarefa quebrar (`PlansScaffoldTests.swift`, `SeedBundleTests.swift`, `ReferenceCatalogTests.swift`, `ExerciseGuideCoverageTests.swift`, `GoalDefaultsTests.swift`).
- Seed: `PersonalTrainer/Resources/Seed/programs.v2.json` (só o programa Cardio `09AB286E-…`) e `references.v1.json` (acrescentar e os textos de `goal.*`, `topic.cardio` e os tópicos novos).
- App: `Services/Planning/*` (menos `TodaySession.swift` e `TodayOverview.swift`, que só ganham membros com padrão, e `SessionPlanning.swift`, onde não se muda nenhuma assinatura), `Persistence/Repositories/ProgramRepository.swift`, `Services/Backup/BackupDocument.swift` (só a validação dos ativos), `Services/Seed/SeedLoader.swift` (só comentários), `Services/Coach/*`.
- Testes do app: `PersonalTrainerTests/Services/SessionPlanner*Tests.swift` (e um novo `SessionPlannerMultiPlanTests.swift`), `Persistence/ProgramRepositoryTests.swift`, `Services/BackupServiceTests.swift`, `Services/CoachServiceTests.swift`, `Services/SeedLoaderTests.swift`, `Integration/FullLoopTests.swift` (só expectativas ligadas a esta tarefa).

**O que fazer:**
1. **`WeeklyFit.fit`** exatamente como SPEC §7.15 M4 e M5: `sessions[0]` de cada demanda é a sessão do começo da semana (a fase, M3); a busca é exaustiva e determinística (no máximo C(7, k₁) × C(7, k₂) escolhas); as regras valem em cada semana da órbita das fases (a fase avança k por semana, até repetir) e na passagem do domingo para a segunda seguinte; os critérios de escolha, os avisos, os motivos e as saídas na ordem da SPEC. Os `PlannedSlot` saem com `programDayID`, `dayName` e `cardioIntensity` do dia previsto nesta semana. Sem `Date()`, sem aleatório. Pode acrescentar em `PlanDemand` um membro como `startingAt(programDayID:)` para rodar as sessões até a fase.
2. **`PlanCombination`** com a tabela M7 da SPEC, na ordem dela, simétrica nos argumentos; `isLargeOverlap` verdadeiro só para Hipertrofia + Força e Força + Combate; vazio para o mesmo objetivo.
3. **Cardio VO2máx** (SPEC RF-48 e §7.14 F2; item 8), no programa `09AB286E-D2B2-49C6-8C9F-400D118D8D03` (o seed 4 não foi entregue ao dono; a versão continua 4), nome "Cardio", inativo, RIR 3, `startingLoad` nulo:

   | Dia (id de hoje) | Nome | Exercício (séries × faixa, descanso) |
   |---|---|---|
   | `F5F17962-…` | Dia A — Base contínua | `brisk-walk` 1 × 30–45 min, 60 s |
   | `C7B85C1B-…` | Dia B — Intervalos 4 × 4 | `run-intervals` 4 × 3–4 min, 180 s (a recuperação andando) |
   | `06B5194C-…` | Dia C — Longo e leve | `stationary-bike` 1 × 45–75 min, 60 s |

   - Sem complementos de força: o plano combina com os outros (M3). Os ids dos dias continuam os de hoje; os alvos de força saem do JSON.
   - Resumo: "Para um coração mais forte e mais condicionamento: três sessões por semana, uma contínua, uma de intervalos 4 × 4 e uma longa e leve, medidas em minutos."
   - No topo das faixas: 45 + 2 × 16 + 75 ≈ 152 min moderados-equivalentes (A2, F3).
   - `SeedBundleTests`, `ExerciseGuideCoverageTests` (a contagem de slugs dos programas muda; as guias continuam no bundle) e a exceção documentada dos 5 exercícios por dia passam a refletir isso.
4. **Referências** (confira cada DOI no Crossref antes do commit; se algum não bater, pare e reporte):
   - `schoenfeld-2017-load`: Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW, 2017, "Strength and Hypertrophy Adaptations Between Low- vs. High-Load Resistance Training: A Systematic Review and Meta-analysis", Journal of Strength and Conditioning Research, `10.1519/JSC.0000000000002200`, `metaAnalysis`;
   - `stoggl-2014-polarized`: Stöggl T, Sperlich B, 2014, "Polarized training has greater impact on key endurance variables than threshold, high intensity, or high volume training", Frontiers in Physiology, `10.3389/fphys.2014.00033`, `study`;
   - `bacon-2013-vo2max`: Bacon AP, Carter RE, Ogle EA, Joyner MJ, 2013, "VO2max Trainability and High Intensity Interval Training in Humans: A Meta-Analysis", PLoS ONE, `10.1371/journal.pone.0073182`, `metaAnalysis`;
   - `gist-2014-sit`: Gist NH, Fedewa MV, Dishman RK, Cureton KJ, 2014, "Sprint Interval Training Effects on Aerobic Capacity: A Systematic Review and Meta-Analysis", Sports Medicine, `10.1007/s40279-013-0115-0`, `metaAnalysis`;
   - `tomlin-2001-recovery`: Tomlin DL, Wenger HA, 2001, "The Relationship Between Aerobic Fitness and Recovery from High Intensity Intermittent Exercise", Sports Medicine, `10.2165/00007256-200131010-00001`, `review`;
   - `goal.endurance` cita `garber-2011-acsm`, `bull-2020-who`, `helgerud-2007-intervals`, `milanovic-2015-hiit`, `bacon-2013-vo2max`, `stoggl-2014-polarized` e `foster-2008-talk-test`; o texto começa por "Cardio" e fala de base contínua, 4 × 4, longo e leve, teste da fala e da meta da OMS (cerca de 3 frases), sem citar complementos de força;
   - `goal.hypertrophy` e `goal.strength` ganham `schoenfeld-2017-load` e uma frase sobre a diferença (item 10: na hipertrofia, cargas leves ou pesadas dão resultado parecido perto do limite; na força máxima, a carga alta vence);
   - `goal.combat` explica a base comum com a Força e o que o Combate acrescenta (item 12);
   - tópicos novos `topic.combination` (`schumann-2022-concurrent`, `wilson-2012-concurrent`, `tomlin-2001-recovery`, `schoenfeld-2016-frequency`), `topic.load` (`schoenfeld-2017-load`, `schoenfeld-2021-loading`) e `topic.weekFit` (`schoenfeld-2016-frequency`, `schumann-2022-concurrent`, `wilson-2012-concurrent`), com explicação curta cada; `topic.cardio` ganha `bacon-2013-vo2max` e `stoggl-2014-polarized`, e o texto fala do 4 × 4.
   - Os textos das explicações são explicações: nada de frase de efeito (item 16).
5. **Vários planos nos dados** (SPEC §7.15 M1, M2, M3, M6, M8, M9; §7.3 S8; §7.16 W2):
   - `ProgramRepository.addActivePlan`/`removeActivePlan` (M1, M8); `activate(programID:)` continua deixando um só;
   - `BackupDocument`: aceita até 2 ativos, de objetivos efetivos diferentes (mensagem de erro em pt-BR para o resto);
   - `SessionPlanner`: planos ativos por `ActivePlanOrder.sorted`; os requisitos de §3.3 de verdade; `activeProgramDays`, `activeProgramGoal`, `deloadStatus`, `requestDeload`, `dismissDeload` e `reviewInput` olham só o principal (M2); `plan(forDayID:now:)` procura o dia em todos os ativos; com dois planos, cada um tem a própria rotação (S8) e o seletor por frequência (S5–S7) fica desligado; `todayOverview` e `nextPlan(now:)` como M6; `weekSchedule` e `fitCheck` montam `PlanDemand.from` com o catálogo e `SessionDurationEstimate`, rodam cada demanda até a fase do começo da semana (S2 com as sessões iniciadas antes de segunda 00:00) e chamam `WeeklyFit.fit`; `weekPreferences`/`saveWeekPreferences` em `PlannerSettings` (chave `weekPreferences`, JSON; ausente ou ilegível → `.default`; ids que não estão ativos são ignorados);
   - `planWeekProgress(now:)` (W2): um `PlanWeekProgress` por plano ativo, na ordem de M1, com as sessões `completed` com ao menos uma série de trabalho, iniciadas na semana de §7.4, em dias daquele plano, e as sessões por semana dele (M3); `weeklyFrequency(now:)` com as metas e o começo da semana do `UserSettingsModel`, no calendário do planejador, contando as sessões dos dois planos;
   - `CoachService`: o "ativo" é o principal; o C2 da Hipertrofia com um segundo plano ativo troca só o plano da Hipertrofia (tira o antigo e acrescenta o próximo formato), mantendo o outro (M8); o C8 vale quando qualquer plano ativo é de Longevidade (M2).
6. Nada de mudança em `Persistence/Schema/`: vários ativos já cabem no `isActive` do SchemaV2.

**Testes** (nome pela regra): TrainerCore: `M4` em tabela (Equilibrado + Cardio em seg–sáb com 2 por dia aceito; o mesmo sem aceitar, que não cabe; 48 h entre sessões com grupo em comum, inclusive domingo → segunda; forte nunca na véspera de pernas; força antes do aeróbico no mesmo dia; nunca duas forças no mesmo dia; "cardio leve depois da força" só em dia que não é de pernas; fase diferente de 0; órbita com menos sessões que dias; escolha pela ordem de critérios; os campos do dia em cada `PlannedSlot`; determinismo); `M5` (motivos; saídas na ordem, cada uma com a semana; dias a acrescentar mínimos; pares quando nenhuma sozinha cabe; Hipertrofia + Força sem saída de cardio); `M7` (os 10 pares, simetria, textos até 90 caracteres, tópicos que existem no catálogo; sobreposição); `RF-48` (o Cardio VO2máx no seed; ≈ 152 min); referências novas. App: `testM1_addActivePlan_rules`, `testM1_removeActivePlan_neverTheLast`, `testM1_backupAcceptsTwoActiveWithDifferentGoals`, `testS8_eachPlanKeepsItsRotation`, `testM3_phaseFromWeekStart`, `testM6_todayOverview_twoPlans`, `_restDay`, `_doneToday`, `_doesNotFitFallsBackToPrincipal`, `testM2_deloadAndReviewUsePrincipal`, `testM2_longevityRemindersWithSecondPlan`, `testM8_coachC2KeepsSecondPlan`, `testM9_weekPreferencesRoundTrip`, `testW2_planWeekProgress_twoPlans`, `testW2_weeklyFrequencyUsesSettingsTargets`.

**Entrega ao integrador:** nada a ligar além do que já passa pelo `SessionPlanning`.

**Aceite:** App build e Core tests verdes em `ci/v7-plans-core`; CA9-8 a CA9-10.

### 4.6 `plans-ui` — Cardio, vários planos, semana e a tela Hoje (T9.6, pesada)

**Arquivos (exclusivos):**
- `PersonalTrainer/Features/Program/*` (inclusive arquivos novos), `Features/Home/*` (a tela Hoje), `Features/DesignSystem/GoalStyle.swift`.
- `PreviewSupport/ProgramPreviewSupport.swift` e `PreviewSupport/HomePreviewSupport.swift`.
- Testes: `PersonalTrainerTests/Features/Program/*`, `Features/Home/*`, `Features/HomeViewModelTests.swift`, `Features/HomeModeTests.swift`, `Features/ProgramViewModelTests.swift`, `Features/RecoveryContextDerivationTests.swift`, `Features/DesignSystem/FlowerAndGoalStyleTests.swift`.

**O que fazer:**
1. **Folha "Seu objetivo"** (SPEC RF-45, §7.15 M7 e M8):
   - com um plano ativo e outro objetivo tocado: dois botões, **"Trocar para X"** (fica só X, como hoje) e **"Adicionar X ao seu plano"**; com dois ativos, só "Trocar para X", com a frase "O plano de Y também sai.";
   - trocar o formato da Hipertrofia, ou o plano de um objetivo que já está ativo, troca só aquele plano e mantém o outro (`removeActivePlan` do antigo e `addActivePlan` do novo, nessa ordem);
   - **"Adicionar"** abre um fluxo curto, em páginas: (a) **"O que muda"**: as consequências de `PlanCombination` em três grupos ("Ganha" +, "Fica igual" =, "Custa" −), cada item com "Por quê?" (`WhyButton` com o `referenceTopic`) e, se `isLargeOverlap`, o aviso "Os dois planos treinam quase os mesmos levantamentos. Um plano só, ou outro formato, pode bastar."; (b) **"Seus dias"**: chips de segunda a domingo e as chaves "Aceito 2 sessões no mesmo dia" e "Cardio leve depois da força", começando de `weekPreferences()`; (c) **"Sua semana"**: `fitCheck`; se cabe, a semana e o botão **"Adicionar X"** (grava as preferências e chama `addActivePlan`); se não cabe, o motivo em uma frase e as saídas, cada uma com a semana que resulta e **"Escolher esta"**; sem saída, "Esses dois planos não cabem juntos na semana. Escolha um só.";
   - com sessão em andamento, tudo bloqueado, como hoje.
2. **Aba Plano:** os planos ativos (1 ou 2), cada um com a flor pequena, o nome, a semana dele para consultar e, com dois, **"Tirar este plano"** (`removeActivePlan`, com confirmação); com dois, **"Sua semana"** (`weekSchedule`, Seg a Dom, cada dia com o `dayName` e, no aeróbico, a intensidade de `cardioIntensity` — "Qui · Dia A — Superior + Cardio forte" —, "descanso" nos dias livres e as notas de M4) e **"Seus dias"** (editar as preferências, com `fitCheck` antes de gravar e as mesmas saídas); com um, **"Adicionar um plano"** abre a folha no modo de adicionar. "Ajustar exercícios" e o catálogo continuam.
3. **Tela Hoje** (SPEC RF-01, §7.15 M6; DESIGN §9.7):
   - o topo mostra todos os objetivos ativos (`FlowerView(activeGoals:)`, "Hipertrofia + Cardio") e continua abrindo "Seu objetivo";
   - com dois planos, um cartão por sessão de `todayOverview` (o título do dia do plano, "5 exercícios · ≈ 55 min" ou "30 min", o menu de dias daquele plano e as linhas), na ordem (força antes do aeróbico), e em cima a linha "Hoje: Superior + Cardio leve 25 min"; uma sessão feita hoje vira "✓ Feito hoje" com "A seguir: …";
   - **"Começar"** (o único botão proeminente) começa a primeira sessão pendente; "Retomar" com sessão em andamento; o segundo cartão tem "Começar esta" menor;
   - dia de descanso: "Hoje é dia de descanso." (sem frase depois, item 16) e "Treinar mesmo assim", que mostra os cartões de `otherSessions`;
   - planos que não cabem mais: a sessão do principal e a faixa "Seus planos não cabem nos dias escolhidos. Ajuste em Plano › Seus dias.";
   - com um plano só, a tela fica como hoje.
4. **Textos** de `FitProblem`, `FitChange`, `FitNote` e da semana num arquivo de textos da tarefa (por exemplo `PlanWeekText.swift`), pt-BR, curtos, testados em tabela. Exemplos: "São 7 sessões para 6 dias."; "Duas sessões de força com os mesmos músculos ficariam a menos de 48 h."; "Um cardio forte cairia na véspera de pernas."; "Treinar também no domingo"; "Aceitar 2 sessões no mesmo dia"; "Cardio leve depois da força"; "Cardio 2 vezes por semana"; "Sem um dia de descanso completo."; "Na terça, faça a força antes do cardio."
5. `paperBackground()` e `inkCard()` nas telas da tarefa.

**Testes** (com doubles de `SessionPlanning` e `ProgramRepositoring` que devolvem `FitResult` e `TodayOverview` prontos): `testM8_addFlow_fits_addsPlanAndSavesPreferences`; `testM8_addFlow_doesNotFit_showsAlternatives_choosingOneAdds`; `testM8_addFlow_noAlternative`; `testM8_changeWithTwoActiveWarnsSecondLeaves`; `testM8_formatChangeKeepsSecondPlan`; `testM7_overlapWarning`; `testM6_today_twoSessions_orderAndPrimaryButton`; `_doneTodayMovesToNext`; `_restDay_trainAnyway`; `_notFitBanner`; `testM6_singlePlanUnchanged`; `testPlanWeekText_table`; `testPlanTab_removePlan`; `testPlanTab_weekShowsDayNames`.

**Entrega ao integrador:** nada novo além de `HomeView` e `ProgramTabView`, com as mesmas assinaturas de hoje (se precisar de parâmetro novo, com valor padrão).

**Aceite:** App build verde em `ci/v7-plans-ui`; CA9-11 e CA9-12.

## 5. Integração (T9.7)

No worktree `C:\Users\leona\Developer\pt-wt\w7-integration` (branch `v7/integration`, a partir da base):

1. Mescle, nesta ordem, com `--no-ff`: `v7/ink`, `v7/launch`, `v7/home`, `v7/session`, `v7/plans-core`, `v7/plans-ui`. Os escopos são disjuntos; um conflito é sinal de arquivo fora do escopo: resolva mantendo as duas partes e registre no relatório.
2. `App/*`:
   - aba nova **"Início"** (`house`), a primeira, selecionada no lançamento, com `LandingView(model:references:onOpenToday:onOpenSession:)`; "Hoje" passa a segunda. O `onOpenToday` seleciona "Hoje"; o `onOpenSession` usa o mesmo caminho do "Retomar". O `LandingViewModel.refresh()` roda ao aparecer, ao voltar para a aba e ao voltar ao primeiro plano;
   - o `LandingViewModel` recebe `healthReport: { healthModel.report }`, `loadHealth: { await healthModel.loadIfStale() }` e `longevityDone: { coach.longevityMarks(in: coach.logStore.load(), now: environment.now()) }`;
   - o `HealthViewModel` recebe `showsSteps: { WeeklyGoals.showsSteps(activeGoals: (try? environment.planner.activeProgramGoals()) ?? []) }` (W7);
   - `launchOverlay(goals:isEnabled:onFinished:)` por cima das abas (não da tela de erro do store), ligado só na abertura a frio (`@State` que começa verdadeiro e vira falso em `onFinished`), com `goals` de `activeProgramGoals()`; o onboarding e o destaque do diálogo esperam o `onFinished` (`blocksCoachSheet`);
   - `.environment(\.exerciseGuides, …)` com `ExerciseGuideLibrary.load(bundle: .main)`, carregado uma vez (por exemplo no `AppEnvironment`, como o `traits`).
3. **Conferência de mensagens** (itens 15 e 16): procure em `PersonalTrainer/Features/**` e `PersonalTrainer/Resources/Seed/**` textos que sejam citação, frase inspiracional ou de efeito ("progredir", "progresso", "força interior", "sabedoria", nome de filósofo, "!") e registre o que achou; o que for de uma tarefa volta para ela. Os avisos do diálogo (C1–C8, `TrainerCore/Coach`) e as explicações do "Por quê?" são funcionais e ficam.
4. Rode `ExerciseGuideCoverageTests` e os testes de todas as tarefas; `git push origin HEAD:ci/v7-final` (Expected 2) até verde.
5. Revisão estática adversarial, correção, CI verde e merge no `main` (fora deste contrato: o workflow decide). Depois: TASKS (T9.x `[x]`), HANDOFF, IPA do run final e a página/PDF da Amanda.

## 6. Critérios de aceitação

| CA | Verificação |
|----|-------------|
| CA9-1 | Tinta e papel: tokens da direção A com AA testado; papel, cartões, flor em aguada, ensō, marca de tinta e aguada de montanha nas folhas `docs/design/v23-ink/`. |
| CA9-2 | Abertura: tela de lançamento marinho com a flor; `LaunchTimeline` com os números do protótipo, pólen discreto, Reduzir Movimento, escuro sem véu, sem objetivo sem cor, sem vibração, sem texto; nunca bloqueia (testes RF-50). |
| CA9-3 | Início: flor, saudação, semana calma que abre as Metas e caminho para a tela Hoje, em todos os estados (testes RF-49); nenhuma mensagem nem citação. |
| CA9-4 | Metas da semana: W1–W7 em testes de tabela no TrainerCore; tela com marcas de tinta, "sem dados" e "Por quê?"; nunca pede permissão; o Histórico sem o painel; passos só com Longevidade ou Cardio, também no cartão, no detalhe e na sugestão de Saúde. |
| CA9-5 | Sessão guiada: o botão grande segue os pendentes e conclui; a lista continua como consulta (testes RF-44 i). |
| CA9-6 | Carga opcional: marcar sem carga grava 0; "sem carga" no cartão; a sugestão aparece uma vez por exercício, com dispensa; Cardio com "30 min", "4 × 3 min", intensidade pelo teste da fala e nível opcional. |
| CA9-7 | "Como fazer": folha com a ilustração animada (e parada com Reduzir Movimento), passos, erros e VoiceOver; botões na ficha, nas informações do exercício e no catálogo, só com guia; E8 com o bundle real. |
| CA9-8 | Encaixe: `WeeklyFit` com M4 e M5 em testes de tabela, com fase e órbita, determinístico. |
| CA9-9 | Consequências: os 10 pares da SPEC M7 com "Por quê?"; Cardio VO2máx no seed com as referências conferidas. |
| CA9-10 | Dados com dois planos: repositório, backup, rotação por plano (S8), fase do começo da semana, tela Hoje do planejador (M6), principal na semana leve, na revisão e no C2 (M2, M8), C8 com Longevidade em qualquer plano, `planWeekProgress` e `weeklyFrequency` (W2). |
| CA9-11 | Folha "Seu objetivo" com Trocar e Adicionar; fluxo de adicionar com consequências, dias, semana e saídas; troca de formato que mantém o outro plano; aba Plano com os planos, a semana (com os dias) e os dias. |
| CA9-12 | Tela Hoje com as sessões do dia, descanso, "Treinar mesmo assim" e a faixa de não cabe; com um plano, igual à 2.2. |
| CA9-13 | (integração) Início como primeira aba, abertura a frio por cima, guias no ambiente, passos ligados a W7, conferência de mensagens feita; App build e Core tests verdes em `ci/v7-final`. |

## 7. Incertezas conhecidas

- **Vibração na abertura:** o texto que chegou a esta tarefa citava "vibração" entre os detalhes aprovados, mas o protótipo aprovado a deixou desligada, a crítica a cortou e o dono mandou não sobrepor a crítica, pedindo de volta só o pólen (itens 13 e 14). O contrato segue as notas do dono: sem vibração. Se o dono quiser, é uma linha no `LaunchOverlay` (o protótipo marca 0,28 s).
- **Aeróbico das Metas:** até a tarefa de HealthKit do Cardio (F5), as sessões do plano Cardio feitas no app não entram nos minutos de aeróbico das Metas, só na linha de sessões do Cardio. Quem grava a caminhada ou a corrida no relógio vê os minutos contados.
- **Equilíbrio e mobilidade:** o C8 registra "Feito" uma vez por semana para cada bloco; a meta das Metas é "feito nesta semana", não as 2 a 3 vezes da tabela de §7.9 (registro próprio é a pendência C10 do TASKS).
- **4 × 4 que cresce de 3 para 5 blocos** (item 8): o motor sobe minutos, não séries. Nesta versão o Dia B tem 4 blocos de 3 a 4 min; o quinto bloco é regra nova do motor (SPEC F3, pendência).
- **Dia D (tiros de 30 s)** do item 8: medido em segundos, não cabe no aeróbico medido em minutos sem um exercício novo; fica fora, como opcional futuro.
- **Zonas de FC e VO2máx no Cardio** (item 8): ficam para a tarefa de HealthKit do Cardio, com a regra de que a FC nunca prescreve (§7.6).
- A semana ideal (M4) supõe que a pessoa segue a rotação a partir da fase do começo da semana; se ela pula dias, a tela Hoje continua mostrando a próxima sessão de cada plano no lugar da semana, e a semana seguinte se recalcula com a fase nova. Aceito: o app sugere, não obriga.
- As preferências da semana ficam fora do backup (UserDefaults), como o modo casa.
- O seed 4 com o Cardio de 3 dias com complementos só existe nos IPAs de `ci/v7-base` e `ci/v7-scaffold*`, que não foram entregues ao dono; se alguém instalou um deles, o loader não troca o programa já gravado (V23-CORE §7).
- Só o aparelho confirma: a barra de status escondida no lançamento e mostrada pela SwiftUI; a abertura a 120 Hz; a textura de papel com True Tone; o desenho da guia no `Canvas` igual à folha de revisão; a barra de 5 abas com Liquid Glass.
