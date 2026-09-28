# Contrato da versão 2.3: núcleo

Versão 1 · 2026-09-27. Base: o commit do `main` que traz este arquivo. Os worktrees `w6-core` e `w6-guide-engine` partem dele.

Este contrato cobre só o núcleo: motor, dados do seed, textos que deixariam de compilar e o motor do "Como fazer". A parte de telas vem depois, num contrato próprio (§8).

**Pedidos do dono** (2026-09-27; SPEC decisão 19). Eles prevalecem sobre qualquer proposta.
- **D1 Hipertrofia "Equilibrado".** O formato padrão deixa de ser "Corpo todo". O novo formato tem 4 dias, alternando Superior e Inferior (A Superior, B Inferior, C Superior com outros exercícios, D Inferior com outros exercícios), com 5 exercícios por dia e cada grupo trabalhado 2 vezes por semana.
  - Os formatos passam a ser: **Equilibrado**, **Mais pernas e glúteos** e **Mais tronco e braços**.
  - O "Corpo todo" fica escondido, como o antigo Empurrar/Inferior/Puxar: só aparece enquanto estiver ativo.
- **D2 "Resistência muscular" vira "Fôlego", cardiovascular.** O subtítulo é "Mais fôlego e disposição". O raw value `endurance` não muda.
  - O plano prescreve cardio simples medido em minutos: uma sessão contínua moderada (teste da fala), uma de intervalos e uma longa e leve, com 1 ou 2 complementos de força.
  - A duração sobe aos poucos, com P4–P6 aplicados aos minutos.
  - O catálogo ganha 10 exercícios aeróbicos.
  - A decisão 14 foi revista.
- **D3 Carga opcional em qualquer exercício.**
  - Não é preciso informar carga para marcar uma série ou um exercício.
  - 0 num exercício com equipamento quer dizer "sem carga externa". A próxima prescrição continua em 0 e progride por repetições, segundos ou minutos até a pessoa pôr carga. A partir daí, a progressão parte do valor que ela registrou.
- **D4 Medida nova `minutes`.** O número gravado na série é o de minutos.
- **D5 "Como fazer" já.**
  - O motor e a ferramenta de autoria saem nesta rodada.
  - Guias para os 62 exercícios que o app usa: os 52 dos programas do seed e os 10 aeróbicos novos.
  - O estilo é o aprovado na v2 do protótipo. O cardio pode usar o manequim parado com setas (`motion: "static"`).

**Regras de domínio:** SPEC RF-04, RF-35, RF-40, RF-43, RF-44 (c), RF-45, RF-46, RF-48, §7.2 (P2, P4, P6, P8, P9), §7.5, §7.8 (R1, R3, R5), §7.9, §7.12 (E1–E10), §7.13 H1, §7.14 (F1–F5) e decisões 14 e 19.

**Fora deste contrato** (vão para a onda de telas, §8):
- a sessão guiada e a parte de tela da D3;
- a interface do Fôlego;
- a folha "Como fazer" (T6.5) e os botões (T6.7);
- a passada estética;
- o HealthKit do Fôlego;
- a semana leve do cardio.

Também ficam fora: SchemaV3, tarefas [PROJ] e [SCHEMA] (não tocar em `project.yml`, workflows, entitlements nem `Persistence/Schema/`), `SessionEvent`, sync e o formato do backup.

## 0. Como testar sem compilador local

Vale o `docs/V2-FINAL-CONTRACT.md` §0. O Smart App Control bloqueia o Swift nesta máquina, e essa configuração não se mexe.
- Comece todo comando PowerShell com `Set-Location` para o **seu** worktree. Nunca edite `C:\Users\leona\Developer\PersonalTrainer` diretamente.
- Antes de cada push, releia inteiro cada arquivo que você alterou: tipos, imports, `@MainActor`/`Sendable`, inits, `switch` exaustivos, fechamentos de chaves e rótulos de argumento.
- Configure o push antes: `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"`.
- CI da `core`: `git push origin HEAD:ci/v6-core`. Roda App build e Core tests (`-Expected 2`). O App build leva de 20 a 30 min.
- CI da `guide-engine`: `git push origin HEAD:v6/guide-engine`. Roda só Core tests (`-Expected 1`), porque ela não toca em código do app.
- Espere com `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\watch-ci.ps1 -Sha <sha completo> -Minutes 9 -Expected <N>`. Repita a chamada até ele dizer que todos terminaram.
- Corrija pelas anotações. No máximo 5 rodadas de CI por tarefa. No fim, com o CI verde, a `core` faz `git push origin v6/core`.
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- O relatório traz a lista **Verificado** e **Incerto** (AGENTS R11) e o sha do último run verde.
- O PowerShell roda nesta máquina (PowerShell 5.1 + System.Drawing). A ferramenta de guias (§2.7) é o único validador local do conteúdo, e as folhas PNG se conferem abrindo o arquivo.

## 1. Regras desta rodada

1. **Escopo exclusivo por arquivo** (§3). Arquivo novo só dentro das pastas da sua tarefa. Se precisar de um arquivo de outra tarefa, pare e reporte; não edite.
2. **Não edite** `SPEC.md`, `TASKS.md`, `AGENTS.md`, `DESIGN.md` nem este contrato. O arquiteto já os atualizou e o integrador marca o estado. `ARCHITECTURE.md` só pode ser editado pela `guide-engine`, e só nas §11 e §17.
3. **Congelado** (§2): enums novos, ids e slugs do seed, semântica da D3, formato do arquivo de guias, API pública de `TrainerCore/Guide`, linha de comando da ferramenta e nomes dos lotes. Quem precisar mudar algo congelado para e reporta.
4. **AGENTS:**
   - R1: `TrainerCore` só usa Foundation.
   - R2: nada de FC no `Engine`. A intensidade do cardio é o teste da fala, nunca a frequência cardíaca.
   - R3: nenhum `Date()` no motor nem em `Guide`.
   - R4, R8 e R11: nada de `fatalError`, `try!` ou força-unwrap fora de testes.
   - §4: um tipo público por arquivo, textos pt-BR fixos, `os.Logger`, sem `print`.
   - R7: toda regra nova tem teste de tabela com o nome da regra, por exemplo `@Test("P8 D3 …")`, `@Test("F3 …")`, `@Test("E10 …")`.
5. **Raw values persistidos nunca mudam:** `endurance`, os slugs e ids existentes, os cases de `MovementPattern` e de `ExerciseMeasure`. Só se acrescentam cases.
6. **Textos pt-BR** curtos e sem jargão de academia (DESIGN §6 e §7). Nenhum texto novo cita RIR (RF-41).

## 2. Assinaturas e dados compartilhados (congelados)

### 2.1 Enums e constantes (TrainerCore; dona: `core`)

```swift
public enum ExerciseMeasure { case reps, seconds, steps, minutes }        // + minutes (D4): o número da série = minutos inteiros
public enum MovementPattern { …; case cardio }                             // displayName "Aeróbico"; isCompound = false
extension ProgramGoal { var displayName }                                  // .endurance → "Fôlego" (o raw value continua "endurance")
public enum CardioDefaults {                                               // Domain/CardioDefaults.swift (novo)
    public static let minutes: ClosedRange<Int>   // 20...40: faixa de um aeróbico novo na edição do plano
    public static let sets: Int                    // 1
    public static let restSeconds: Int             // 60
}
```
`GoalDefaults` de `.endurance` (Fôlego, só os complementos de força): `compoundRepRange` 12…20, `isolationRepRange` 15…20, `targetRIR` 3, `weeklySetsPerMuscle` 4…12, `compoundRestSeconds` 60, `isolationRestSeconds` 60 e `setsPerExercise` 2. Base: ACSM 2011, com força 2 a 3 dias por semana e 2 a 4 séries.

### 2.2 D3 no motor (dona: `core`; SPEC P2, P4, P6, P8, P9 e §7.5)

L é a carga de referência (P3). "Sem carga" quer dizer L = 0. "Aeróbico" quer dizer `exercise.movementPattern == .cardio`.

| Caso | Hoje | 2.3 |
|---|---|---|
| Mínimo de P8 | inc (0 em peso do corpo) | também 0 quando L = 0 |
| P2 com `startingLoad == 0` | inc (fora do peso do corpo) | 0, nota `calibrate`. Entre 0 e inc, sobe para inc, como hoje. |
| P4 com L = 0, peso do corpo **e não** aeróbico | L + inc (RF-46: "+ 2,5 kg extra") | **igual** (decisão 18 mantida) |
| P4 com L = 0, qualquer outro equipamento **ou** aeróbico | inc | P4 não se aplica e vale P5: carga 0, meta = min(repMax, menor + 1) = repMax, nota `hold` |
| P5 com L = 0 | 0 / inc | 0, meta + 1, nota `hold` |
| P6, 1ª falha, com L = 0 | 0 / inc | 0, `retry` |
| P6, 2ª falha na mesma L = 0 | `decrease` com 0 ou inc | 0, **`retry`**. Não há o que reduzir (vale também para peso do corpo). |
| P9 com L = 0 | 0 / inc | 0, `returning` |
| §7.5 semana leve com C = 0 | inc (fora do peso do corpo) | 0 |
| Aeróbico com L > 0 (nível da máquina registrado) | — | regras normais. P4 sobe 1 incremento (1 nível) e a meta volta a repMin. Sem RIR nas séries novas, não há o bônus de 2 incrementos. |

Quando a pessoa registra carga maior que 0, a P3 (moda) passa a usar esse valor e as regras de sempre voltam a valer (P10). O `SetResult` e o `ExerciseHistoryEntry` não mudam.

### 2.3 Seed (dona: `core`)

Os dois arquivos ficam com `"version": 4`, e `SeedLoader.currentSeedVersion` = 4. O loader continua como está:
- insere os exercícios que faltam;
- insere, inativos, os programas cujo id falta;
- nunca altera nem apaga um programa existente.

**Exercícios novos** (`exercises.v2.json`). Todos têm `movementPattern: "cardio"`, `measure: "minutes"`, `isUnilateral: false`, `machineNotes: null` e `isCustom: false`. O `quads` vem primeiro nos grupos primários, para todo aeróbico ser substituto de todo aeróbico (RF-34 e H2).

| id | slug | name | equipment | loadUnit / inc | primários | secundários | atHome |
|---|---|---|---|---|---|---|---|
| `FF3602F0-7208-40EE-88D6-E77A4C9C4EED` | `brisk-walk` | Caminhada rápida | bodyweight | kilograms / 2,5 | quads, glutes | hamstrings, calves | true |
| `26AED2AF-D743-430C-BB82-EA5F7372B7C9` | `easy-run` | Corrida leve | bodyweight | kilograms / 2,5 | quads, glutes | hamstrings, calves | true |
| `24B71417-E6AD-41D6-AAA5-D88873A17EDA` | `stationary-bike` | Bicicleta ergométrica | machine | level / 1 | quads, glutes | hamstrings, calves | false |
| `A5FC671E-C216-4398-87F7-870124E3302C` | `rowing-machine` | Remo na máquina | machine | level / 1 | quads, back | glutes, hamstrings, biceps | false |
| `8A515D14-D6B5-4517-83AF-6B31CD718F7A` | `elliptical` | Elíptico | machine | level / 1 | quads, glutes | hamstrings, calves | false |
| `74FB2A7F-8F60-41BF-B671-3CBB6D4949EE` | `stair-climb` | Subir escadas | bodyweight | kilograms / 2,5 | quads, glutes | calves, hamstrings | true |
| `F2078CD8-1F1F-4BE0-9592-874BD4051974` | `jump-rope` | Pular corda | bodyweight | kilograms / 2,5 | quads, calves | shoulders | false (precisa de corda) |
| `732DE545-F908-43F8-A7AA-9D41D6CA7B0E` | `run-intervals` | Intervalos de corrida | bodyweight | kilograms / 2,5 | quads, glutes | hamstrings, calves | true |
| `8F4DF10D-F6BE-4D25-B586-F800CE4D918B` | `bike-intervals` | Intervalos na bicicleta | machine | level / 1 | quads, glutes | hamstrings, calves | false |
| `C75ABEFA-6032-4EB4-B4E1-BA06969947C5` | `bodyweight-circuit` | Circuito com peso do corpo | bodyweight | kilograms / 2,5 | quads, glutes | chest, core, shoulders | true |

**Programas** (`programs.v2.json`). Continuam 8, com um único ativo. Ids de dias e de alvos novos saem de `New-Guid` em maiúsculas.
- **Novo e ativo no seed:** `9FE0818F-1417-4953-B357-43D757054FCC`, "Hipertrofia — Equilibrado", `hypertrophy`. O resumo: "Para ganhar massa muscular no corpo todo de forma equilibrada: quatro dias que alternam superior e inferior, com cada grupo trabalhado duas vezes por semana." RIR 2 e `startingLoad` nulo em todos os alvos.

  | Dia | Exercícios (séries × faixa, descanso) |
  |---|---|
  | Dia A — Superior | `barbell-bench-press` 4 × 6–10, 150 · `barbell-row` 4 × 6–10, 150 · `dumbbell-shoulder-press` 3 × 8–12, 150 · `barbell-curl` 3 × 8–12, 90 · `cable-triceps-pushdown` 3 × 8–12, 90 |
  | Dia B — Inferior | `barbell-back-squat` 4 × 6–10, 150 · `barbell-romanian-deadlift` 4 × 6–10, 150 · `barbell-hip-thrust` 3 × 8–12, 150 · `standing-calf-raise` 3 × 12–15, 90 · `cable-crunch` 3 × 12–15, 90 |
  | Dia C — Superior | `incline-dumbbell-bench-press` 4 × 8–12, 150 · `lat-pulldown` 4 × 8–12, 150 · `dumbbell-lateral-raise` 3 × 12–15, 90 · `hammer-curl` 3 × 8–12, 90 · `overhead-dumbbell-triceps-extension` 3 × 8–12, 90 |
  | Dia D — Inferior | `leg-press-45` 4 × 8–12, 150 · `lying-leg-curl` 3 × 8–12, 90 · `hip-abduction-machine` 3 × 8–12, 150 · `seated-calf-raise` 3 × 12–15, 90 · `hanging-leg-raise` 3 × 8–12, 90 |

  Cada um dos 10 grupos é o **primeiro** grupo primário de exatamente 2 exercícios da semana, e todos os 20 alvos passam na `seedProgramParametersFollowGoalTable`. Os descansos seguem §7.9 (150 s nos compostos, 90 s nos isolados; `hipThrust` é composto). Com 4 dias, a escolha do dia pela semana (RF-39, automático) fica ligada.
- **"Hipertrofia — Completo"** (`14E3FAC0-…`): continua no seed, inativo e com o mesmo conteúdo. Fica escondido (§2.4).
- **Sai do seed:** "Resistência muscular" (`CBE66162-1F29-41BE-9FF6-7A9E34C179BA`). Instalações que já o têm o mantêm no banco, porque o loader nunca apaga. Instalação nova não o recebe.
- **Novo:** `09AB286E-D2B2-49C6-8C9F-400D118D8D03`, "Fôlego", `endurance`, inativo. O resumo: "Para ganhar fôlego e disposição: três sessões simples por semana (contínua, intervalos e uma longa e leve), medidas em minutos, com exercícios leves de força." RIR 3 e `startingLoad` nulo em todos os alvos.

  | Dia | Exercícios (séries × faixa, descanso) |
  |---|---|
  | Dia A — Contínuo | `brisk-walk` 1 × 20–45 min, 60 · `box-squat` 2 × 12–20, 60 · `knee-push-up` 2 × 12–20, 60 |
  | Dia B — Intervalos | `run-intervals` 4 × 2–4 min, 180 (o descanso é a recuperação andando) · `dead-bug` 2 × 15–20, 60 |
  | Dia C — Longo e leve | `stationary-bike` 1 × 30–60 min, 60 · `bird-dog` 2 × 15–20, 60 |

  É a exceção aos 5 exercícios por dia (SPEC §7.9 e §7.14). No topo das faixas, a semana soma cerca de 45 + 2 × 16 (vigoroso) + 60 ≈ 137 min moderados-equivalentes, mais as recuperações: perto dos 150 da OMS.

**Referências** (`references.v1.json`, só acrescentar). Confira cada DOI no Crossref antes do commit.
- `milanovic-2015-hiit`: Milanović Z, Sporiš G, Weston M, 2015, "Effectiveness of High-Intensity Interval Training (HIT) and Continuous Endurance Training for VO2max Improvements: A Systematic Review and Meta-Analysis of Controlled Trials", Sports Medicine, `10.1007/s40279-015-0365-0`, `metaAnalysis`. O ano é 2015 (vol. 45, n. 10), não 2016.
- `foster-2008-talk-test`: Foster C, Porcari JP, Anderson J, et al., 2008, "The Talk Test as a Marker of Exercise Training Intensity", Journal of Cardiopulmonary Rehabilitation and Prevention, `10.1097/01.HCR.0000311504.41775.78`, `study`.
- `helgerud-2007-intervals`: Helgerud J, Høydal K, Wang E, et al., 2007, "Aerobic High-Intensity Intervals Improve VO2max More Than Moderate Training", Medicine & Science in Sports & Exercise, `10.1249/mss.0b013e3180304570`, `study`.
- `goal.endurance` passa a citar `garber-2011-acsm`, `bull-2020-who`, `milanovic-2015-hiit` e `foster-2008-talk-test`. A explicação nova fala de fôlego, minutos por semana, teste da fala e intervalos (cerca de 3 frases, sem jargão).
- Tópico novo `topic.cardio` com `foster-2008-talk-test`, `garber-2011-acsm`, `milanovic-2015-hiit` e `helgerud-2007-intervals`. A explicação diz:
  - como sentir a intensidade (conversar sem cantar no moderado; só poucas palavras no forte);
  - que a duração sobe 1 minuto por sessão até o topo da faixa;
  - que o nível da máquina é opcional.

### 2.4 Objetivo, formatos e textos no app (dona: `core`)

- `GoalStyle` (`.endurance`): `subtitle` = "Mais fôlego e disposição" e `symbolName` = "wind". Cor e `petalIndex` não mudam.
- `GoalPlanCatalog`:
  - `hypertrophyFormats` = [(`hypertrophyBalancedID` = `9FE0818F-…`, "Equilibrado"), (`hypertrophyLowerFocusID`, "Mais pernas e glúteos"), (`hypertrophyUpperFocusID`, "Mais tronco e braços")].
  - `hypertrophyFullBodyID` (`14E3FAC0-…`) e `legacyPushLegsPullID` só entram como formato extra enquanto estão ativos, pela regra de RF-45. O extra do `14E3FAC0-…` tem o título "Corpo todo"; os outros extras usam o nome do programa.
  - `seedPlanID(.endurance)` = `enduranceCardioID` (`09AB286E-…`). O antigo `CBE66162-…` vira `legacyEnduranceID` e só vale pela regra "ativo primeiro".
  - Os comentários passam a dizer "Fôlego".
- `CoachService.hypertrophyFormats` (C2) recebe a mesma lista de 3 formatos. Com o Corpo todo ativo, o próximo formato é o Equilibrado, que é o primeiro da lista.
- Texto da R5 `switchProgram` (TrainerCore): o motivo passa a ser "Você treina com este plano há N semanas; depois de M semanas, mudar de plano renova o estímulo, e as cargas de cada exercício são mantidas." O título e o id não mudam.
- `.minutes` nos textos do app (pt-BR):

  | Função | Saída |
  |---|---|
  | `MeasureText.title` | "Minutos" |
  | `MeasureText.pluralNoun` | "minutos" |
  | `MeasureText.stepperRange` | 0...300 |
  | `MeasureText.range` | "20–40 min" |
  | `MeasureText.amount` | "30 min" |
  | `MeasureText.spokenAmount` | "1 minuto", "30 minutos" |
  | `TodayTargetText.amount` | "1 minuto", "30 minutos" |
  | `TodayTargetText.compactAmount` | "30 min" |
  | `SessionSheetText.firstTimeHint` | o mesmo ramo de segundos e passos |
  | `SessionSheetText.unitSuffix` | " min" |
  | `ExerciseInfoText.measureSubjectPlural` | "os minutos" |
  | `SessionDurationEstimate` | minutos × 60 s por série |

  As saídas atuais de `.reps`, `.seconds` e `.steps` não mudam.
- `ProgramRepository`: um aeróbico novo num dia (`MovementPattern.cardio`) usa `CardioDefaults`: 1 série, faixa 20–40 e descanso 60. O `setGoal(… withDefaults)` pula o aeróbico como já pula carregadas e pescoço.

### 2.5 Formato do arquivo de guias (congelado; SPEC §7.12)

Vale para `PersonalTrainer/Resources/Seed/exercise-guides.v1.json` e para cada `docs/design/exercise-guides/batch-N.json`: o formato é o mesmo, e o lote só traz as próprias guias. É o formato do protótipo (`exercise-guides.sample.json`) com as extensões marcadas **(novo)**. JSON em UTF-8 **sem BOM**, com fim de linha LF.

**Convenções.**
- Unidade: estatura H = 1. x cresce para a frente (à direita no desenho), y para cima, e o chão fica em y = 0.
- Ângulos em graus, absolutos por segmento: 0 = direita, 90 = cima, −90 = baixo, 180 = esquerda.
- O rosto aponta para `neck − 90°`. O manequim é sempre "destro" no próprio referencial, nunca espelhado:
  - em pé, virado para a direita: `trunk` 90, `neck` 90;
  - deitado de costas com a cabeça à esquerda: `trunk` 180, `neck` ≈ 178 (rosto para cima);
  - de bruços com a cabeça à direita: `trunk` ≈ 0, `neck` ≈ 0 (rosto para baixo);
  - em quatro apoios, virado para a direita: `trunk` ≈ 0.

**Topo:** `{"version": 1, "rig": "mannequin-v2", "units": "stature", "guides": [ … ]}`. Nenhuma outra chave.

**Guia:**

| Campo | Tipo | Regra |
|---|---|---|
| `slug` | String | E1: existe no catálogo do seed; uma guia por slug. |
| `view` | `"side"` \| `"front"` | Na vista frontal, os braços são sempre por ângulos (sem `arms.reach`). |
| `motion` | `"loop"` (padrão) \| `"static"` **(novo)** | `static` não anima e não desenha o fantasma. |
| `anchor` | `{"joint": P, "at": [x, y]}` | P é um ponto do esqueleto (tabela abaixo) **(novo: qualquer ponto, inclusive do lado de lá e da mão)** ou `"none"` **(novo)**, com `frames[].root` obrigatório. Âncora na mão ou no braço exige braços por ângulos. |
| `timing` | `{"toEnd", "toStart", "hold", "easing": "easeInOut"}` | Obrigatório em `loop`: `toEnd` e `toStart` entre 0,8 e 3,0 s, `hold` entre 0,2 e 1,0 s (E7). Em `static` pode faltar. |
| `scene` | [Cena] | Estrutura fixa; pode ser `[]`. |
| `props` | [Acessório] | O que se move com o corpo; pode ser `[]`. |
| `arms` | Braços? | Sem `arms`, os braços são por ângulos. |
| `frames` | [Quadro] | 2 ou 3 em `loop`; de 1 a 3 em `static`. |
| `cue` | Seta? | Obrigatória em `loop`; opcional em `static`. |
| `moving` | [Segmento]? | Substitui o cálculo (E9). É obrigatório em `static` com 1 quadro. Uma chave do lado de cá vale também para o lado de lá. |
| `works` | String? **(novo)** | Até 60 caracteres, em minúsculas no meio da frase: substitui o "Trabalha: …" tirado do catálogo. Obrigatório nos padrões `cardio` ("coração e pulmões, com as pernas") e `neck` ("pescoço"), porque ali o grupo primário é convenção (§7.4). |
| `a11y` | String | De 1 a 240 caracteres: descreve o movimento para o VoiceOver. |
| `steps` | [String] | Exatamente 3, cada um com 1 a 120 caracteres (E2). |
| `mistakes` | [String] | Exatamente 2, cada um com 1 a 120 caracteres, no formato "erro: o que fazer", com ": " (E2). |

**Pontos do esqueleto** (nomes normativos, usados em `anchor.joint`, `attach`, `cue.track`, `cable.to` e no golden):
- vista lateral: `hip`, `shoulder`, `head`, `knee`, `ankle`, `toe`, `heel`, `elbow`, `wrist`, `hand` (meio da palma = pegada) e `fist`, mais os do lado de lá: `kneeFar`, `ankleFar`, `toeFar`, `heelFar`, `elbowFar`, `wristFar`, `handFar`, `fistFar`;
- vista frontal: `hip`, `neckBase`, `head`, `shoulder`, `shoulderFar`, `hipJ`, `hipJFar`, `elbow`, `elbowFar`, `wrist`, `wristFar`, `hand`, `handFar`, `fist`, `fistFar`, `knee`, `kneeFar`, `ankle`, `ankleFar`, `toe` e `toeFar`.

**Segmentos** (em `moving`, E9 e E10): `trunk`, `head`, `thigh`, `shin`, `foot`, `upperArm` e `forearm`, mais `thighFar`, `shinFar`, `footFar`, `upperArmFar` e `forearmFar`.

As pontas de cada segmento:

| Segmento | Pontas |
|---|---|
| `trunk` | `hip`→`shoulder` (na vista frontal, `hip`→`neckBase`) |
| `head` | `shoulder`→`head` |
| `thigh` | `hip`→`knee` (na vista frontal, `hipJ`→`knee`) |
| `shin` | `knee`→`ankle` |
| `foot` | `ankle`→`toe` |
| `upperArm` | `shoulder`→`elbow` |
| `forearm` | `elbow`→`wrist` |

**Quadro:**

| Campo | Regra |
|---|---|
| `label` | `"Início"`, `"Meio"`, `"Fim"` ou `"Posição"`. Com 2 quadros, Início e Fim; com 3, Início, Meio e Fim; num `static` de 1 quadro, Posição. |
| `caption` | De 1 a 28 caracteres, em pt-BR. |
| `pose` | Na vista lateral, `trunk`, `neck`, `thigh`, `shin` e `foot` são obrigatórios. `upperArm` e `forearm` são obrigatórios quando os braços são por ângulos. `thighFar`, `shinFar`, `footFar`, `upperArmFar` e `forearmFar` são opcionais (padrão = o lado de cá). Na vista frontal: `trunk`, `neck`, `thigh`, `shin`, `upperArm` e `forearm`, com o lado de lá espelhado por padrão. **Todos os quadros da guia têm o mesmo conjunto de chaves.** |
| `grip` | `[x, y]`, obrigatório com `arms.reach: "grip"`. |
| `armDepth` | Número ou `[braço, antebraço+mão]`, entre 0,3 e 1. |
| `legDepth` **(novo)** | Número ou `[coxa, perna]`, entre 0,3 e 1: escorço das pernas (por exemplo, sentado visto de frente). |
| `elbow` | Graus: dica do lado do cotovelo no IK. |
| `root` **(novo)** | `[x, y]` do quadril, obrigatório com `anchor.joint: "none"`. |

**Braços:**

| Campo | Regra |
|---|---|
| `reach` | `"grip"` ou o id de um acessório preso em `back`, `chest` ou `hip` (IK de dois ossos). |
| `depth` | Escorço padrão dos braços. |
| `elbow` | Dica padrão do lado do cotovelo; padrão −90. |
| `forearm` | Ângulo travado do antebraço. Só com `reach`. |
| `farArm` **(novo)** | `"mirror"` (padrão: o braço de lá repete o de cá) ou `"pose"` (o braço de lá segue `upperArmFar` e `forearmFar` dos quadros, por ângulos, enquanto o de cá usa IK). |

**Cena** (fixa). Todos os itens aceitam `id` (único na guia), `layer` (`"back"`, `"mid"` ou `"front"`; padrão abaixo) e `tone` (`"structure"`, o padrão, ou `"soft"`).
- Do protótipo:
  - `bench {x, top, length}` (mid);
  - `seat {x, top, length}` (mid);
  - `rail {x1, x2}` (back);
  - `tower {x, width, height}` (back);
  - `footPlate {at, length, angle}` (back);
  - `pulley {id, at}` (mid; `id` obrigatório).
- **Novos:**
  - `block {x, y, width, height}`: retângulo arredondado, como caixa, degrau, assento de cadeira ou apoio do búlgaro (mid);
  - `pad {at, length, angle, thick = 0.042}`: cápsula girada, como encosto, apoio do joelho, guidão ou apoio do peito (mid);
  - `post {from, to, thick = 0.024}`: barra fina entre dois pontos, como armação, tubo, suporte ou trilho inclinado (back);
  - `wheel {at, radius}`: aro, como volante do remo, pedivela ou barra fixa vista de ponta com `radius` 0.018 (mid);
  - `steps {x, count, rise, run}`: escada que sobe para a frente a partir de x (back).
- Ponto de referência de um item, para `cable.from` e `band.from`: `at` em `pulley`, `wheel`, `pad` e `footPlate`; `to` em `post`. Nos outros itens não pode.

**Acessórios** (movem-se com o corpo). Todos têm `id` (único na guia) e `kind`. Os tipos:
- `barbell`: anilha vista de frente;
- `dumbbell`: disco visto de ponta;
- `kettlebell`: sino pendurado abaixo da pegada;
- `ball`: medicine ball, raio 0.07, centrada na pegada;
- `vHandle`: puxador em V;
- `bar`: puxador reto visto de ponta (puxada, tríceps na polia);
- `rope`: corda da polia, em dois fios;
- `plate {length, angle}`: placa girada, com ângulo absoluto, como a plataforma do leg press, o pedal ou o banco móvel do remo;
- `roller {radius = 0.035}`: rolo acolchoado;
- `jumpRope`: a corda sai das mãos e passa por baixo dos pés;
- `cable {from, to}`: linha de um item da cena até um acessório ou um ponto do esqueleto;
- `band {from, to}`: elástico, uma linha mais grossa.

Onde o acessório fica (`attach`, em todos menos `cable` e `band`):
- **Ponto do esqueleto** (`hand`, `handFar`, `head`, `hip`, `shoulder`, `knee`, `ankle`, `toe`…): o ponto mais `offset: [dx, dy]`, no mundo, com padrão [0, 0].
- **`back`** (do protótipo): `shoulder` + `offset[0]` × frente + `offset[1]` × cima, no referencial do tronco (cima = `Dir(trunk)`, frente = `Dir(trunk − 90)`). É desenhado atrás do tronco.
- **`chest`** **(novo)**: a mesma conta, desenhada na frente do tronco (por exemplo, a barra do agachamento frontal).
- **Segmento** **(novo)** (`thigh`, `shin`, `foot`, `upperArm` e `forearm`, com os do lado de lá): proximal + (distal − proximal) × `along` + n × `side`, com n = unitário(distal − proximal) girado +90°. O `along` vai de 0 a 1 e é obrigatório; o `side` tem padrão 0.
- Na vista lateral com `farArm: "mirror"`, um acessório em `hand` é desenhado uma vez só. Na vista frontal, os acessórios de mão aparecem nas duas mãos, como no protótipo.

**Seta (`cue`):**
- `track`: um ponto do esqueleto ou o id de um acessório.
- `span: [a, b]`, com 0 ≤ a < b ≤ 1.
- Afastamento, de dois jeitos (um ou os dois, como no protótipo): `offset: [dx, dy]`, ou `side` (`"left"` ou `"right"`) com `gap` maior que 0.
- Caminho: o do protótipo (`Get-CuePath`). São 80 passos em t ∈ [0, n − 1], reamostrados por comprimento de arco em 41 pontos.

**Cálculo normativo:** é o do protótipo. Isso inclui `Solve-Guide`, `Solve-Front`, `Solve-TwoBone`, `Set-ForearmPoints`, `LerpAngle` e `Ease`. O resto (`%` como `truncatingRemainder`, o `Get-Moving` com 12° e 0,04 H entre o primeiro e o último quadro, o `Get-CuePath` e as constantes `$Rig`, `$GripAt` = 0,40 e `$FistAt` = 0,55) também vem do protótipo, com estas extensões:
- (a) `legDepth` multiplica os comprimentos da coxa e da perna e é interpolado como o `armDepth`.
- (b) Com braços por ângulos, os braços saem por cinemática direta antes da translação da âncora, e depois tudo é transladado. Com braços por IK, a âncora é aplicada primeiro e os braços são resolvidos depois, como no protótipo. Âncora num ponto do braço com IK é inválida.
- (c) Com `anchor: none`, o quadril fica em `lerp(root_i, root_i+1, u)`, com o mesmo u suavizado dos ângulos, e não há translação.
- (d) Com `farArm: pose` na vista lateral, o braço de lá sai por cinemática direta a partir do `shoulder`, com `upperArmFar`, `forearmFar` e o mesmo escorço do de cá.
- (e) Os acessórios são calculados depois dos braços. `arms.reach` com um acessório exige que ele esteja em `back`, `chest` ou `hip`, que são calculados antes dos braços.

**Tempo** (`loop`): ciclo = `hold` + `toEnd` + `hold` + `toStart`. Para s no ciclo:
- s < `hold` → t = 0;
- na ida, t = (n − 1) × (s − `hold`) / `toEnd`;
- no fim, t = n − 1;
- na volta, t = (n − 1) × (1 − (s − 2 × `hold` − `toEnd`) / `toStart`).

A suavização (`Ease`) é aplicada dentro de cada trecho entre quadros.

**Validação.** São as mesmas regras no Swift (`ExerciseGuideValidator`) e na ferramenta (`-Check`):
- **Formato:** tipos, campos obrigatórios, enumerações, ids únicos, referências de `reach`, `from`, `to`, `track` e `attach` existentes, e as mesmas chaves de pose em todos os quadros. Chave desconhecida em qualquer nível: o `-Check` recusa e o decodificador Swift ignora.
- **E1:** slug existe no catálogo do seed; uma guia por slug.
- **E2:** número de quadros, rótulos, legendas, passos, erros, `a11y` e `works` obrigatório em `cardio` e `neck`.
- **E3:** rig `mannequin-v2`.
- **E4 e E6:** coordenadas finitas em t = 0, 0,05, …, n − 1. A mão chega ao alvo alcançável com tolerância de 0,005 H. Com o antebraço travado, |cotovelo − ombro| ≤ braço + 0,005 H.
- **E5:** a âncora fica parada, com tolerância de 0,001 H.
- **E7:** faixas de `timing`.
- **E9:** as chaves de `moving` são segmentos válidos.
- **E10 (novo, só na vista lateral e para os dois lados):** as articulações ficam dentro de faixas possíveis em todo t amostrado, com o ângulo relativo normalizado para (−180°, 180°]. O ângulo de cada segmento é medido nos pontos resolvidos (`atan2` entre as pontas).

  | Articulação | Ângulo relativo | Faixa aceita |
  |---|---|---|
  | joelho | `shin − thigh` | [−165°, 5°] |
  | tornozelo | `foot − shin` | [0°, 140°] |
  | pescoço | `neck − trunk` | [−60°, 60°] |
  | quadril | `thigh − trunk` | [150°, 180°] ∪ [−180°, −25°] |

  O cotovelo fica de fora, porque o braço sai do plano do desenho e engana. Conferi as 4 guias do protótipo com uma porta do `Solve-Guide`: passam. O agachamento vai de −103° a 2° no joelho, de 76° a 103° no tornozelo e de −174° a −62° no quadril. No supino, o braço precisa de no máximo 0,168 H (limite 0,186).

Mensagem de erro: `ExerciseGuideError(slug:rule:message:)`, com `rule` de "E1" a "E10" ou "format".

### 2.6 API pública de `TrainerCore/Guide` (congelada; dona: `guide-engine`)

A dona pode acrescentar tipos e funções; não pode mudar estes.

```swift
public struct GuidePoint: Codable, Sendable, Hashable { public let x: Double; public let y: Double }
public enum GuideJoint: String, CaseIterable, Sendable { case hip, shoulder, head, … }   // raw values = nomes de §2.5
public enum GuideSegment: String, CaseIterable, Sendable { case trunk, head, thigh, … }  // raw values = nomes de §2.5
public struct ExerciseGuide: Codable, Sendable, Hashable, Identifiable { public var id: String { slug }; public let slug: String; … }
public struct ExerciseGuideCatalog: Codable, Sendable, Hashable {
    public static let empty: ExerciseGuideCatalog
    public let guides: [ExerciseGuide]
    public static func decode(_ data: Data) throws -> ExerciseGuideCatalog      // só decodifica
    public func guide(forSlug slug: String) -> ExerciseGuide?
}
public struct ExerciseGuideError: Error, Sendable, Hashable { public let slug: String?; public let rule: String; public let message: String }
public enum ExerciseGuideValidator {
    public static func problems(in catalog: ExerciseGuideCatalog, exercises: [ExerciseDefinition]) -> [ExerciseGuideError]
    public static func validate(_ catalog: ExerciseGuideCatalog, exercises: [ExerciseDefinition]) throws   // lança o primeiro problema
}
public struct GuideSkeleton: Sendable, Hashable {
    public let points: [GuideJoint: GuidePoint]
    public let props: [String: GuidePoint]        // por id do acessório; nas mãos da vista frontal, também "<id>Far"
    public let isFront: Bool
}
public enum GuideKinematics { public static func skeleton(of guide: ExerciseGuide, at t: Double) -> GuideSkeleton }  // t em 0...(n − 1), fora da faixa é limitado
public enum GuideMotion {
    public static func movingSegments(of guide: ExerciseGuide) -> Set<GuideSegment>       // E9, com `moving` quando existe
    public static func cuePath(of guide: ExerciseGuide) -> [GuidePoint]                   // 41 pontos; vazio sem `cue`
}
public enum GuideTiming {
    public static func cycleSeconds(of guide: ExerciseGuide) -> Double                    // 0 em static
    public static func frameTime(of guide: ExerciseGuide, atSeconds seconds: Double) -> Double
}
public enum GuideRig { /* comprimentos e raios de §2.5 (E3) */ }
```

### 2.7 Ferramenta de autoria e lotes (congelada; dona: `guide-engine`)

Todos os arquivos ficam em `docs/design/exercise-guides/`.

**Renderizador** `render-exercise-guides.ps1`: o protótipo, promovido no mesmo lugar e rodado com `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`.

| Opção | O que faz |
|---|---|
| `-Data <json>` | Arquivo de guias. Padrão: `PersonalTrainer/Resources/Seed/exercise-guides.v1.json`. |
| `-Catalog <json>` | Catálogo do seed. Padrão: `exercises.v2.json` do seed. |
| `-Check` | Só valida (§2.5). Imprime `ok <slug>` ou `ERRO <slug> <regra>: <motivo>` e sai com código 1 se houver erro. |
| `-Sheet <nome>` | Gera `sheet-<nome>.png` e `sheet-<nome>-dark.png`, com todos os quadros de cada guia, "Trabalha: …", legendas, passos, erros e a frase do VoiceOver. |
| `-Golden <saída.json>` | Grava as coordenadas de referência (formato abaixo). |
| `-Only <slug,slug>` | Filtra as guias. |
| `-Vocabulary` | Gera `vocabulary.png` a partir de `vocabulary.sample.json`: um exemplo de cada tipo de cena e de acessório, nos modos claro e escuro, para os autores verem o que existe. |
| `-Out <pasta>` | Pasta de saída. |

**Lotes:**
- Manifesto `batches.json`: `{"version": 1, "batches": [{"id": 0, "title": "…", "slugs": [ … ]}, …]}`, com a lista de §4.
- Um arquivo `batch-<id>.json` por lote, no formato de §2.5 e só com os slugs daquele lote.
- **O arquivo do seed é gerado; nunca o edite à mão.**

**Junção** `merge-guides.ps1`:
- lê o manifesto e os `batch-*.json` que existirem;
- recusa slug fora do manifesto do lote, slug repetido e lote com erro de `-Check`;
- grava `PersonalTrainer/Resources/Seed/exercise-guides.v1.json` com as guias em ordem de slug. O serializador é próprio e determinístico: 2 espaços, listas de números numa linha, chaves na ordem de §2.5, números com até 6 casas, UTF-8 sem BOM e LF. Rodar duas vezes dá os mesmos bytes;
- roda `-Check` e `-Golden` sobre o resultado, gravando `Packages/TrainerCore/Tests/TrainerCoreTests/Fixtures/exercise-guides-golden.v1.json`;
- lista os slugs de §4 que ainda faltam.

**Golden:**

```json
{"version":1,"tolerance":0.001,"guides":[{"slug":"…","samples":[{"t":0.0,"points":{"hip":[x,y],…},"props":{"barbell":[x,y]}}, …],"moving":["shin","thigh",…],"cue":[[x,y], …]}]}
```

- `samples` traz t = 0, ¼, ½, ¾ e 1 × (n − 1);
- `moving` vem em ordem alfabética;
- `cue` traz os pontos 0, 10, 20, 30 e 40 dos 41;
- os números têm 6 casas.

## 3. Tarefas

Resumo:

| Chave | TASKS | Worktree | Branch | CI | Tipo |
|---|---|---|---|---|---|
| `core` | T8.1 | `C:\Users\leona\Developer\pt-wt\w6-core` | `v6/core` | `ci/v6-core` (App build + Core tests) | [CI] + TrainerCore + seed |
| `guide-engine` | T8.2 (= T6.1 + T6.4) | `C:\Users\leona\Developer\pt-wt\w6-guide-engine` | `v6/guide-engine` | push no próprio branch (Core tests) | TrainerCore + PowerShell |

### 3.1 `core` — carga opcional, Fôlego, Equilibrado e minutos (T8.1; SPEC D1–D4)

**Arquivos (exclusivos):**
- TrainerCore:
  - `Sources/TrainerCore/Domain/ExerciseMeasure.swift`, `MovementPattern.swift`, `GoalDefaults.swift`, `ProgramGoal.swift` e `CardioDefaults.swift` (novo);
  - `Sources/TrainerCore/Engine/DoubleProgressionRule.swift`, `DeloadPolicy.swift` e `HomeSubstitution.swift` (H2: aeróbico e não aeróbico nunca se equivalem por grupo, como o pescoço);
  - `Sources/TrainerCore/Review/ProgramReviewer.swift`, `ProgramReviewer+Signals.swift` e `ProgramReviewer+Suggestions.swift`;
  - todos os testes existentes em `Tests/TrainerCoreTests/`, e testes novos como `CardioProgressionTests.swift`. Os arquivos novos de guia (§3.2) são da `guide-engine`.
- Seed: `PersonalTrainer/Resources/Seed/exercises.v2.json`, `programs.v2.json` e `references.v1.json`.
- App:
  - `Services/Seed/SeedLoader.swift` (só `currentSeedVersion` e o comentário);
  - `Features/DesignSystem/GoalStyle.swift`;
  - `Features/Program/GoalPlanCatalog.swift`;
  - `Services/Coach/CoachService+Actions.swift`;
  - `Features/Session/MeasureText.swift` e `SessionSheetText.swift`;
  - `Features/ExerciseInfo/TodayTargetText.swift` e `ExerciseInfoText.swift`;
  - `Services/Planning/SessionDurationEstimate.swift`;
  - `Persistence/Repositories/ProgramRepository.swift`;
  - `PreviewSupport/ProgramPreviewSupport.swift`.
- Testes do app: os que quebrarem por causa desta tarefa, mudando só as expectativas ligadas a D1–D4, ao seed ou aos nomes. Os prováveis:
  - `Features/Program/GoalPlanCatalogTests.swift`, `GoalPlanTestDoubles.swift`, `GoalSheetModelTests.swift` e `PlanTabModelTests.swift`;
  - `Features/DesignSystem/FlowerAndGoalStyleTests.swift`;
  - `Features/ExerciseInfo/TodayTargetTextTests.swift` e `ExerciseInfoTextTests.swift`;
  - `Features/Session/MeasureAndRIRTextTests.swift` e `SessionSheetTextTests.swift`;
  - `Features/History/MeasureHistoryTests.swift`;
  - `Features/Home/PrescriptionRowMeasureTests.swift`;
  - `Features/HomeViewModelTests.swift`;
  - `Integration/FullLoopTests.swift`;
  - `Services/SeedLoaderTests.swift`, `CoachServiceTests.swift`, `SessionPlannerTests.swift`, `SessionPlannerHomeModeTests.swift` e `BackupServiceTests.swift`;
  - `Persistence/ProgramRepositoryTests.swift`.

**O que fazer:**
1. **D4:** `ExerciseMeasure.minutes`, `MovementPattern.cardio` ("Aeróbico"; `isCompound` = false, com comentário) e `CardioDefaults` (§2.1). Atualize todo `switch` do app sobre `ExerciseMeasure` (§2.4). O `switch` de `ProgramRepository` sobre `MovementPattern` tem `default`, mas ganha o caso `.cardio`.
2. **D3 no motor:** a tabela de §2.2 em `DoubleProgressionRule` e `DeloadPolicy.deloadLoad`, com comentários `// SPEC P8 (D3)`. O motor lê `exercise.movementPattern`; nada de medida nem de FC entra nele.
3. **D2:**
   - `ProgramGoal.displayName` passa a ser "Fôlego" e `GoalDefaults.endurance` recebe os valores de §2.1;
   - no seed, os 10 exercícios, o programa Fôlego, a saída do antigo "Resistência muscular" e as referências (§2.3);
   - `GoalStyle` e `GoalPlanCatalog` (§2.4).
4. **D1:** o programa Equilibrado ativo no seed, `GoalPlanCatalog`, `CoachService.hypertrophyFormats` e o Corpo todo escondido (§2.4).
5. **Revisão (SPEC §7.8):**
   - os aeróbicos saem de R1 (estagnação, `progress` = nil), de R3 (séries por grupo) e das sugestões de R5 por exercício (faixa vizinha e troca);
   - continuam contando em R2 (notas) e R4 (aderência);
   - o texto da R5 `switchProgram` muda (§2.4).
6. `SeedLoader.currentSeedVersion` = 4, e `"version": 4` nos dois JSON.
7. `ProgramRepository`: `CardioDefaults` para um aeróbico novo; `setGoal(withDefaults:)` pula aeróbicos.
8. `HomeSubstitution` (SPEC H2, 2.3): no passo "mesmo grupo primário", aeróbico e não aeróbico nunca se equivalem, com a mesma trava que já separa o pescoço.

**Testes:**
- TrainerCore (Swift Testing, nome pela regra):
  - `P8 D3` em várias versões: equipamento sem carga fica em 0 e segura no topo; aeróbico de peso do corpo sem carga segura no topo; peso do corpo não aeróbico ainda ganha a carga extra; P6 repetido com 0 é `retry`; P9 com 0 fica em 0; `startingLoad` 0 fica em 0;
  - `F3`: minutos sobem 1 por sessão até o topo; aeróbico com nível sobe 1 nível e recomeça no mínimo;
  - `§7.5 D3`: a semana leve com 0 fica em 0;
  - `P10 D3`: a primeira carga depois de sessões em 0 vira a referência;
  - `R1/R3/R5 aeróbico fora`;
  - `RF-43 minutes`: decodifica pelo catálogo;
  - `H2`: o equivalente de casa da bicicleta é um aeróbico de casa medido em minutos; um exercício de pernas sem equivalente de casa nunca vira um aeróbico pelo grupo;
  - `RF-34`: todo aeróbico tem ao menos 2 substitutos;
  - `SeedBundleTests` atualizado:
    - 8 programas, só o Equilibrado ativo;
    - o Equilibrado com 4 dias alternando superior e inferior, 5 exercícios por dia e cada grupo como primeiro primário de exatamente 2 exercícios;
    - o Fôlego com 3 dias, um aeróbico em minutos por dia e de 1 a 2 complementos;
    - exceções documentadas dos 5 exercícios por dia e da tabela do objetivo nos aeróbicos;
    - incremento 1 nas máquinas medidas em nível;
  - `ReferenceCatalogTests`: as 3 referências novas e `topic.cardio`.
- App (XCTest):
  - `testRF45_catalog_balancedIsFirstFormat`;
  - `testRF45_catalog_fullBodyHiddenUnlessActive`, que mostra o título "Corpo todo" como extra;
  - `testRF45_catalog_enduranceResolvesToFolego`;
  - `testS1_subtitles`, com o subtítulo do Fôlego;
  - `testRF43_minutesTexts` (tabela de §2.4);
  - `testC2_nextFormatAfterFullBodyIsBalanced`;
  - `testSeedLoader_v4_insertsBalancedAndFolegoInactive_keepsLegacyEndurance`, sobre um store com o seed 3: os dois entram inativos, o ativo antigo continua e o `CBE66162-…` fica.

**Aceite:** App build e Core tests verdes em `ci/v6-core`, CA8-1 a CA8-5 cobertos e lista Verificado/Incerto.

### 3.2 `guide-engine` — motor e ferramenta do "Como fazer" (T8.2 = T6.1 + T6.4; SPEC §7.12 E1–E10)

**Arquivos (exclusivos):**
- `Packages/TrainerCore/Sources/TrainerCore/Guide/*` (novo), com um tipo público por arquivo, por exemplo:
  - `ExerciseGuide.swift`, `ExerciseGuideCatalog.swift`, `GuideFrame.swift`, `GuidePose.swift`, `GuideArms.swift`;
  - `GuideSceneItem.swift`, `GuideProp.swift`, `GuideCue.swift`, `GuidePoint.swift`, `GuideJoint.swift`, `GuideSegment.swift`;
  - `GuideRig.swift`, `GuideKinematics.swift`, `GuideSkeleton.swift`, `GuideMotion.swift`, `GuideTiming.swift`;
  - `ExerciseGuideValidator.swift` e `ExerciseGuideError.swift`.
- Testes novos em `Packages/TrainerCore/Tests/TrainerCoreTests/`:
  - `ExerciseGuideTests.swift` (formato e E1–E10, lendo os arquivos reais por `#filePath`);
  - `GuideKinematicsTests.swift` (âncora, IK, antebraço travado, `farArm`, `legDepth`, `anchor: none` e tempo);
  - `GuideGoldenTests.swift` (paridade com o golden em até 0,001 H, com o mesmo `moving` e a mesma seta);
  - `ExerciseGuideCoverageTests.swift`, com `@Test(.disabled("liga na integração, V23 §5"))`: todo slug de `programs.v2.json` e todo aeróbico do catálogo tem guia;
  - `Fixtures/exercise-guides-golden.v1.json`.
- `Packages/TrainerCore/Package.swift`: só `exclude: ["Fixtures"]` no alvo de testes.
- `PersonalTrainer/Resources/Seed/exercise-guides.v1.json`, gerado pela junção só com o lote 0.
- `docs/design/exercise-guides/`:
  - `render-exercise-guides.ps1` (promovido) e `merge-guides.ps1` (novo);
  - `batches.json` (§4) e `batch-0.json` (as 4 guias do protótipo);
  - `vocabulary.sample.json`, `vocabulary.png`, `sheet-0.png` e `sheet-0-dark.png`;
  - opcional: `AUTHORING.md`, com dicas práticas de pose para os autores dos lotes.
- `ARCHITECTURE.md`: §11 (o arquivo de guias, gerado pela junção, com o formato em `docs/V23-CORE-CONTRACT.md` §2.5) e §17 (pastas `Guide/`, `Tests/…/Fixtures/`, e as futuras `Features/ExerciseGuide/` e `Services/ExerciseGuides/`).
- Não toque em nenhum outro arquivo do seed, do app ou dos testes do app.

**O que fazer:**
1. **Swift** (§2.5 e §2.6): tipos Codable que decodificam o formato inteiro, cinemática (o protótipo mais as extensões a–e), E9, seta, tempo e o validador E1–E10.
   - Só Foundation. Nada de `Date()` nem aleatório.
   - Determinístico: a mesma guia e o mesmo t dão as mesmas coordenadas.
   - `ExerciseGuideCatalog.decode` só decodifica; quem valida é o `ExerciseGuideValidator`.
2. **Lote 0:** porte as 4 guias do `exercise-guides.sample.json` para `batch-0.json` sem mudar as poses. Se o validador reprovar alguma, ajuste o mínimo e registre no relatório.
3. **Ferramenta** (§2.7):
   - no renderizador, o formato inteiro;
   - todas as cenas e acessórios novos, desenhados no estilo do DESIGN §12, com contraste ≥ 3:1 no que se move (o `Test-Contrast` continua);
   - a folha por lote com 1, 2 ou 3 quadros por guia e o "Trabalha:" com `works`;
   - `-Check`, `-Golden`, `-Only` e `-Vocabulary`;
   - a junção determinística.
4. **Vocabulário:** `vocabulary.sample.json` com uma guia de exemplo por recurso novo e `vocabulary.png` gerado. Os exemplos:
   - `block`, `pad`, `post`, `wheel` e `steps`;
   - `kettlebell`, `ball`, `bar`, `rope`, `plate`, `roller`, `jumpRope` e `band`;
   - `anchor` na mão e `none`;
   - `farArm: pose`, `legDepth`, `static` com 1 quadro e `chest`.

   Os slugs de exemplo começam com `vocab-` e o `-Check` do vocabulário roda com `-Catalog` desligado para eles (opção interna). Eles nunca vão para o seed.
5. **Paridade:** gere o golden do lote 0 com a ferramenta e faça o `GuideGoldenTests` comparar. Se Swift e PowerShell divergirem, corrija o que estiver fora de §2.5.
6. Documente em ARCHITECTURE §11 e §17.

**Testes (Swift Testing, nome pela regra):**
- `E1` a `E10` com um caso bom e um ruim cada;
- `format`: chave obrigatória ausente, `reach` para acessório inexistente e poses com chaves diferentes;
- `E4 determinismo`;
- `E5 âncora parada em cada t`;
- `E6 antebraço travado não estica o braço`;
- `E7 tempo`: t nas quatro fases e nas bordas;
- `E9` sobre as 4 guias do protótipo: agachamento com coxa e perna, e braços parados;
- `GuideGolden` com o lote 0;
- o arquivo do bundle decodifica e passa (E8: "os testes garantem que o arquivo do bundle passa").

**Aceite:**
- Core tests verdes;
- `-Check` limpo no lote 0;
- `sheet-0.png`, `sheet-0-dark.png` e `vocabulary.png` conferidos a olho;
- a junção idempotente (rodar duas vezes não muda o arquivo);
- CA8-6 e CA8-7 cobertos.

## 4. Onda de conteúdo (T8.3, depois de §5 passo 1)

Um agente por lote. Cada um trabalha no branch `v6/guides-<id>`, no worktree `C:\Users\leona\Developer\pt-wt\w6-guides-<id>`, a partir do sha de §5 passo 1. Rode no máximo 3 lotes ao mesmo tempo (limite de uso do plano, HANDOFF §7).

**Escopo exclusivo** de cada lote, em `docs/design/exercise-guides/`: `batch-<id>.json`, `sheet-<id>.png` e `sheet-<id>-dark.png`. Nada mais: o seed e o golden são gerados na integração.

| Lote | Tema | Slugs |
|---|---|---|
| 0 | Protótipo (`guide-engine`) | `barbell-back-squat`, `barbell-bench-press`, `seated-cable-row`, `dumbbell-lateral-raise` |
| 1 | Barra | `barbell-curl`, `barbell-deadlift`, `barbell-hip-thrust`, `barbell-overhead-press`, `barbell-romanian-deadlift`, `barbell-row`, `front-squat`, `hex-bar-deadlift` |
| 2 | Halteres e kettlebell | `alternating-dumbbell-curl`, `dumbbell-bulgarian-split-squat`, `dumbbell-romanian-deadlift`, `dumbbell-shoulder-press`, `dumbbell-step-up`, `goblet-squat`, `hammer-curl`, `incline-dumbbell-bench-press`, `kettlebell-deadlift`, `kettlebell-swing`, `one-arm-dumbbell-row`, `overhead-dumbbell-triceps-extension` |
| 3 | Máquinas e polias | `cable-crunch`, `cable-triceps-pushdown`, `chest-press-machine`, `hip-abduction-machine`, `lat-pulldown`, `leg-extension`, `leg-press-45`, `lying-leg-curl`, `pallof-press`, `seated-calf-raise`, `seated-leg-curl`, `standing-calf-raise` |
| 4 | Peso do corpo e tronco | `back-extension-45`, `bird-dog`, `box-squat`, `chin-up`, `dead-bug`, `hanging-leg-raise`, `knee-push-up`, `pull-up`, `push-up` |
| 5 | Carregar, potência e pescoço | `box-jump`, `dumbbell-farmers-walk`, `kettlebell-farmers-walk`, `medicine-ball-chest-pass`, `medicine-ball-rotational-throw`, `neck-isometric-band`, `suitcase-carry` |
| 6 | Aeróbico (novos da D2) | `bike-intervals`, `bodyweight-circuit`, `brisk-walk`, `easy-run`, `elliptical`, `jump-rope`, `rowing-machine`, `run-intervals`, `stair-climb`, `stationary-bike` |

São 62 guias: 52 dos programas do seed, contando o Corpo todo e o Empurrar/Inferior/Puxar, que ficam escondidos, e mais os 10 aeróbicos.

**Como autorar:**
- Leia §2.5, `vocabulary.png` e `sheet-0.png`.
- Escreva as guias. Rode `-Check -Data batch-<id>.json` até ficar limpo e depois `-Sheet <id> -Data batch-<id>.json`.
- **Abra os dois PNG e confira cada quadro:** pés no chão, mão na barra, nada atravessando o corpo ou o banco, o que se move em acento forte e a seta no caminho certo. Corrija e repita.
- Commit só com a folha aprovada por você.

**Regras do conteúdo:**
- **Texto:** pt-BR, no tom do DESIGN §6. São 3 passos no imperativo ("Apoie…", "Desça…", "Suba…") e 2 erros no formato "o erro: o que fazer". Palavras próprias: nada copiado de sites, livros ou apps. Sem jargão de academia, sem "falha" e sem RIR.
- **Legendas:** até 28 caracteres, descrevendo a posição ("Coxas paralelas ao chão").
- **Cena:** não decida pelo campo `equipment` do catálogo, porque os 6 exercícios de medicine ball estão como `dumbbell`. A máquina é genérica, só sugerida.
- **Difíceis:** podem sair `motion: "static"`, com setas: `pallof-press`, `medicine-ball-rotational-throw`, `hip-abduction-machine`, `neck-isometric-band`, `jump-rope`, `bodyweight-circuit` e, se a pedalada não ler bem, `stationary-bike` e `bike-intervals`.
- **Aeróbicos:**
  - `works` = "coração e pulmões, com as pernas";
  - os passos dizem a intensidade pelo teste da fala: no moderado, dá para conversar mas não para cantar; no forte, só dá para dizer poucas palavras; no leve, a conversa é fácil;
  - nos intervalos, o descanso é andar ou pedalar devagar;
  - nada de FC, zonas ou ritmo em números (SPEC §7.14 F2).
- **Pescoço:** `works` = "pescoço". O movimento é isometria leve: empurrar sem mexer a cabeça.

## 5. Integração (T8.4)

1. Com `core` e `guide-engine` verdes, o integrador faz `git merge v6/core` no worktree `w6-guide-engine`. Não há arquivo em comum. Depois roda `merge-guides.ps1` (que confere o `-Check` do lote 0 contra o catálogo novo) e faz o push de `v6/guide-engine` e de `ci/v6-guides` (App build e Core tests verdes). **Esse sha é a base da onda de conteúdo (§4).**
2. Cada lote pronto é mesclado em `v6/guide-engine`; conflitos não devem existir. Com todos (ou os que chegarem), o integrador:
   - roda `merge-guides.ps1`;
   - revisa o `-Check` e as folhas;
   - liga o `ExerciseGuideCoverageTests` quando os 62 estiverem lá;
   - faz o push e espera o Core tests verde. Se o Swift reprovar uma guia que passou no `-Check`, a correção vai para a ferramenta ou para o validador, na `guide-engine`.
3. Marca T8.1 a T8.4 no TASKS e anota os dados das folhas para a revisão do dono (CA6-7).
4. **Nada vai para o `main` nesta rodada.** Sem a onda de telas, a bicicleta do Fôlego pede carga (RF-44 c ainda vale na tela), e não há onde ver o "Como fazer". A onda de telas parte de `v6/guide-engine` já com o `v6/core`.

## 6. Critérios de aceitação desta rodada

| CA | Verificação |
|----|-------------|
| CA8-1 | D3 no motor: equipamento com carga 0 continua em 0, sobe as repetições até o topo e fica lá; peso do corpo não aeróbico mantém a carga extra no topo; P6 repetido em 0 é `retry`; semana leve e P9 em 0 ficam em 0 (testes P8 D3). |
| CA8-2 | `ExerciseMeasure.minutes` com os textos de §2.4 no app, e a progressão por minutos: +1 por sessão até o topo e nível opcional (testes F3 e RF-43). |
| CA8-3 | Fôlego: nome, subtítulo e símbolo; o plano do seed resolve para `09AB286E-…`; 3 dias com um aeróbico em minutos por dia; 10 aeróbicos no catálogo com substitutos e equivalentes de casa; referências conferidas no Crossref. |
| CA8-4 | Equilibrado: ativo no seed, 4 dias Superior/Inferior e cada grupo como primeiro primário de 2 exercícios por semana. É o primeiro formato; o Corpo todo só aparece ativo, com o título "Corpo todo"; o C2 vai do Corpo todo para o Equilibrado. |
| CA8-5 | Seed 4 num store com o seed 3: Equilibrado e Fôlego entram inativos; nada existente muda nem some. |
| CA8-6 | `TrainerCore/Guide`: E1–E10 testados, com paridade de 0,001 H com o golden do lote 0 e as 4 guias do protótipo válidas no bundle. |
| CA8-7 | Ferramenta: `-Check`, `-Sheet`, `-Golden` e `-Vocabulary` funcionam; a junção é idempotente; `vocabulary.png` mostra todos os recursos de §2.5. |
| CA8-8 | (onda de conteúdo) As 62 guias passam no `-Check` e no Swift, o teste de cobertura está ligado e as folhas dos 7 lotes estão prontas para o dono. |

## 7. Incertezas conhecidas

- Ninguém confirma que a pedalada, o remo e a corda leem bem no manequim 2D antes das folhas. A reserva é `static`.
- O `-Check` em PowerShell e o validador Swift podem divergir. Mitigação: as mesmas regras de §2.5, o golden e a correção na `guide-engine` quando o CI discordar.
- O E10 (faixas das articulações) pode recusar uma pose real pouco comum, como a extensão do quadril no afundo. Nesse caso, a faixa é ajustada na SPEC, com o motivo.
- A convenção "pernas como grupo primário do aeróbico" faz o Fôlego contar no painel "Esta semana" (§7.4) e na escolha do dia pela semana (S5–S7). Isso foi aceito e registrado na SPEC §7.14 F4.
- Quem está hoje no Corpo todo ou no antigo "Resistência muscular" continua nele até trocar na folha "Seu objetivo". O loader nunca troca o programa ativo sozinho.

## 8. Para a onda de telas (contrato próprio, depois da pesquisa de estética)

O núcleo deixa pronto: minutos, "Fôlego", o Equilibrado, a D3 no motor, as guias e a API de `TrainerCore/Guide`. Falta nas telas:
1. **D3 na ficha** (RF-44 c e RF-46, 2.3):
   - `canMark` não depende de carga;
   - sem carga, a série grava 0;
   - num exercício com equipamento e carga 0 ou vazia, o cartão mostra "sem carga", que a pessoa toca para pôr uma;
   - sai a caixa "Escolha uma carga…" como bloqueio; se ficar, vira dica opcional.
2. **Fôlego na ficha e na Hoje:**
   - "30 min" em vez de "1 série de 30 min";
   - nos intervalos, "4 × 3 min", com o descanso chamado "Recuperação andando";
   - a frase da intensidade (F2) no lugar da carga;
   - o nível da máquina opcional.
3. **"Como fazer":**
   - `ExerciseGuideLibrary` (E8), que lê o bundle, valida contra o catálogo e devolve `.empty` com log se falhar;
   - `GuideIllustrationView` com `TimelineView` + `Canvas`;
   - `GuideStaticFramesView` para Reduzir Movimento e `static`;
   - a seção na folha "Informações do exercício" (RF-47) e o botão.
4. **HealthKit do Fôlego:**
   - a sessão do Fôlego vai para o Saúde como treino aeróbico e conta nos minutos da A1;
   - vincula uma caminhada ou corrida do relógio que sobreponha a sessão.
5. **Semana leve no cardio:** reduzir minutos, não só séries.
6. A passada estética, com as direções em `docs/design/v23-aesthetics/`.
