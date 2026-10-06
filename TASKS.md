# TASKS — Plano de execução

Versão 0.1 · 2026-09-22. Regras em [SPEC.md](SPEC.md), desenho em [ARCHITECTURE.md](ARCHITECTURE.md), conduta dos agentes em [AGENTS.md](AGENTS.md).

## Como usar este arquivo

- Cada tarefa é pequena (meio dia a um dia de trabalho de um agente), tem **arquivos que pode criar/editar** ("Escopo") e **dependências** explícitas. Duas tarefas sem dependência entre si e sem interseção de escopo podem rodar em paralelo (Claude Code em uma, Codex em outra).
- Tarefas marcadas **[PROJ]** editam `project.yml`, `.github/workflows/*`, entitlements ou scripts de build. Só uma **[PROJ]** por vez, nunca em paralelo com outra **[PROJ]**.
- Tarefas marcadas **[SCHEMA]** editam `Persistence/Schema/`. Só uma por vez.
- Tarefas marcadas **[CI]** produzem código de app (iOS/watchOS) que **não compila nesta máquina** (Windows, sem Xcode): são escritas às cegas, revisadas estaticamente (AGENTS R11) e só ficam `[x]` depois de um run verde de "App build (manual)" no GitHub Actions. As demais (só `Packages/TrainerCore`) compilam e testam localmente com `Scripts/swift-test.ps1`.
- Tarefas marcadas **[USER]** só o usuário pode fazer (conta GitHub, aparelhos, credenciais Apple).
- Status: `[ ]` a fazer · `[~]` em andamento (escrever o agente e a branch) · `[x]` concluída (mergeado em `main` e verificado) · `[-]` cancelada.
- Um milestone só fecha quando **todos** os seus critérios de aceitação (CA) foram verificados manualmente ou por teste e anotados aqui.

Grupos paralelos: dentro de cada milestone, tarefas com a mesma letra de grupo (**G1**, **G2**…) podem rodar simultaneamente; grupos são sequenciais entre si.

---

## M0 — Esqueleto compilável e motor testado

**Objetivo:** projeto gerado por XcodeGen compila no CI para iPhone e Watch (placeholders), `TrainerCore` tem domínio, motor v1, resumos e DTOs de sync com testes verdes localmente e no CI Linux. Nenhuma tela funcional ainda.

**Estado em 2026-09-22:** motor, seed, sync e resumos entregues, revisados adversarialmente e testados no Windows (186 testes). Esquema SwiftData, mappers, protocolos/fakes e projeto XcodeGen escritos e revisados estaticamente (findings aplicados em `fix/app-review`), aguardando o primeiro run do CI (T0.11). Probe T0.0 pronto para o mesmo run.

**Critérios de aceitação M0**

| CA | Verificação | Estado |
|----|-------------|--------|
| CA0-1 | `Scripts/swift-test.ps1` (Windows) e o job "Core tests" (Linux) passam com ≥ 1 teste por regra P1–P9, P11, P12 e S1–S4. | ✔ Windows (186 testes) e Linux (run 35868642830, 2026-09-23) |
| CA0-2 | Job "App build (manual)" verde: `xcodegen generate`, `xcodebuild test` no simulador (PersonalTrainerTests) e build `generic/platform=iOS` sem erros de concorrência. | ✔ run 35868699393 (2026-09-23), primeira tentativa |
| CA0-3 | O IPA do job contém `Payload/PersonalTrainer.app/Watch/PersonalTrainerWatch.app` com os dois executáveis; os apps mostram "Personal — em construção". | ✔ verificado por `Scripts/build-app.sh` no mesmo run (texto dos placeholders só será visto no aparelho, V3) |
| CA0-4 | Entitlement HealthKit e strings `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription` presentes nos dois targets; `WKBackgroundModes` contém `workout-processing` (verificado por `Scripts/build-app.sh`). | ✔ mesmo run |
| CA0-5 | `ModelContainerFactory.make(.inMemory)` abre `SchemaV1` em teste XCTest e insere/lê um `WorkoutSessionModel` com um `SetLogModel`. | ✔ PersonalTrainerTests no simulador, mesmo run |
| CA0-6 | `Scripts/check-boundaries.sh` passa (R1–R3). | ✔ |
| CA0-7 | `ActiveSessionSnapshot` e `SessionEvent` fazem round-trip JSON em teste e rejeitam `schemaVersion` maior que o suportado. | ✔ |

**M0 fechado em 2026-09-23** (exceto T0.0 V3–V5, que dependem do aparelho e seguem como pré-condição de M3).

### Tarefas M0

- [~] **T0.0 [PROJ][CI][USER] Validar instalação gratuita Windows → iPhone + Watch** — V0, V1 e V2 concluídos (run "Device probe (manual)" 35868680081 verde em 2026-09-23, IPA com o Watch embutido); V3–V5 exigem aparelho e ação do usuário. Fatos verificados e roteiro em `WINDOWS_SETUP.md`.
  - Escopo: `Validation/DeviceProbe/**`, `Scripts/build-device-probe.sh`, `Scripts/check-device-probe.py`, `.github/workflows/device-probe.yml`, `WINDOWS_SETUP.md`, `README.md`, `SPEC.md`, `ARCHITECTURE.md`, `.gitignore`, esta tarefa em `TASKS.md`.
  - Fazer: app mínimo nativo com companion, HealthKit sob protocolo + Live + Fake, autorização somente por botão e leitura da última FC com data; compilação e empacotamento não assinados em macOS hospedado, acionados manualmente. Não grava treino, não implementa sessão/WatchConnectivity nem altera o domínio.
  - Ambiente: edição no Windows; `[CI]` exige compilação real com Xcode no runner macOS. Não exige Mac do usuário. O custo deve permanecer zero; não executar Actions privados sem verificar bloqueio de gasto excedente.
  - Aparelhos informados: iPhone 17 / iOS 26.6.2; Apple Watch Series 7 GPS 41 mm / watchOS 26.5. Não registrar números de série.
  - Aceite: V0 estrutura/plists conferidos; V1 build iOS+watchOS; V2 IPA com companion; V3 instalação/abertura nos dois aparelhos com conta gratuita; V4 leitura real de FC nos dois; V5 renovação da assinatura preservando instalação. V3–V5 exigem aparelho e ação do usuário.
  - Dependências: nenhuma. Executar antes de avançar o app; não substitui T0.1 nem fecha os CAs de M0. Se funcionar, reutilizar o aprendizado de build/instalação; o probe não é o app de treino.



- [x] **T0.1 [PROJ][CI] Projeto via XcodeGen, placeholders e CI** — G1 — run "App build (manual)" verde em 2026-09-23
  - Escopo: `project.yml`, `PersonalTrainer/App/{PersonalTrainerApp,RootPlaceholderView}.swift`, `PersonalTrainer/Support/PersonalTrainer.entitlements`, `PersonalTrainerWatch/App/PersonalTrainerWatchApp.swift`, `PersonalTrainerWatch/Support/PersonalTrainerWatch.entitlements`, `PersonalTrainerTests/SmokeTests.swift`, `.github/workflows/{app-build,core-tests}.yml`, `Scripts/{build-app,check-boundaries}.sh`, `.gitignore`.
  - Feito: targets PersonalTrainer (iOS 18, `com.personaltrainer.app`), PersonalTrainerWatch (watchOS 11, `com.personaltrainer.app.watchkitapp`, companion, `workout-processing`) e PersonalTrainerTests, todos com o pacote local `TrainerCore`; Info.plist gerado pelo XcodeGen (fora do Git); Swift 6 + strict concurrency; workflow macOS manual (`macos-26`, Xcode 26.6 fixado) que testa no simulador e empacota IPA sem assinatura com o Watch embutido; workflow Linux (`swift:6.3`) com testes do pacote e check de fronteiras (absorve T0.10).
  - Aceite: CA0-2, CA0-3, CA0-4 no primeiro run verde (T0.11).

- [x] **T0.11 [USER] Publicar o repositório e obter o primeiro run verde do CI** — G1 — repositório público `03052023/PersonalTrainer`; os três workflows verdes na primeira rodada (2026-09-23). O gatilho automático de "Core tests" não dispara no primeiro push de um repositório novo; a partir do segundo push funciona.
  - Fazer (só o usuário): criar repositório no GitHub (recomendado **público**: runners macOS gratuitos e ilimitados; sem segredos no repo), `git remote add origin …`, `git push -u origin main`; conferir que "Core tests" passou; rodar manualmente "Device probe (manual)" e "App build (manual)" na aba Actions; baixar os artefatos. Roteiro completo em `WINDOWS_SETUP.md`.
  - Se o job macOS falhar: colar o log de erro no chat; o agente corrige em branch `fix/ci-*` e o usuário roda de novo. Cada rodada custa ~15–30 min de runner.
  - Aceite: "Core tests" ✔; "App build (manual)" ✔ com artefato `PersonalTrainer-for-resigning.ipa`; "Device probe (manual)" ✔ com artefato `DeviceProbe-for-resigning.ipa`. Ao fechar, marcar T0.1, T0.5, T0.8, T0.9 e CA0-2…CA0-5 como `[x]`.

- [x] **T0.2 Domínio em TrainerCore** — G1 — 15 testes, Windows (2026-09-22)
  - Escopo: `Packages/TrainerCore/Sources/TrainerCore/Domain/*`, `Package.swift`.
  - Fazer: todos os structs/enums da ARCHITECTURE §4, `Codable`, `Sendable`, `Hashable`, com `init` públicos e valores padrão da SPEC §7.2. Helper `Load.round(_:toIncrement:)` (arredondamento ↓ e ↑).
  - Depende de: nada. Bloqueia: T0.3, T0.4, T0.5, T0.6, T0.7.
  - Aceite: compila em `swift build`; teste de round-trip Codable de cada struct; teste de arredondamento.

- [x] **T0.3 Motor de progressão v1** — G2 — 38 testes; inclui P9 (T2.8). Revisão adversarial e ajuste de P6/P9 em `fix/engine-spec` (2026-09-22)
  - Escopo: `Sources/TrainerCore/Engine/ProgressionRule.swift`, `Engine/DoubleProgressionRule.swift`, `Tests/TrainerCoreTests/DoubleProgressionRuleTests.swift`.
  - Feito: protocolo + implementação de P1–P12 conforme SPEC §7.2 (com as decisões de P3/P6/P8/P9 registradas lá). Casos de tabela nomeados por regra.
  - Aceite: CA0-1 (parte P) ✔.

- [x] **T0.4 Seletor de treino v1 (rotação)** — G2 — 16 testes (2026-09-22)
  - Escopo: `Sources/TrainerCore/Engine/WorkoutSelector.swift`, `Engine/RotationSelector.swift`, `Tests/.../RotationSelectorTests.swift`.
  - Feito: S1–S4; `nextDay` devolve `nil` só para programa vazio; `inProgress` ignorado (S3 é do planejador); dia desconhecido → D1; S4 emerge da sessão registrada (sem parâmetro de override).
  - Aceite: CA0-1 (parte S) ✔.

- [x] **T0.5 [SCHEMA][CI] SwiftData SchemaV1 + container factory** — G2 — testes XCTest verdes no simulador (2026-09-23)
  - Escopo: `PersonalTrainer/Persistence/Schema/SchemaV1.swift`, `Persistence/MigrationPlan.swift`, `Persistence/ModelContainerFactory.swift`, `PersonalTrainerTests/Persistence/SchemaV1Tests.swift`.
  - Fazer: os 8 modelos da ARCHITECTURE §5 exatamente (nomes, campos, inversos, delete rules), `VersionedSchema`, `SchemaMigrationPlan` com um estágio, factory `.persistent`/`.inMemory`.
  - Depende de: T0.1, T0.2 (raw values dos enums).
  - Aceite: CA0-5.

- [x] **T0.6 Dados semente (JSON + validador)** — G2 — 45 exercícios, programa ABC, 32 testes (2026-09-22)
  - Escopo: `PersonalTrainer/Resources/Seed/exercises.v1.json`, `Resources/Seed/program-default.v1.json`, `Sources/TrainerCore/Domain/SeedBundle.swift`, `Domain/SeedValidator.swift`, `Tests/.../SeedBundleTests.swift`.
  - Feito: `SeedExerciseCatalog`, `SeedProgramFile`, `SeedBundle.decode`, `SeedValidator` (slugs/ids únicos, ids do programa existem, faixas, RIR, descanso, incremento > 0, um programa ativo, `order` único). Os testes leem os JSON reais via `#filePath` (sem cópia de fixtures, sem mudar `Package.swift`).
  - Aceite: ✔. O `SeedLoader` que grava no SwiftData é T1.10.

- [x] **T0.7 DTOs de sync** — G2 — 20 testes, formato de fio travado por golden test (2026-09-22)
  - Escopo: `Sources/TrainerCore/Sync/{DeviceSource,SessionEvent,ActiveSessionSnapshot,SyncSchema,SyncCodec}.swift`, `Tests/.../SyncDTOTests.swift`.
  - Feito: conforme ARCHITECTURE §7 e §9 (`activeSession` + `nextPlan`, `heartRateSummary(averageBPM:maxBPM:hkWorkoutUUID:)`); `SyncCodec` rejeita `schemaVersion > currentVersion` e mapeia `DecodingError` para `SyncError.corrupted`.
  - Aceite: CA0-7 ✔.

- [x] **T0.8 [CI] Protocolos de serviços externos + Fakes** — G2 — compilado e testado no simulador (2026-09-23)
  - Escopo: `PersonalTrainer/Services/HealthKit/{HeartRateSummary,HealthKitServicing,HealthKitServiceError,FakeHealthKitService}.swift`, `Services/WatchSync/{WatchSyncServicing,NoopWatchSyncService}.swift`, `Services/Notifications/{NotificationScheduling,FakeNotificationScheduler}.swift`, `PersonalTrainerTests/Services/FakeServicesTests.swift`.
  - Feito: só protocolos, tipos de valor e fakes (estado em `actor` interno; sem `@MainActor`). Nenhum `import HealthKit` real — `LiveHealthKitService` é T2.1.
  - Aceite: compila no CI; fakes usáveis em previews.

- [x] **T0.9 [CI] Mappers SwiftData ↔ TrainerCore** — G3 — testes verdes no simulador (2026-09-23)
  - Escopo: `PersonalTrainer/Persistence/Mappers/{MappingError,ExerciseMapper,ProgramMapper,HistoryMapper,SessionSummaryMapper}.swift`, `PersonalTrainerTests/Persistence/MapperTests.swift`.
  - Feito: `ExerciseModel ⇄ ExerciseDefinition`, `ProgramModel → ProgramTemplate`, `[SessionExerciseModel] → [ExerciseHistoryEntry]`, `WorkoutSessionModel → SessionSummary` (grupo conta só com ≥ 1 série de trabalho). Falta o inverso `ProgramTemplate → ProgramModel`, que T1.10 adiciona.
  - Aceite: testes em container in-memory no CI.

- [x] **T0.10 Verificação de fronteira** — G3 — `Scripts/check-boundaries.sh` (R1–R3) roda no CI Linux e no build macOS; `Scripts/swift-test.ps1` substitui o `test-core.sh` previsto (Windows). CA0-6 ✔.

---

## M1 — MVP utilizável na academia (iPhone)

**Objetivo:** usar de verdade no próximo treino. Programa vem do JSON semente. Sem HealthKit, sem Watch, sem edição, sem export.

**Critérios de aceitação M1**

| CA | Verificação | Estado |
|----|-------------|--------|
| CA1-1 | Instalação limpa → Home mostra "Dia A" com todos os exercícios do JSON, cada um com "S × min–max · carga ou '—' · RIR T · descanso". | ✔ código + `HomeViewModelTests`/`SeedLoaderTests` no CI; confirmar visual no aparelho (T1.12) |
| CA1-2 | Tocar **Iniciar** → tela de sessão; a primeira série do primeiro exercício vem pré-preenchida com a prescrição. | ✔ `ActiveSessionViewModelTests`; confirmar no aparelho |
| CA1-3 | **Concluir série** persiste em < 100 ms perceptível e inicia o timer com o `restSeconds` do exercício; o timer dispara notificação local com o app em segundo plano. | persistência ✔ (`SessionCoordinatorTests`), timer ✔ (`RestTimerTests`); notificação em segundo plano só no aparelho |
| CA1-4 | Matar o app no meio da sessão e reabrir → Home mostra **Retomar**; todas as séries concluídas estão lá. | lógica ✔ (`activeSession` + Retomar); confirmar no aparelho |
| CA1-5 | **Finalizar** → Home mostra "Dia B". Voltar a treinar A depois de B e C → as cargas de A refletem P4/P5/P6 conforme os registros (teste de integração T1.11 + verificação manual com um exercício). | ✔ `FullLoopTests` (P4, P5, P6) verde no simulador |
| CA1-6 | Pular exercício → aparece como pulado no histórico; não afeta a prescrição futura desse exercício (P7 com 0 séries). | ✔ `FullLoopTests.testCA16…` |
| CA1-7 | Histórico lista sessões por data com dia, duração e nº de séries; detalhe mostra cada série (carga × reps @ RIR). | ✔ `HistoryTests`; confirmar visual no aparelho |
| CA1-8 | Toda a Home e a sessão ativa funcionam em modo avião. | por construção (nenhuma chamada de rede); confirmar no aparelho |
| CA1-9 | Nenhuma View chama `modelContext.insert/delete` (grep em `Features/` retorna vazio). | ✔ |

**M1: código completo e verde no CI em 2026-09-23** (run 35913991560: 310 s de testes no simulador, IPA de 1,2 MB). Faltam só as confirmações que exigem o aparelho (T1.12), que dependem de T0.0 V3.

### Tarefas M1

- [x] **T1.1 [CI] AppEnvironment, injeção e navegação raiz** — G1 — run "App build (manual)" 35913991560 verde (2026-09-23)
  - Escopo: `PersonalTrainer/App/AppEnvironment.swift`, `App/RootView.swift`, `App/PersonalTrainerApp.swift` (substituir placeholder).
  - Fazer: `AppEnvironment` (`@Observable`, `@MainActor`) segurando container, `SessionCoordinator`, `SessionPlanner`, serviços (fakes por padrão em DEBUG/simulador); `TabView` Home · Histórico; `.modelContainer`.
  - Depende de: T0.5, T0.8. Interfaces de `SessionCoordinator`/`SessionPlanner` são definidas aqui como protocolos vazios para que T1.2/T1.3 preencham em paralelo.
  - Aceite: app abre em duas abas vazias.

- [x] **T1.2 [CI] SessionPlanner** — G2 — verde no CI (2026-09-23)
  - Escopo: `Services/Planning/SessionPlanner.swift`, `PersonalTrainerTests/Services/SessionPlannerTests.swift`.
  - Fazer: `nextPlan() -> SessionPlan` (DTO: dia + prescrições, sem gravar) e `startSession(from plan) -> UUID` (cria `WorkoutSessionModel` com snapshots via evento `sessionStarted`). Usa `RotationSelector` + `DoubleProgressionRule` + mappers. Recusa iniciar se já há `inProgress`.
  - Depende de: T0.3, T0.4, T0.9, T1.1.
  - Aceite: teste: seed in-memory → `nextPlan()` retorna Dia A com cargas `nil`/`startingLoad`.

- [x] **T1.3 [CI] SessionCoordinator** — G2 — verde no CI (2026-09-23)
  - Escopo: `Services/Session/SessionCoordinator.swift`, `Services/Session/AppliedEventStore.swift`, `PersonalTrainerTests/Services/SessionCoordinatorTests.swift`.
  - Fazer: `apply(_:)` para todos os `SessionEvent.Kind` (M1 usa `sessionStarted`, `setLogged`, `exerciseSkipped`, `sessionFinished`, `sessionAbandoned`; os demais implementados mas sem UI); `save()` imediato; dedup por `event.id`; `AsyncStream<SessionEvent>` `eventsApplied`; `activeSession() -> WorkoutSessionModel?`.
  - Depende de: T0.5, T0.7, T1.1.
  - Aceite: teste por `Kind`; teste de idempotência; teste de que `setLogged` está no disco após `apply` (reabrir contexto).

- [x] **T1.4 [CI] Tela Home** — G3 — verde no CI (2026-09-23); callback chama-se `onOpenSession`
  - Escopo: `Features/Home/HomeView.swift`, `Features/Home/HomeViewModel.swift`, `Features/Home/PrescriptionRow.swift`.
  - Fazer: card "Próximo treino: <dia>", lista de `PrescriptionRow`, botão Iniciar/Retomar. Formatação pt-BR ("60 kg", "3 × 8–12", "RIR 2", "2 min"). A Home **não** conhece `ActiveSessionView`: expõe `onStart(sessionID)` e quem liga Home → Sessão é `RootView` (T1.8), evitando dependência com T1.5 dentro do mesmo grupo paralelo.
  - Depende de: T1.2, T1.3.
  - Aceite: CA1-1, CA1-2 (navegação).

- [x] **T1.5 [CI] Tela de sessão ativa (estrutura)** — G3 — verde no CI (2026-09-23)
  - Escopo: `Features/Session/ActiveSessionView.swift`, `Features/Session/ActiveSessionViewModel.swift`, `Features/Session/ExerciseProgressList.swift`.
  - Fazer: ViewModel mantém estado em memória da sessão (não `@Query`), lista de exercícios com progresso "2/3", exercício atual destacado, botões Pular / Finalizar (com confirmação). Delega registro de série ao componente T1.6 via closure e ao coordinator via evento.
  - Depende de: T1.3. Pode rodar em paralelo com T1.4 e T1.6 usando dados de preview.
  - Aceite: CA1-4, CA1-6 (fluxo), CA1-9.

- [x] **T1.6 [CI] Componente de registro de série** — G3 — verde no CI (2026-09-23); `onComplete: () -> Void`
  - Escopo: `Features/Session/SetEntryView.swift`, `Features/Session/LoadStepper.swift`, `Features/Session/RIRPicker.swift`.
  - Fazer: view pura (entrada: `SetDraft`; saída: `onComplete(SetDraft)`), steppers grandes de carga (passo = `loadIncrement`, toque longo acelera) e reps, seletor RIR 0–5 em segmentos, toggle aquecimento, botão **Concluir série** ≥ 56 pt. Sem acesso a coordinator/SwiftData.
  - Depende de: T0.2 apenas. Totalmente paralelizável.
  - Aceite: previews com Dynamic Type XXL sem quebra; RNF-06.

- [x] **T1.7 [CI] Timer de descanso** — G3 — verde no CI (2026-09-23)
  - Escopo: `Services/RestTimer/RestTimer.swift`, `Features/Session/RestTimerView.swift`, `Services/Notifications/LiveNotificationScheduler.swift`.
  - Fazer: `RestTimer` `@Observable` baseado em `endDate`; agenda `UNNotificationRequest` ao iniciar, cancela ao pular; haptic ao zerar em primeiro plano; view compacta (anel + "1:32" + botões +30 s / Pular). Pedir permissão de notificação na primeira vez.
  - Depende de: T0.8 (protocolo). Totalmente paralelizável.
  - Aceite: CA1-3 (parte timer); timer correto após app em background por 2 min.

- [x] **T1.8 [CI] Finalizar sessão + resumo** — G4 — verde no CI (2026-09-23)
  - Escopo: `Features/Session/SessionSummaryView.swift`, `Features/Session/ActiveSessionViewModel+Finish.swift`.
  - Fazer: emitir `sessionFinished`, mostrar resumo (duração, séries de trabalho, exercícios pulados), botão Fechar → Home recalcula.
  - Depende de: T1.5.
  - Aceite: CA1-5 (fluxo).

- [x] **T1.9 [CI] Histórico (lista + detalhe)** — G3 — verde no CI (2026-09-23)
  - Escopo: `Features/History/HistoryListView.swift`, `Features/History/SessionDetailView.swift`.
  - Fazer: `@Query` de `WorkoutSessionModel` ordenado por `startedAt` desc; linha com dia, data, duração, nº séries; detalhe com exercícios e séries "60 kg × 10 @ RIR 2", pulados marcados.
  - Depende de: T0.5. Paralelizável com toda a G3.
  - Aceite: CA1-7.

- [x] **T1.10 [CI] SeedLoader no primeiro launch** — G2 — verde no CI (2026-09-23)
  - Escopo: `Services/Seed/SeedLoader.swift`, `Persistence/Mappers/ProgramMapper.swift` (adicionar `ProgramTemplate → ProgramModel` com lookup `[UUID: ExerciseModel]`), `PersonalTrainerTests/Services/SeedLoaderTests.swift`.
  - Fazer: ler JSONs do bundle (`SeedBundle.decode` + `SeedValidator.validate`), upsert de exercícios por `slug` preservando edições do usuário, inserir o programa ativo se não existir, criar `UserSettingsModel`, gravar `schemaSeedVersion`; idempotente. O `project.yml` já inclui `PersonalTrainer/Resources/**` como recursos do target.
  - Depende de: T0.5, T0.6, T0.9.
  - Aceite: rodar duas vezes não duplica; teste in-memory.

- [x] **T1.11 [CI] Teste de integração do loop completo** — G4 — `FullLoopTests` (P4, P5, P6, sessão dupla, exercício pulado) verde no simulador (2026-09-23)
  - Escopo: `PersonalTrainerTests/Integration/FullLoopTests.swift`.
  - Fazer: seed → plano A → iniciar → registrar 3×12 em um exercício com `startingLoad` 40 → finalizar → plano B → … → plano A de novo → afirmar carga 42,5 e nota `increase`; variante de falha dupla → `decrease`.
  - Depende de: T1.2, T1.3, T1.10.
  - Aceite: CA1-5.

- [x] **T1.12 [CI] Instalar no iPhone e treinar uma vez** — G5 (o dono instala pelo Impactor e treina com o app desde a 2.1)
  - Escopo: nenhum arquivo; anotar achados em `TASKS.md` seção "Achados de campo".
  - Depende de: tudo de M1.
  - Aceite: CA1-1 a CA1-9 marcados manualmente.

### Achados da revisão do M1 (2026-09-23) — decisões pendentes do arquiteto

- **Meta de reps não chega à tela (SPEC P5).** `SessionExerciseModel` não guarda `ExercisePrescription.targetReps`; a 1ª série pré-preenche `repMin` mesmo em `hold`. Correção exige **SchemaV2** (`prescribedTargetReps`) + coordinator copiando o valor + `makeDraft`. Vira tarefa `[SCHEMA]` em M2 (T2.11).
- **Calibração começa em 0 kg** (seed sem `startingLoad`): "Concluir série" fica habilitado com 0 kg. Decidir: bloquear quando `prescribedLoad == nil && load == 0` (exceto `bodyweight`) ou pedir a carga explicitamente. Candidata a T2.8b.
- **Sem "voltar" com sessão ativa.** Da sessão só se sai finalizando ou abandonando; "Retomar" hoje só ocorre ao relançar o app. Decidir se M2 ganha um botão "Voltar" que mantém a sessão `inProgress`.
- **Store persistente falhou → cai em memória em silêncio** (logado). Decidir se M2 mostra aviso "dados não estão sendo salvos".
- **Duas linhas iguais de prescrição** (`CurrentExercisePanel` e `SetEntryView`) após a correção C2; polimento de layout.
- **A confirmar no CI:** `SeedLoader` insere o grafo do programa pela raiz (ProgramMapper monta relações antes do insert); `TEST_HOST` do bundle de testes precisa ser o app para `Bundle.main` conter os JSON do seed.

---

## M2 — Robustez, HealthKit, edição e backup

**Objetivo:** app que dá para viver com por meses sem reinstalar: FC e treino no Saúde, editar programa/catálogo no app, backup.

**Estado em 2026-09-23:** as 12 partes do M2 foram mescladas, revisadas por 4 lentes adversariais e corrigidas (eab3e3b). Core tests verde (run 35945595815). **App build verde na primeira tentativa** (run 35945596092, branch `ci/app-check`, commit 29e19c5): compilação, testes no simulador e IPA. Os CAs que dependem do aparelho (HealthKit real, migração do store da M1) ficam para a instalação. Rodada final: `docs/V2-FINAL-CONTRACT.md`.

**Critérios de aceitação M2**

| CA | Verificação |
|----|-------------|
| CA2-1 | Finalizar sessão no aparelho → app Saúde mostra 1 treino "Treinamento de Força" com início/fim corretos; finalizar de novo (reabrir e refinalizar) não cria segundo. |
| CA2-2 | Com Watch no pulso (sem app do Watch), detalhe da sessão mostra FC média/máx; sem Watch mostra "FC indisponível" sem erro. |
| CA2-3 | Substituir exercício na sessão → série registrada aparece no histórico do exercício novo; o exercício original não recebe histórico. |
| CA2-4 | Editar `repMax` de um exercício do programa → próxima prescrição usa o novo valor; sessões antigas mantêm o snapshot. |
| CA2-5 | Exportar JSON → apagar app → reinstalar → importar → Home mostra a mesma prescrição que antes e contagem de sessões idêntica. |
| CA2-6 | Painel semanal mostra "Peito 1/2" após uma sessão de Dia A na semana. |
| CA2-7 | Exercício sem treino há 22 dias recebe nota `returning` e carga 0,9·L (teste P9). |
| CA2-8 | Editar/excluir uma série em sessão em andamento reflete no resumo e no histórico. |

### Tarefas M2

- [~] **T2.1 [CI] LiveHealthKitService — gravar ou vincular HKWorkout** — G1 — Escopo: `Services/HealthKit/LiveHealthKitService.swift`, `Services/HealthKit/HealthKitWorkoutRecorder.swift` (reage a `sessionFinished` via `eventsApplied`, checa `hkWorkoutUUID == nil`, procura treino de força de outro app sobrepondo ≥ 50 % do intervalo e **vincula** se existir, senão grava; emite `heartRateSummary` com o UUID), `HealthKitServicing` ganha `findOverlappingStrengthWorkout(start:end:)` (+ fake). Depende de: T0.8, T1.3. Aceite: CA2-1 e SPEC RF-13.
- [~] **T2.2 [CI] Leitura de FC pós-sessão** — G1 — Escopo: `LiveHealthKitService+HeartRate.swift`, `Features/History/HeartRateSection.swift`. `HKStatisticsQuery` avg/max no intervalo. Depende de: T2.1. Aceite: CA2-2.
- [x] **T2.3 Cálculo de resumo em TrainerCore** — G1 — `Summary/SessionStats.swift`, `Summary/WeeklyFrequency.swift`, 39 testes (2026-09-22). `weekEnd` é exclusivo: a UI (T2.7) exibe `weekEnd − 1 dia`.
- [~] **T2.4 [CI] Backup export/import** — G1 — Escopo: `Services/Backup/BackupDocument.swift`, `BackupService.swift`, `Features/Settings/BackupView.swift`, testes de round-trip in-memory. Depende de: T0.9, T1.3. Aceite: CA2-5.
- [~] **T2.5 [CI] Edição de catálogo** — G2 — Escopo: `Features/Catalog/*`, `Persistence/Repositories/CatalogRepository.swift`. Depende de: T0.5. Aceite: RF-15.
- [~] **T2.6 [CI] Edição de programa** — G2 — Escopo: `Features/Program/*`, `Persistence/Repositories/ProgramRepository.swift`. Depende de: T0.5, T2.5 (picker de exercício). Aceite: CA2-4.
- [~] **T2.7 [CI] Painel de frequência semanal** — G2 — Escopo: `Features/Home/WeeklyFrequencyCard.swift`, `Features/Settings/WeeklyTargetsView.swift`. Depende de: T2.3. Aceite: CA2-6.
- [x] **T2.8 Regra P9 (retorno após pausa)** — G1 — entregue dentro de T0.3 (2026-09-22). CA2-7 coberto por teste de tabela.
- [~] **T2.11 [SCHEMA][CI] SchemaV2: objetivo do programa e meta de reps no snapshot** — Escopo: `Persistence/Schema/SchemaV2.swift`, `MigrationPlan.swift` (estágio leve V1→V2), `Domain/ProgramGoal.swift` (TrainerCore: `hypertrophy`, `strength`, `endurance` + tabela de padrões da SPEC §7.9), `ProgramModel.goalRaw` (padrão `hypertrophy`), `SessionExerciseModel.prescribedTargetReps` (copiado pelo coordinator; `makeDraft` passa a usar). Testes: migração abre store V1 de fixture; draft da 1ª série usa `targetReps` em `hold`. Resolve o achado "meta de reps não chega à tela".
- [~] **T2.13 [CI] Apagar sessão do histórico** (pedido do usuário, 2026-09-23) — swipe "Apagar" com confirmação em `HistoryListView`; exclusão via `SessionCoordinating` (novo método `deleteSession(id:)`, não pela View, R4); o motor recalcula por derivação do histórico (ADR 003). Teste: apagar a última sessão de A devolve a prescrição anterior.
- [~] **T2.14 [CI] Escolher o dia A/B/C manualmente na Home** (pedido do usuário) — menu no nome do dia usando `SessionPlanning.plan(forDayID:)` (S4 já implementada); a rotação segue do dia escolhido.
- [x] **T2.15 Programa padrão com 5 exercícios por dia** (pedido do usuário, 2026-09-23) — seed reduzido (sai voador, leg press e rosca martelo); testes ajustados. Instalações existentes mantêm o programa antigo até a edição de programa (T2.6) ou reset.
- [~] **T2.16 Objetivo Longevidade (SPEC §7.9)** — `ProgramGoal.longevity` com os padrões da tabela, metas de equilíbrio, mobilidade, passos e sono; blocos opcionais "feito/não feito" no fim do treino (M5 lê passos/aeróbico/sono do HealthKit). Depende de T2.11.
- [~] **T2.17 Objetivo Combate (SPEC §7.9)** — `ProgramGoal.combat`, programa semente de combate (força máxima + potência + pegada/tronco), exercícios novos no catálogo (arremesso de medicine ball, kettlebell swing, farmer's walk, pallof, isometria de pescoço), bloco de intervalos tipo round; aviso único "o app não ensina técnica". Depende de T2.11.
- [~] **T2.18 Catálogo de referências e "Por quê?" (RF-32)** — `Resources/Seed/references.v1.json` (id, autores, ano, título, revista, DOI, nível: diretriz/meta-análise/estudo), `Domain/ScientificReference.swift` + validador (toda regra citada existe; DOI bem formado) em TrainerCore; `Features/References/WhySheet.swift` aberta pelas notas de prescrição e metas. Teste: cada regra P/S/R/A e cada objetivo tem ≥ 1 referência.
- [~] **T2.19 Padrão de movimento e substitutos (RF-34)** — catálogo ganha `movementPattern` (ex.: `horizontalPush`, `verticalPull`, `squat`, `hinge`, `lunge`, `carry`...) e `equipment`; `Domain/ExerciseSubstitution.swift` ranqueia substitutos (mesmo padrão + mesmo grupo primário, depois equipamento parecido); catálogo ampliado para ter ≥ 3 opções por padrão. Botão "Trocar" usa o evento `exerciseSubstituted` já existente. Testes de tabela.
- [~] **T2.20 Adicionar/remover exercícios (RF-33)** — parte de T2.6 (edição de programa): limites 1–10 por dia.
- [~] **T2.21 Formatos de hipertrofia (RF-35)** — três programas semente: completo, foco inferior, foco superior; escolha junto com o objetivo.
- [x] **T2.22 [CI] Dias do programa: adicionar, remover, renomear, reordenar (RF-36)** (conferido no código em 2026-10-05: `ProgramDetailView` e `ProgramRepositoring`; desde a 2.4, apagar o dia da última sessão faz S2 seguir a sessão anterior num dia que existe) (pedido do usuário, 2026-09-23) — `ProgramRepositoring` ganha `addDay(programID:name:) -> UUID` (novo dia com o próximo rótulo livre: A, B, C, D, E…), `removeDay(id:)` (mínimo 1 dia; se era o dia da última sessão, S2 recomeça em D1), `renameDay(id:to:)`, `moveDay(id:toIndex:)` (renumera `order`); limites 1–7 dias; UI no `ProgramDetailView`. Rodada seguinte à integração do M2 (os agentes atuais já estavam em execução quando o pedido chegou).
- [~] **T2.12 [CI] Escolha do objetivo na edição de programa** — Escopo: `Features/Program/GoalPicker.swift`, ajuste em T2.6. Depende de: T2.11.
- [~] **T2.9 [CI] Substituir exercício + editar/excluir série + abandonar** — G2 — Escopo: `Features/Session/ExercisePickerSheet.swift`, `Features/Session/SetEditSheet.swift`, ajustes em `ActiveSessionViewModel`. Eventos já existem (T1.3). Depende de: T1.5, T2.5. Aceite: CA2-3, CA2-8.
- [~] **T2.10 [CI] Resumo enriquecido + gráfico de carga por exercício** — G3 — Escopo: `Features/History/ExerciseProgressChart.swift` (Swift Charts), `SessionSummaryView` com tonelagem e FC. Depende de: T2.2, T2.3.
- [~] **T2.23 [PROJ][CI] Build do app por push e identidade Magister** — Escopo: `.github/workflows/app-build.yml` (gatilho `push` em `ci/**`, concorrência por ref, anotações de erro públicas), `project.yml` (`CFBundleDisplayName: Magister` e textos de uso do Saúde), `Assets.xcassets/AppIcon.appiconset` (ícone final com aparências escura e tingida, DESIGN §2). Aceite: um push em `ci/<nome>` roda o App build; falha de compilação aparece em `/check-runs/<id>/annotations`; o app instalado mostra "Magister" e o ícone novo.

---

## M3 — Apple Watch

**Adiado em 2026-09-23 por decisão do usuário** (o app próprio do relógio fica para outra versão; o Watch continua sendo usado via app Exercício e HealthKit).

**Objetivo:** treinar só com o relógio, iPhone no armário. FC ao vivo. Zero perda ou duplicação de séries.

**Pré-condição (2026-09-22):** M3 só começa depois de T0.0 V3–V5 aprovados no aparelho (instalação do companion pelo Windows, leitura de FC no relógio, renovação semanal). Enquanto isso, a FC vem do app Exercício nativo do Watch via HealthKit (SPEC §7.6, ADR 010) e o app do Watch é opcional. Se V3–V5 falharem, M3 fica suspenso e M4 segue normalmente.

**Critérios de aceitação M3**

| CA | Verificação |
|----|-------------|
| CA3-1 | Iniciar no iPhone → em ≤ 5 s o relógio mostra o mesmo exercício e série atuais. |
| CA3-2 | Iniciar no relógio com iPhone bloqueado no bolso → relógio mostra o próximo treino; ao desbloquear o iPhone, a sessão está lá em andamento. |
| CA3-3 | iPhone em modo avião durante 10 séries registradas no relógio → ao religar, as 10 séries aparecem, uma vez cada, na ordem certa. |
| CA3-4 | Durante a sessão, relógio exibe FC atualizando ≥ 1×/5 s; tela permanece ativa (Always On) por 90 min. |
| CA3-5 | Finalizar pelo relógio → Saúde tem 1 treino (gravado pelo relógio); iPhone não grava outro; detalhe no iPhone mostra FC média/máx. |
| CA3-6 | Registrar a mesma série no relógio e no iPhone (teste forçado) → uma só série no banco (a de `occurredAt` mais recente). |
| CA3-7 | Timer de descanso no relógio vibra ao zerar com a tela apagada. |
| CA3-8 | Toda a lógica de fila/dedup está em `TrainerCore/Sync` com testes sem WCSession. |

### Tarefas M3

- [ ] **T3.1 [PROJ][CI] Configurar WCSession nos dois targets** — G1 — Escopo: `Services/WatchSync/LiveWatchSyncService.swift` (iOS), `PersonalTrainerWatch/Services/PhoneSyncService.swift`, ativação em ambos os `App.swift`. Depende de: T0.7, T0.8. Só configuração e canais; sem UI.
- [ ] **T3.2 Fila e reconciliação em TrainerCore** — G1 — Escopo: `Sources/TrainerCore/Sync/PendingEventQueue.swift`, `Sync/SnapshotReconciler.swift`, testes. Regras da ARCHITECTURE §9. Depende de: T0.7. Sem Mac.
- [ ] **T3.3 [CI] ActiveSessionStore no relógio** — G2 — Escopo: `PersonalTrainerWatch/Services/ActiveSessionStore.swift` (JSON em Application Support, snapshot + fila). Depende de: T3.2.
- [ ] **T3.4 [CI] Snapshot publisher no iPhone** — G2 — Escopo: `Services/WatchSync/SnapshotPublisher.swift` (constrói `ActiveSessionSnapshot` do `WorkoutSessionModel` e do `nextPlan()`, envia em `eventsApplied` e ao calcular a Home). Depende de: T3.1, T1.2, T1.3.
- [ ] **T3.5 [CI] UI do relógio — sessão** — G3 — Escopo: `PersonalTrainerWatch/Features/Session/*` (exercício atual, série atual, Crown para carga/reps, RIR em botões, Concluir). Depende de: T3.3. Emite `SessionEvent` para a fila.
- [ ] **T3.6 [CI] WorkoutManager (HKWorkoutSession + FC ao vivo)** — G3 — Escopo: `PersonalTrainerWatch/Services/WorkoutManager.swift`, `Features/Session/HeartRateView.swift`. Depende de: T3.3. Envia `heartRateSummary(hkWorkoutUUID:)` ao finalizar.
- [ ] **T3.7 [CI] Timer de descanso no relógio** — G3 — Escopo: `PersonalTrainerWatch/Features/Session/WatchRestTimerView.swift` (reusa `RestTimer` se movido para TrainerCore em T3.2, senão cópia mínima), `WKInterfaceDevice.play(.notification)`. Depende de: T3.3.
- [ ] **T3.8 [CI] iPhone: não duplicar HKWorkout quando origem é Watch** — G3 — Escopo: `HealthKitWorkoutRecorder.swift` (ajuste da trava §8). Depende de: T2.1, T3.4. Aceite: CA3-5.
- [ ] **T3.9 [CI] Home do relógio (próximo treino + Iniciar)** — G4 — Escopo: `PersonalTrainerWatch/Features/Home/*`. Depende de: T3.4, T3.5. Aceite: CA3-2.
- [ ] **T3.10 [CI] Teste de campo M3** — G5 — Cenários CA3-1 a CA3-7 no aparelho; achados em "Achados de campo".

---

## M4 — Inteligência de programa e diálogo

**Entra na versão 2 (2026-09-23), junto com M2 e M5.** Inclui o diálogo do app (SPEC §7.11 C1–C8, RF-37..RF-39). Parte de cálculo (TrainerCore) começa em paralelo; telas e integração na rodada final.

**Estado em 2026-09-24:** cálculo (DeloadPolicy, DeloadScheduler com rearme, FrequencyAwareSelector, ProgramReviewer, PersonalRecordDetector, Coach C1–C8) verde no Core tests. App (planejador com semana leve e seletor, diálogo com feed, destaque, revisão aplicável e aviso de expiração) integrado, revisado por 2 lentes adversariais e corrigido. App build verde em `ci/v3-final`. Falta a verificação no aparelho.

### Versão 2.4: atividades fora do app e pendências (pedido do dono, 2026-10-04)

Pedido do dono: "gere a próxima versão já com tudo que está pendente de ser incluído". Contrato `docs/V24-CONTRACT.md`, com a lista completa das pendências e a decisão de cada uma; SPEC decisão 21, RF-53 e §7.17. Worktrees `C:\Users\leona\Developer\pt-wt\w8-<key>`, branches `v8/<key>`, CI em `ci/v8-<key>`.

- [x] **T10.0 Documentos e andaime** (arquiteto): o contrato; na SPEC, RF-01, RF-09, RF-13, RF-16, RF-34, RF-44 (e, j), RF-45, RF-46, RF-47, RF-48, RF-49, RF-52, RF-53 (novo), S2, S6, S8, §7.5, R4, R8, C1, C8, §7.10, §7.14 (F3, F5, F6 e F7), §7.15 (M4, M5, M9), §7.16 (W2, W4), §7.17 (novo) e a decisão 21; DESIGN 1.5; ARCHITECTURE §12 e §17; `docs/design/exercise-guides/batches.json` com os lotes 4 a 7; este TASKS; o andaime (`TrainerCore/Activities`, `FixedActivityDemand`, `RecoveryLoad`, `DeloadTriggerDetail`, os parâmetros novos com padrão, `OutsideActivityStoring` com o Fake, o `ActivitiesModel` e as duas views em esboço).
- [x] **T10.1 [CI] `activities-core`** — X1–X8 testadas; encaixe com fixas (X4); B9 no núcleo; Metas com as atividades (W2.3, W2.6, W4); A1 com a intensidade declarada; referência Ainsworth 2011 e `topic.activities`.
- [x] **T10.2 [CI] `engine`** — S2 pelos dias do programa (A3 da 2.3); S6 com as atividades (X5); blocos do 4 × 4 (F6); semana leve no aeróbico (F5); C1 com números (B11 da 2.1); R8 com segundos e passos; vocabulário "plano" na revisão.
- [x] **T10.3 [CI] `data`** — JSON das atividades (X8), backup, planejador (S6, encaixe, semana leve, medida na revisão, números do C1), "Feito" do C8 como registro (X6), faixa até 300 no repositório (B-2 da 2.1).
- [x] **T10.4 [CI] `healthkit`** — sessão do Cardio como treino aeróbico e vínculo pelo tipo (F5); FC por minuto para o Histórico (F7).
- [x] **T10.5 [CI] `activities-ui`** — registro e fixas (RF-53), "Também hoje", Metas com "Fora do app" e "1 de 2 vezes", Início com os textos da tela Hoje (B8 da 2.3) e Saúde com as atividades.
- [x] **T10.6 [CI] `plans-ui`** — "Também hoje" na tela Hoje, "Atividades fixas" e as fixas em "Sua semana", chaves de "Seus dias" (B9 da 2.3), faixa por medida no editor (B-2 da 2.1).
- [x] **T10.7 [CI] `session`** — carga digitada (A4 da 2.2), cartão aberto (B6 da 2.2), Trocar em casa (B-5 da 2.1), "sem carga" na tela Hoje (B11 da 2.3), progressão dos intervalos (B10 da 2.3, F6), evolução sem carga (A5 da 2.2), sessão vazia fora do Histórico (A7 da 2.2), zonas e VO2máx (F7).
- [x] **T10.8 [CI] `launch`** — halo (A7), ordem das pétalas (B5) e degradê (B6) da abertura (achados da 2.3).
- [x] **T10.9 `guides-4` a `guides-7`** — as 78 guias que faltam, nos lotes 4 a 7 (T6.9 e CA8-8).
- [x] **T10.10 [CI] Integração** — `v8/integration`: as guias juntadas, a raiz, os testes cruzados, a conferência de mensagens, `ci/v8-final`, revisão adversarial e correção. Depois, IPA novo, HANDOFF, a página e o PDF da Amanda e as folhas das guias para o dono. **Feito em 2026-10-05:** revisão com 11 achados (10 corrigidos, B-5 rejeitado), App build 37277483627 e Core tests 37277483632 verdes, merge no `main`; faltam a página e o PDF da Amanda e as folhas para o dono (HANDOFF §5e).

Decisões conservadoras do arquiteto (SPEC decisão 21): a fixa só conta com "Feito"; pilates, ioga e cross ficam fora do aeróbico; com um plano só continua sem encaixe; as atividades ficam fora do painel de músculos; a sessão vazia de "Sair sem registrar" some do Histórico sem ser apagada; o nome "Intervalos 4 × 4" fica; o 4 × 4 vai de 4 a 5 blocos; o dia D fica fora; os intervalos do Combate ficam com a aula de luta registrada; o C11 espera um SchemaV3.

**Critérios de aceitação da 2.4:** CA10-1 a CA10-13, em `docs/V24-CONTRACT.md` §6.

### Versão 2.3: equilibrado, fôlego, carga opcional e "Como fazer" (pedidos do dono, 2026-09-27, depois de usar a 2.2)

Pedidos, na redação do dono, com a tarefa que resolve cada um. As decisões estão na SPEC (decisão 19), e o contrato do núcleo é `docs/V23-CORE-CONTRACT.md`.
- [x] **D1** "O hipertrofia corpo todo é treino de corpo todo todo dia? O correto seria equilibrado, … com as divisões por dia habituais." → formato **Equilibrado**: 4 dias Superior/Inferior, padrão no seed, com o Corpo todo escondido (RF-35, §7.9): **T8.1 `core`**.
- [x] **D2** "O programa de resistência muscular deve mudar, deve ser cardiovascular. Aumentar o fôlego." → objetivo **Fôlego**, cardio simples em minutos, com 10 aeróbicos no catálogo (RF-48, §7.14): **T8.1 `core`**. A parte de tela vai para a onda de telas.
- [x] **Pergunta** "Por que o treino de hipertrofia superior tem 4 dias? É para ter descanso?" → Não é descanso. São 2 dias de superior, para cada grupo em foco treinar 2×/semana, e 2 dias de pernas em manutenção, com menos séries. Agora os três formatos têm 4 dias (RF-35).
- [x] **D3** "Não obrigar colocar carga para poder marcar as séries e o exercício feito; a carga é só se o cara usar carga." → motor em **T8.1 `core`** (P8 D3); a ficha, na onda de telas (RF-44 c, RF-46).
- [x] **D4** Medida `minutes` (RF-43): **T8.1 `core`**.
- [x] **D5** "Você já incluiu os desenhos explicando os exercícios? Se não, inclua já na próxima." → motor e ferramenta em **T8.2 `guide-engine`**; os 62 desenhos em **T8.3** (lotes); a folha e o botão, na onda de telas.
- [x] "Deixe ainda mais simples a interação quando ele aperta Começar", com as informações que recomendam treinos, cargas, exercícios e mudanças → onda de telas (sessão guiada), com contrato próprio.
- [x] Estética mais bonita, "budista, porém estoica", com uma animação elegante de abertura → pesquisa em `docs/design/v23-aesthetics/` e passada estética na onda de telas.

Tarefas do núcleo (contrato `docs/V23-CORE-CONTRACT.md`; worktrees `C:\Users\leona\Developer\pt-wt\w6-<key>`, branches `v6/<key>`):
- [x] **T8.0 Documentos** (arquiteto): contrato do núcleo; na SPEC, RF-04, RF-35, RF-40, RF-43, RF-44 c, RF-45, RF-46, RF-48 (novo), P2/P4/P6/P8, §7.4, §7.5, R8 (novo), §7.9, §7.10, §7.12 (E2, E5–E10), H1/H2, §7.14 (novo) e as decisões 8, 14 e 19; DESIGN §1, §3 e §4 (nome Fôlego); este TASKS.
- [x] **T8.1 [CI] `core`**: carga opcional no motor (P8 D3), `ExerciseMeasure.minutes`, `MovementPattern.cardio`, 10 aeróbicos, os programas Equilibrado e Fôlego (seed 4), "Fôlego" no `ProgramGoal`, no `GoalStyle` e no `GoalPlanCatalog`, R8 na revisão e o texto da R5 (pendência da 2.2).
- [x] **T8.2 `guide-engine`** (= T6.1 + T6.4): `TrainerCore/Guide` com o validador E1–E10, as 4 guias do protótipo (lote 0), a ferramenta de autoria (`-Check`, `-Sheet`, `-Golden`, `-Vocabulary`), a junção dos lotes e o teste de paridade.
- [x] **T8.3 Conteúdo em lotes** (55 guias, uma por exercício dos programas; desenhos aprovados pelo dono em 2026-09-28) (substitui T6.6 e T6.9): lotes 1 a 6 de `docs/V23-CORE-CONTRACT.md` §4, em `v6/guides-N`, depois de T8.4 passo 1.
- [x] **T8.4 Integração do núcleo**: `v6/core` em `v6/guide-engine`, a junção dos lotes e o teste de cobertura ligado. Mesclado no `main` em 2026-09-28 (`f0bcce4`, Core tests 36388566363 e App build 36388568579 verdes), como base da onda de telas.
- [x] **T8.5+ Onda de telas** → virou a seção "Versão 2.3: onda de telas" logo abaixo (T9.x). O HealthKit do Cardio (F5) e a semana leve no cardio ficam para depois dela.

**Critérios de aceitação da 2.3 (núcleo):** CA8-1 a CA8-8, em `docs/V23-CORE-CONTRACT.md` §6.

### Versão 2.3: onda de telas (pedidos do dono, 2026-09-27 e 2026-09-28)

Decisões do dono em `docs/design/v23-owner-notes.md` (itens 1 a 18) e na SPEC (decisão 20); contrato `docs/V23-UI-CONTRACT.md`. Os itens 15 a 18 prevalecem sobre os anteriores.
- [x] **Cardio** "Coração forte e mais condicionamento", com o plano focado no VO2máx: base contínua, 4 × 4, longo e leve (itens 1 e 8; RF-48, §7.14) → **T9.5 `plans-core`** (seed, referências) e **T9.4 `session`** (ficha).
- [x] **Carga opcional com sugestão delicada** (item 2; RF-44 c, RF-46) → **T9.4 `session`**.
- [x] **Abertura** com a flor, amanhecer de areia, pétala do objetivo e pólen discreto; sem vibração (itens 3, 6, 13 e 14; RF-50) → **T9.2 `launch`**.
- [x] **Vários planos** com encaixe, saídas e consequências (itens 4, 9, 10, 11 e 12; RF-51, §7.15, S8) → **T9.5 `plans-core`** e **T9.6 `plans-ui`**.
- [x] **Sem cardio base** nos outros planos (item 7): nada muda.
- [x] **Direção A · Tinta e papel**, só no visual (item 14; DESIGN §3, §14) → **T9.1 `ink`**; desenhos do "Como fazer" aprovados → folha e botões em **T9.4 `session`**.
- [x] **Início** antes do treino do dia, sem mensagem (itens 14 e 15; RF-49) e **Metas da semana** (item 17; RF-52, §7.16) → **T9.3 `home`**.
- [x] **Sem mensagens em nenhum lugar do app** (item 16; decisão 20; DESIGN §6) → regra de todas as tarefas e conferência na **T9.7**.
- [x] **Passos só com Longevidade ou Cardio** (item 18; §7.16 W7) → **T9.3 `home`**.
- [x] "Deixe ainda mais simples a interação quando ele aperta Começar" → sessão guiada (RF-44 i): **T9.4 `session`**.

Tarefas (worktrees `C:\Users\leona\Developer\pt-wt\w7-<key>`, branches `v7/<key>`, CI em `ci/v7-<key>`):
- [x] **T9.0 Documentos e andaime** (arquiteto): contrato `docs/V23-UI-CONTRACT.md`; na SPEC, P-1, F1, RF-01, RF-17, RF-31, RF-44 (c, i), RF-45, RF-47, RF-48, RF-49 a RF-52 (novos), S8, §7.9, §7.10, §7.14 (Cardio VO2máx), §7.15 (M1–M9, novo), §7.16 (W1–W7, novo), §7.7 e as decisões 14, 19 e 20; DESIGN 1.4 (§1, §3, §4, §6, §7, §8, §9, §10, §11, §13 e §14 novo); ARCHITECTURE §17; este TASKS; o andaime (`473345a`, `29d1256`, `cfb6b39`: `TrainerCore/Plans`, requisitos novos do `SessionPlanning` e do `ProgramRepositoring`, DTOs da tela Hoje, stubs do DesignSystem e o nome Cardio).
- [x] **T9.1 [CI] `ink`** — Tinta e papel: tokens, papel, cartões, flor em aguada, ensō, marca de tinta, aguada de montanha, folhas de conferência e a pele de Ajustes, Diálogo e Referências.
- [x] **T9.2 [CI][PROJ] `launch`** — tela de lançamento (`project.yml`, assets) e a abertura com o pólen (RF-50).
- [x] **T9.3 [CI] `home`** — Início (RF-49), Metas da semana (RF-52, W1–W7 no TrainerCore), Histórico sem o painel (RF-17) e passos só com Longevidade ou Cardio no Saúde (W7).
- [x] **T9.4 [CI] `session`** — sessão guiada, carga opcional com a sugestão, Cardio na ficha e na tela Hoje, "Como fazer" (T6.5, T6.7), descanso em ensō.
- [x] **T9.5 [CI] `plans-core`** — `WeeklyFit` (M4, M5), `PlanCombination` (M7), Cardio VO2máx no seed, referências, vários planos no repositório, no backup, no planejador (S8, M6, W2) e no diálogo (C2, C8).
- [x] **T9.6 [CI] `plans-ui`** — folha "Seu objetivo" com Adicionar, aba Plano com a semana e os dias, tela Hoje com as sessões do dia.
- [x] **T9.7 [CI] Integração** — `v7/integration`: aba Início, abertura, guias no ambiente, passos (W7), conferência de mensagens, `ci/v7-final`, revisão adversarial e correção. Depois, IPA novo, HANDOFF e a página e o PDF da Amanda.
- [~] **Para depois da onda:** HealthKit do Cardio e semana leve em minutos (F5); o 4 × 4 que cresce em blocos; o dia D de tiros curtos; zonas de FC no Cardio; registro próprio de equilíbrio e mobilidade (C10). → versão 2.4: T10.2, T10.3, T10.4 e T10.7 (F5, F6, F7) e T10.1/T10.5 (C10, X6). O dia D fica fora (decisão 21).

**Critérios de aceitação da onda de telas:** CA9-1 a CA9-13, em `docs/V23-UI-CONTRACT.md` §6.

### Versão 2.2: simplificação (pedido do dono, 2026-09-27, depois de usar a 2.1 no aparelho)

O app está rodando no iPhone do dono (prints de 2026-09-27: sessão e tela Hoje). Pedidos, na redação dele, com a tarefa do contrato `docs/V22-CONTRACT.md` que resolve cada um (respostas do dono na SPEC, decisão 18):
- [x] **S1** Mudar o subtítulo "Saber se defender" do Combate. → "Potência e resistência" (DESIGN §4): **T7.6 `flower`**.
- [x] **S2** Poder mudar de programa com facilidade. → topo da tela Hoje com "Trocar" (**T7.3 `home`**) e a folha "Seu objetivo" (**T7.4 `goal-plan`**, RF-45).
- [x] **S3** "Objetivo e programa está confuso, devem ser uma coisa só." → objetivo = plano, Hipertrofia com 3 formatos, aba Plano, primeiro uso em um passo: **T7.4 `goal-plan`** (RF-35, RF-45).
- [x] **S4** "Muito complexo, simplifique." Vale para o app inteiro. → tela Hoje enxuta (**T7.3 `home`**, RF-01), ficha da sessão (**T7.1 `session`**), aba Plano (**T7.4**), Ajustes com "Mais opções" (**T7.5 `settings`**), "Esta semana" e Histórico sem RIR (**T7.7 `history`**), vocabulário leigo (DESIGN §7).
- [x] **S5** Avaliar se o RIR é indispensável; se ficar, que seja mais simples. → RIR interno e invisível (RF-41): **T7.1 `session`**, **T7.3 `home`**, **T7.4 `goal-plan`** (editor sem RIR), **T7.7 `history`**; textos do "Por quê?" sem a sigla em **T7.2 `exercise-info`**.
- [x] **S6** Flexão e agachamento são peso do corpo: não mostrar carga. → RF-46, com os textos compartilhados de **T7.2 `exercise-info`** (`TodayTargetText`), usados por **T7.1**, **T7.3** e **T7.7**.
- [x] **S7** Qual a função da chave "Aquecimento"? Esclarecer ou tirar. → a chave sai e vira a dica fixa da ficha (RF-44 d): **T7.1 `session`**.
- [x] **S8** Clicar menos na tela durante o treino. → bolinhas, "Feito", concluir com pendentes e tela acesa (RF-44): **T7.1 `session`**.
- [x] **S9** "Ele quer mais consultar as infos": a sessão como consulta, com o registro mais leve. → ficha (**T7.1 `session`**) e "Informações do exercício" com "Da última vez" (**T7.2 `exercise-info`**, RF-47).
- [x] **S10** Flor/ícone com pétalas com mais movimento, irregularidade, organicidade e vivacidade. Referências enviadas: pinwheel arredondado colorido, asterisco orgânico irregular, espiral de gotas. → candidato 6 · Brisa no ícone (padrão, escuro e tingido) e na `FlowerView`: **T7.6 `flower`** (DESIGN §2, §4).
- Continuam valendo: "Como fazer" (RF-40, T6.1 e T6.4–T6.9) e as pendências da revisão da 2.1 (logo abaixo). A folha de informações (RF-47) é onde o "Como fazer" vai entrar.

Tarefas da versão 2.2 (contrato `docs/V22-CONTRACT.md`; worktrees `C:\Users\leona\Developer\pt-wt\w5-<key>`, branches `v5/<key>`, CI em `ci/v5-<key>`):
- [x] **T7.0 Documentos e andaime** (arquiteto): SPEC (RF-01, RF-03, RF-04, RF-12, RF-16, RF-17, RF-35, RF-39, RF-41, RF-42, RF-44 a RF-47, decisão 18), DESIGN (§2, §4, §7, §8, §9, §13), ARCHITECTURE §17, este TASKS, e o andaime compartilhado (`SessionPlanning.lastSession`, `ExerciseLastSession`, `Features/ExerciseInfo/*`).
- [x] **T7.1 [CI] `session`** — ficha da sessão (RF-44, RF-04, RF-46), resumo "Sessão concluída", tela acesa, paleta da sessão.
- [x] **T7.2 [CI] `exercise-info`** — folha "Informações do exercício" (RF-47), `SessionPlanner.lastSession`, textos das notas no "Por quê?" sem a sigla RIR. (Os testes dela só compilaram na integração: ordem dos argumentos.)
- [x] **T7.3 [CI] `home`** — tela Hoje enxuta (RF-01), topo que troca de objetivo, linhas com a meta de hoje.
- [x] **T7.4 [CI] `goal-plan`** — objetivo = plano (RF-45): folha "Seu objetivo", aba Plano, primeiro uso, editor sem RIR.
- [x] **T7.5 [CI] `settings`** — Ajustes com "Mais opções"; sai "Onde treinar".
- [x] **T7.6 [CI] `flower`** — flor Brisa no ícone e na `FlowerView`; subtítulo do Combate.
- [x] **T7.7 [CI] `history`** — "Esta semana" no Histórico; Histórico sem RIR e com os selos leigos.
- [x] **T7.8 [CI] Integração** — `v5/integration`: RootView (aba Plano, folha "Seu objetivo", parâmetros novos), limpeza do código morto, `ci/v5-final`, revisão adversarial e correção.
- [~] **Pendências da revisão da 2.2** → versão 2.4 (A4, A5, A7 e B6 na T10.7; o texto do ProgramReviewer já foi na T8.1, e o vocabulário que faltava vai na T10.2; A7 com a decisão conservadora de esconder, sem apagar). Texto original (achados menores deixados para depois): a carga digitada antes da 1ª série se perde ao tocar em "Voltar" e retomar (A4: o ViewModel da ficha é recriado); a evolução do exercício (Histórico e "Ver evolução") ainda mostra "0 kg" e 1RM estimado em peso do corpo (A5, RF-46); "Sair sem registrar" grava a sessão vazia como encerrada e ela aparece no Histórico (A7: decisão do dono entre esconder no Histórico ou apagar, com a SPEC); a última série marcada recolhe o cartão e corrigir custa 1 toque a mais que no mockup (B6); o texto da revisão R5 no TrainerCore ainda diz "programa X" (→ T8.1, SPEC R8).

### Versão 2.1 (entregue em 2026-09-24, App build 36037123014) e pendências

- [x] **Modo casa (RF-42, §7.13)**, **medida (RF-43)**, **RIR explicado (RF-41)**, saúde para qualquer relógio (A3/A4), B7 duração estimada, B10 backup direto, A4/B8 dispensa nos dois sentidos, A5 importar limpa decisões — contrato `docs/V21-CONTRACT.md`; revisão adversarial com 8 achados (3 major corrigidos: import de backup 2.0 reaplica o seed, revisão antiga some após importar, equivalente de casa com a mesma medida).
- [~] **Pendências da revisão da 2.1** → versão 2.4: as unidades da aba Plano já estavam feitas, e o limite da faixa por medida vai na T10.3/T10.6; B-3 cancelada (RIR invisível desde a 2.2); B-5 na T10.7; R5 e Epley sem segundos e passos na T10.2/T10.3 (o C6 já filtrava no app); o app do Watch fica com o M3. Texto original: aba Programa sem unidade (s/passos) no resumo e no editor do alvo (B-2); o seletor de RIR mostra só o significado do valor escolhido, e a escala inteira fica no cartão e na folha (B-3, mantido); a folha Trocar vazia em modo casa diz "catálogo" sem explicar que só mostra opções de casa (B-5); a sugestão R5 "outra faixa de repetições" e o 1RM de Epley (R1/C6 no core) não consideram segundos e passos; o app do Watch não mostra a medida.

- [x] **Como fazer (RF-40, SPEC §7.12)**: entregue na 2.3 (T8.2, T8.3 e T9.4); o resto do catálogo vai na 2.4 (T10.9). Estilo aprovado em 2026-09-24 (protótipo v2). Tarefas T6.1 e T6.4–T6.9 na seção "Versão 2.1: Como fazer", logo abaixo.
- [x] **T6.2 [CI] RIR explicado na sessão (RF-41)** — entregue na v2.1 (2026-09-24; seletor 0–5 com o significado do valor escolhido, folha "O que é RIR?", cartão da primeira sessão, leitura acessível) — Escopo: `Features/Session/RIRPicker.swift` (rótulos por valor), `Features/Session/RIRExplainerSheet.swift` (nova), cartão de primeira vez em `Features/Session/ActiveSessionView.swift` (marca `hasSeenRIRExplainer` em `@AppStorage`), leitura acessível em `Features/Home/PrescriptionRow.swift`. Aceite: os 4 itens do RF-41 visíveis no simulador, e o cartão some depois de "Entendi" e não volta.
- [x] **T6.3 Exercícios medidos em tempo ou passos (RF-43)** — entregue na v2.1 SEM SchemaV3: a medida vem do catálogo do seed pelo slug (texto original a seguir) (achado de 2026-09-24): isometrias (pescoço, prancha) e carregadas aparecem como "10–20 repetições", quando são segundos ou passos. Acrescentar ao exercício a medida (`reps` | `seconds` | `steps`), com SchemaV3 e estágio de migração (R6), seed e rótulos na sessão, no histórico e na prescrição. A progressão (P4–P6) passa a usar a mesma lógica sobre a medida.
- [x] **A5** (feito na v2.1: importar apaga as decisões de semana leve, a revisão guardada e a chave pendente; o log do diálogo fica) Importar backup mantinha decisões de semana leve, o log e a revisão do diálogo tomados sobre os dados antigos; esses JSON também não entram no backup. Decidir o que o import zera.
- [x] **B7** (feito na v2.1) Duração estimada no cartão da sessão (DESIGN §9.2).
- [x] **B10** (feito na v2.1) "Fazer backup" (C7) deveria abrir a exportação direto, não só a aba Ajustes.
- [~] **B11** → versão 2.4 (T10.2, T10.3). Motivo do C1 com os números do gatilho (quantos exercícios baixaram; N semanas): exige campos no `CoachDeloadState`.
- [x] **A4/B8** (feito na v2.1) Dispensar uma sugestão de saúde no feed deveria escondê-la também no detalhe de Saúde (hoje só o sentido inverso funciona).
- [x] Programas Foco inferior e Foco superior: revisar para 2×/semana no grupo em foco e alinhar os descansos ao §7.9 (150/90 s). Conferido no seed 4 em 2026-10-05: 4 dias, cada grupo em foco 2×/semana e descansos de 150/90 s.
- [~] C10 (corretor do M2) → versão 2.4: equilíbrio e mobilidade ganham registro próprio pelas atividades fora do app (SPEC §7.17 X6; T10.1, T10.3, T10.5); os intervalos do Combate ficam com a "Aula de luta" registrada (decisão 21). Texto original: blocos de intervalos do Combate e de equilíbrio/mobilidade com registro próprio; hoje são lembretes C8.
- [ ] C11 (corretor do M2): marcar exercício do seed editado pelo usuário (SchemaV3) antes de qualquer seed v3. Continua pendente na 2.4: sem SchemaV3 nem seed novo (decisão 21).

### Versão 2.1: Como fazer (RF-40, SPEC §7.12)

Decisões do dono (2026-09-24):
- estilo da v2 do protótipo aprovado (`docs/design/exercise-guides/compare-v2.png`);
- o agente rascunha poses e textos, e o dono revisa por lote;
- exceção de equipamento só dentro da folha (DESIGN §12).

Pesquisa e alternativas descartadas: `docs/design/exercise-guides/PROPOSAL.md`.

| CA | Verificação |
|----|-------------|
| CA6-1 | Core tests verdes, com ao menos um teste por regra E1–E9 e o teste de paridade com o renderizador de autoria (T6.4). |
| CA6-2 | Todo exercício usado em `programs.v2.json` e todo aeróbico do catálogo tem guia válida; o teste lê os dois arquivos. Na 2.3 são 62 (`docs/V23-CORE-CONTRACT.md` §4). O resto do catálogo fica para depois. |
| CA6-3 | No aparelho, "Como fazer" aparece na sessão, na Home e no catálogo para um exercício com guia, e não aparece para um personalizado. Um exercício trocado mostra a guia do substituto. |
| CA6-4 | Em modo avião, a folha abre e anima. O app cresce menos de 1 MB, e nenhum arquivo de imagem é adicionado para as guias. |
| CA6-5 | Com Reduzir Movimento, as posições ficam paradas lado a lado. Pausar para a animação. O VoiceOver lê a descrição, os passos e os erros, nessa ordem. |
| CA6-6 | No modo escuro e com Aumentar Contraste, figura, seta e implemento continuam legíveis (DESIGN §3 e §12). |
| CA6-7 | O dono aprovou a folha de revisão de cada lote (anotar a data aqui). |

- [~] **T6.1 Guias de execução em TrainerCore (§7.12 E1–E10)** — G1 — na 2.3, faz parte da **T8.2 `guide-engine`** (`v6/guide-engine`), com o formato congelado em `docs/V23-CORE-CONTRACT.md` §2.5–§2.6
  - Escopo:
    - `Packages/TrainerCore/Sources/TrainerCore/Guide/*` (catálogo, guia, quadro, pose, rig, cinemática com o modo antebraço travado, partes que se movem, tempo, validador, erros);
    - `ExerciseGuideTests.swift` e `GuideKinematicsTests.swift`, que leem os arquivos reais por `#filePath`;
    - `PersonalTrainer/Resources/Seed/exercise-guides.v1.json` com as 4 guias do protótipo v2;
    - ARCHITECTURE §11 (formato) e §17 (pastas `Guide/`, `Features/ExerciseGuide/`, `Services/ExerciseGuides/`).
  - Base: o formato de `docs/design/exercise-guides/exercise-guides.sample.json`.
  - Só Foundation. A pose é função de `t`, sem `Date()`.
  - O JSON entra no bundle sem tarefa [PROJ], porque o `project.yml` já inclui `PersonalTrainer/` inteiro.
  - Aceite: CA6-1 parcial (E1–E9) e 4 guias válidas.
- [~] **T6.4 Ferramenta de autoria no Windows** — G2 — na 2.3, faz parte da **T8.2 `guide-engine`** (`docs/V23-CORE-CONTRACT.md` §2.7)
  - Escopo:
    - promover `docs/design/exercise-guides/render-exercise-guides.ps1` para ler `exercise-guides.v1.json` e gerar folhas de revisão por lote, nos modos claro e escuro;
    - opção `-Golden` com as coordenadas em t = 0, ¼, ½, ¾ e 1, gravadas em `Tests/TrainerCoreTests/Fixtures/exercise-guides-golden.v1.json`;
    - `GuideGoldenTests.swift`: o Swift e o script concordam em até 0,001 H. Isso protege contra os dois renderizadores divergirem, já que o Swift não roda localmente.
  - Depende de: T6.1. Aceite: CA6-1 completo.
- [x] **T6.5 [CI] Ilustração e folha "Como fazer"** — G2 (entregue na 2.3, T9.4)
  - Escopo em `Features/ExerciseGuide/`:
    - `GuideIllustrationView.swift`: `TimelineView(.animation(minimumInterval: 1.0 / 30, paused:))` + `Canvas`, com um único `accessibilityLabel`;
    - `GuideStaticFramesView.swift`: modo Reduzir Movimento;
    - `ExerciseGuideSheet.swift`: título em New York, "Trabalha: …", ilustração, Pausar/Continuar ≥ 44 pt, legendas, passos e erros;
    - `ExerciseGuideButton.swift`.
  - Previews com as 4 guias; só APIs do iOS 15 ou posterior.
  - Depende de: T6.1. Aceite: App build verde e lista Verificado/Incerto (R11).
- [-] **T6.6 Conteúdo, lote 1: os 54 exercícios dos programas** — G3 — substituída na 2.3 pela **T8.3** (lotes 1 a 6 com 58 guias, mais as 4 do lote 0; `docs/V23-CORE-CONTRACT.md` §4)
  - Escopo: `exercise-guides.v1.json`, as folhas `docs/design/exercise-guides/sheet-1*.png` e o teste de cobertura dos slugs de `programs.v2.json`.
  - Fáceis e médios primeiro. Os difíceis (cadeira abdutora, Pallof, salto na caixa, arremesso rotacional) podem sair como `motion: "static"`, com setas.
  - Não usar o campo `equipment` para decidir a cena: os 6 exercícios de medicine ball estão como `dumbbell`.
  - Depende de: T6.1 e T6.4. Aceite: CA6-2 (54) e folha pronta para o dono.
- [x] **T6.7 [CI] "Como fazer" no app** — G3 (entregue na 2.3, T9.4)
  - Escopo:
    - `Services/ExerciseGuides/ExerciseGuideLibrary.swift`: lê o bundle, valida e devolve `.empty` em caso de falha (E8);
    - injeção em `App/AppEnvironment*.swift`;
    - botão em `Features/Session/CurrentExercisePanel.swift` (slug do exercício realizado), `Features/Home/PrescriptionRow.swift` e na tela do exercício no catálogo.
  - Depende de: T6.5 e T6.2. Não rodar em paralelo com a T6.2, porque as duas editam `PrescriptionRow.swift`.
  - Aceite: CA6-3 a CA6-6 no simulador.
- [ ] **T6.8 [USER] Revisão do lote 1 e teste no aparelho** — G4 — O dono olha a folha e o app e anota as correções por exercício; o agente corrige no escopo da T6.6. Aceite: CA6-7 (lote 1) e CA6-3 a CA6-6 no iPhone.
- [~] **T6.9 Conteúdo, lote 2: os restantes do catálogo** → versão 2.4, T10.9 (lotes 4 a 7: os 7 aeróbicos que faltavam e os 71 do resto do catálogo, 133 no total) — G5 — depois da 2.3, os que não estão nos programas nem são aeróbicos
  - Escopo: `exercise-guides.v1.json`, as folhas `sheet-2*.png` e a cobertura dos 99.
  - Difíceis previstos: voador, crucifixo inverso na máquina, abdominal na máquina, power clean suspenso, salto horizontal, arremesso para trás e extensão de pescoço na polia.
  - Depende de: T6.8. Aceite: CA6-2 (99) e CA6-7 (lote 2).

- [~] **T4.8 [CI] Diálogo do app (SPEC §7.11)** — `Services/Coach/CoachFeedBuilder.swift` (junta revisão, deload, saúde, validade da instalação, retomada, marcos, backup, longevidade), `Services/Coach/CoachLogStore.swift` (decisões em JSON, cadência/silêncio), `Services/Coach/ProvisioningExpiryReader.swift` (lê ExpirationDate do embedded.mobileprovision; notificação na véspera), `Features/Coach/*` (feed na Home, destaque na abertura, ações).

**Objetivo:** seleção por frequência, deload automático, troca de programa ao fim do mesociclo. Tudo em `TrainerCore` com testes; UI mínima.

**Critérios de aceitação M4**

| CA | Verificação |
|----|-------------|
| CA4-1 | Com Peito 2/2 e Pernas 0/2 na semana, seletor escolhe o dia de pernas mesmo fora da ordem de rotação (teste S5–S7). |
| CA4-2 | Grupo treinado há 30 h exclui o dia candidato; se todos excluídos, cai na rotação (teste S6). |
| CA4-3 | ≥ 50 % dos exercícios com `decrease` → próxima passagem da rotação é deload com séries ⌈0,6·S⌉, carga arredondar↓(0,85·C, inc) sobre a carga C da prescrição normal, RIR 4; a passagem seguinte volta às cargas pré-deload, e as mesmas reduções não disparam um novo deload (rearme, §7.5) (teste). |
| CA4-4 | Após o mesociclo (padrão 8 semanas), a revisão sugere trocar para o próximo programa (§7.11 C2, sempre opcional); ao aceitar, o programa ativo muda e as cargas por exercício são preservadas, porque o histórico é por exercício (teste de integração). Nada troca sozinho (§7.8). |
| CA4-5 | Home exibe um aviso de uma linha explicando a escolha ("Pernas: abaixo da meta semanal" / "Semana de deload"). |

### Tarefas M4

- [~] **T4.1 FrequencyAwareSelector** — Escopo: `Engine/FrequencyAwareSelector.swift` + testes. Depende de: T0.4, T2.3. Sem Mac.
- [~] **T4.2 DeloadPolicy** — Escopo: `Engine/DeloadPolicy.swift`, ajuste em `DoubleProgressionRule` para ignorar entradas `wasDeload` + testes. Depende de: T0.3. Sem Mac.
- [x] **T4.3 Troca de programa por mesociclo** — Entregue como sugestão opcional `switchProgram` em `Review/ProgramReviewer` (§7.11 C2), não como `Engine/ProgramRotationPolicy.swift`: a troca nunca é automática (§7.8). Aplicar a sugestão fica na T4.4. Verde no CI (v2/core-integration).
- [~] **T4.5 Revisão periódica em TrainerCore (SPEC §7.8 R1–R5, R7)** — Escopo: `Sources/TrainerCore/Review/EstimatedOneRepMax.swift`, `Review/ReviewReport.swift`, `Review/ProgramSuggestion.swift`, `Review/ProgramReviewer.swift` + testes de tabela por regra. Entradas: histórico por exercício, `SessionSummary`s, programa, objetivo, `now`. Saída: `ReviewReport` com sinais e `[ProgramSuggestion]` (deload, volume ±, troca de exercício/faixa, frequência), cada uma com regra, motivo e números. `Review/` é módulo separado de `Engine/` (que continua sem qualquer referência a FC, R2). Sem Mac.
- [~] **T4.7 [CI] Tela de sugestões na abertura** — Escopo: `Features/Review/*`, `Services/Review/ReviewScheduler.swift` (a cada `reviewIntervalWeeks`, ou gatilho de deload), aplicação de sugestões aceitas via `ProgramRepository`. Recusar mantém o programa; cada decisão fica registrada. Depende de: T4.5, T2.6. A modulação por recuperação (R6) chega em T5.4.
- [~] **T4.4 [CI] Integrar políticas no SessionPlanner + configurações** — Escopo: `SessionPlanner.swift`, `Features/Settings/ProgramPolicyView.swift`, `Features/Home/PlannerReasonBanner.swift`. Depende de: T4.1–T4.3. Aceite: CA4-5.

---

## M5 — Saúde aeróbica e recuperação (SPEC §7.10)

**Antecipado em 2026-09-23 a pedido do usuário:** construído em paralelo com o M2 e entregue na mesma versão (antes de M3 e M4). Depende do HealthKit funcionar no aparelho com a instalação pelo Impactor (verificado no primeiro treino finalizado).

**Estado em 2026-09-24:** TrainerCore/Health verde no CI. Leitor do HealthKit, cartão e detalhe de Saúde integrados à Home, com App build verde. As sugestões de saúde aparecem no feed do diálogo (C3). Falta a leitura real no aparelho: o simulador não tem HealthKit.

**Objetivo:** o app lê do HealthKit o que o Watch já mede (treinos aeróbicos, FC, VO2max, HRV, FC de repouso, sono) e devolve três coisas: minutos aeróbicos da semana contra a meta, tendência de VO2max e recuperação, e sugestões práticas ("use o Watch à noite", "caminhe 20 min ao ar livre", "faça o aeróbico na quinta, não na véspera de pernas"). Sem IA. Nada aqui grava no HealthKit nem altera a musculação.

**Critérios de aceitação M5**

| CA | Verificação |
|----|-------------|
| CA5-1 | Uma caminhada de 30 min registrada pelo Watch com FC em 70 % da FCmáx aparece como 30 min moderados; uma corrida de 20 min a 85 % aparece como 20 vigorosos = 40 moderados-equivalentes (teste de tabela A1/A2). |
| CA5-2 | Card "Saúde" na Home mostra "Aeróbico: X/150 min" da semana corrente e o último VO2max com a faixa por idade/sexo. |
| CA5-3 | Sem HRV/sono em 5 dos últimos 7 dias → sugestão "Use o Apple Watch à noite"; com dados → sem sugestão (teste A4). |
| CA5-4 | Sem `vo2Max` há 60 dias → sugestão de caminhada/corrida ao ar livre (teste A3). |
| CA5-5 | Sugestão de aeróbico vigoroso nunca cai nas 24 h antes de um dia de inferior; no mesmo dia de um treino de inferior, só modalidade de baixo impacto com ≥ 6 h de intervalo (teste A5). |
| CA5-6 | Nenhuma referência a FC em `Packages/TrainerCore/Sources/TrainerCore/Engine` (`check-boundaries.sh` continua verde). |

- [~] **T5.1 Regras de saúde em TrainerCore (A1–A6)** — Escopo: `Sources/TrainerCore/Health/HeartRateZones.swift` (FCmáx Tanaka, limiares ACSM, zonas), `Health/AerobicWeek.swift` (minutos por intensidade a partir de intervalos de FC já agregados por treino), `Health/Vo2MaxTrend.swift` (tendência + tabela de referência por idade/sexo), `Health/RecoveryTrend.swift` (médias 7 vs 28 dias, alertas), `Health/HealthSuggestions.swift` (A3, A4, A5 com o calendário do programa) + testes de tabela. Entradas são structs simples (`AerobicWorkoutSummary`, `DailyRecoverySample`); nada de HealthKit aqui. Sem Mac.
- [~] **T5.2 [CI] Leitura de saúde no HealthKit** — Escopo: `Services/HealthKit/LiveHealthKitService+Health.swift` (+ protocolo e fake): treinos aeróbicos dos últimos 28 dias com amostras de FC agregadas por minuto, `vo2Max` (180 dias), `heartRateVariabilitySDNN`, `restingHeartRate`, `sleepAnalysis`, `dateOfBirth`/`biologicalSex` (só para FCmáx e faixa de VO2max; opcional se negado). Depende de: T2.1.
- [~] **T5.3 [CI] Card "Saúde" e tela de detalhe** — Escopo: `Features/Health/*` (card na Home, tela com semana aeróbica, VO2max, recuperação, lista de sugestões com "ok, entendi"). Depende de: T5.1, T5.2.
- [~] **T5.4 Modulação da revisão por recuperação (SPEC §7.8 R6)** — Escopo: `Sources/TrainerCore/Review/RecoveryContext.swift` (só tendências agregadas), ajuste em `ProgramReviewer` + testes. Depende de: T4.5, T5.1. Nunca toca `Engine/`.

---

## M6 — App Store (v2.5)

**Decidido pelo dono em 2026-10-05:** o app do iPhone vai para a App Store do Brasil (SPEC decisão 22; regras L1–L8 na SPEC §7.18). Fase 1 (T11.0, T11.1): worktrees `C:\Users\leona\Developer\pt-wt\w9-<key>`, branches `v9/<key>`. Fase 2 (T11.2–T11.6): contrato `docs/V25-CONTRACT.md`, andaime no `main` (`edc8201`, o app já não lê nem abre nada da C4), worktrees `C:\Users\leona\Developer\pt-wt\w10-<key>`, branches `v10/<key>` e integração em `v10/integration` → `ci/v10-final`.

**Objetivo:** um build do iPhone que a App Store aceita, enviado pelo GitHub Actions, sem Mac. O app não envia dados a ninguém (rótulo "Dados não coletados"), o app não fala de sideload, mostra só os avisos indispensáveis e pede avaliação do jeito menos invasivo. A ficha da loja e as páginas de privacidade, suporte e termos ficam escritas.

**Pendentes do dono** (nenhum agente decide): o bundle ID (T11.10; o nome na loja já foi decidido: "Magister: Treino com Ciência"); a classificação de idade (entra na T11.9); o modelo do plano pago e o uso de IA (fora do M6; SPEC §3.4, decisão 13 em revisão).

**Critérios de aceitação M6**

| CA | Verificação | Estado |
|----|-------------|--------|
| CA11-1 | L1: nenhum código de rede nem pacote de terceiros no app. Um grep por `URLSession`, `NWConnection`, `NSURLConnection` e `import Network` em `PersonalTrainer/` e `Packages/` volta vazio, e o `project.yml` não tem pacote externo. | Verde: passo "Check L1: no network code" do App build 37395008741 (`ci/v10-final`, dce26a3) e o grep do contrato §7, vazio. |
| CA11-2 | O `.app` do IPA tem o `PrivacyInfo.xcprivacy` com `NSPrivacyTracking` falso, nenhum domínio de rastreamento, nenhum tipo de dado coletado e as APIs de motivo obrigatório que o app usa, com o motivo (T11.2). | Verde: manifesto conferido no `.app` do simulador e no IPA (`build-app.sh`), App build 37395008741. O grep das APIs de motivo obrigatório ainda só acha `UserDefaults`. |
| CA11-3 | L4: nenhum texto do app cita o "Impactor", o vencimento da instalação ou "Como renovar"; o diálogo nunca gera a C4 (teste "L4 …") (T11.4). | Verde: testes "L4 …" (Core tests 37395008576) e `testL4_…` (App build 37395008741); o grep do contrato §7 só acha o legado de `CoachService+LegacyReminder.swift`. |
| CA11-4 | L2 e L5: a seção Sobre dos Ajustes mostra a versão, a página "Privacidade" e a linha do aviso de saúde (T11.5). | Verde: `testL2_…` e `testL5_…` no App build 37395008741. A aparência das telas só se vê no aparelho. |
| CA11-5 | L3: testes de tabela verdes. Não pede com menos de 7 dias desde a primeira sessão concluída, com menos de 3 sessões concluídas, depois de uma sessão abandonada ou de um erro, nem duas vezes na mesma versão; pede quando tudo isso é cumprido (T11.6). | Verde: tabela "L3 …" (Core tests 37395008576) e `testL3_…` (App build 37395008741), com o Live ligado no ambiente. A caixa de verdade só aparece no app da loja (T11.7). |
| CA11-6 | O IPA da loja não leva o app do Watch, tem a versão 1.0.0, `ITSAppUsesNonExemptEncryption` falso e o texto de gravação no Saúde cita as sessões de força e as de aeróbico (T11.3). | Verde: `build-app.sh` no App build 37395008741 (IPA sem `Watch/`, 1.0.0, criptografia falsa, texto com força e aeróbico). |
| CA11-7 | Um build enviado ao App Store Connect pelo `release.yml`, sem Mac, com os segredos cadastrados pelo dono e nenhum segredo nos logs; nesse build, `AppLinks.privacyPolicyURL` e `AppLinks.supportURL` têm os endereços publicados, e a página Privacidade mostra o link da política (diretriz 5.1.1(i)) (T11.7). | |
| CA11-8 | Capturas de 6,9" geradas no simulador, como artefato de um run (T11.8). | |
| CA11-9 | Política de privacidade, suporte, termos e ficha da loja escritos e aprovados pelo dono, sem "personal", "treinador" ou "coach" para o app e sem promessas absolutas (L2, L5, L8; T11.9). | |

### Tarefas M6

- [x] **T11.0 Documentos** — agente de documentação · `v9/docs-launch`
  - Escopo: `SPEC.md`, `AGENTS.md`, `README.md`, este `TASKS.md`.
  - Feito: na SPEC, o cabeçalho com a revisão 2.5, P-2, P-7, §3.4, a C4 da §7.11 como nota histórica, a §7.18 (L1–L8, nova), §7.7, RNF-05, §10, as decisões 13 e 22, §12 e §13; o AGENTS 0.2 (quando o App build roda em `ci/**`; `release.yml`, `ExportOptions.plist` e `build-release.sh` como [PROJ]; bundle IDs, capabilities, segredos e rede na §7); o README sem "app pessoal"; este milestone.
  - Dependências: nenhuma.
  - Aceite: SPEC e AGENTS dizem o mesmo sobre a loja; os pendentes do dono estão listados sem decisão (SPEC decisão 22).

- [x] **T11.1 [PROJ] Reduzir os builds de CI** — agente ci · `v9/ci-reduce` (runs 37314805402 sem IPA e 37316606216 com IPA, verdes)
  - Escopo: `.github/workflows/app-build.yml` e, se preciso, `.github/workflows/core-tests.yml` e `Scripts/build-app.sh`.
  - Fazer: em push para `ci/**`, o App build compila e roda os testes; o IPA só sai quando o run é manual (`workflow_dispatch`), quando o branch termina em `-final` ou quando a mensagem do commit contém `[ipa]`. Commits só de documentação não disparam o App build (AGENTS §2).
  - Dependências: nenhuma. As outras [PROJ] do M6 (T11.3, T11.7, T11.8) esperam por ela.
  - Aceite: um push só de `.md` em `ci/<nome>` não dispara o App build; um push com código roda os testes sem gerar IPA; `ci/<nome>-final`, `[ipa]` na mensagem ou o run manual geram o IPA.
  - Depois dela: o dono pode tornar o repositório privado (SPEC decisão 22) **[USER]**.

- [x] **T11.2 [CI] Manifesto de privacidade (`PrivacyInfo.xcprivacy`)** — loja · `v10/loja` (junto com a T11.3, contrato `docs/V25-CONTRACT.md` §5.1) · App build 37381465494 (`ci/v10-loja`); integrada no App build 37395008741
  - Escopo: `PersonalTrainer/Resources/PrivacyInfo.xcprivacy`. A pasta `Resources/` já entra no target; `Support/` não entra (ARCHITECTURE §17).
  - Fazer (L1): `NSPrivacyTracking` falso; `NSPrivacyTrackingDomains` vazio; `NSPrivacyCollectedDataTypes` vazio; `NSPrivacyAccessedAPITypes` com as APIs de motivo obrigatório que o código do app usa. Hoje o app usa `UserDefaults` (motivo `CA92.1`: dados só do próprio app). Conferido por grep pelo arquiteto em 2026-10-05: nenhuma outra categoria (data de arquivo, tempo desde o boot, espaço em disco, teclados ativos) aparece em `PersonalTrainer/` nem em `Packages/TrainerCore/Sources`; a tarefa confere de novo antes de fechar.
  - Dependências: nenhuma. Como a T11.3 está na mesma tarefa, a checagem do arquivo na raiz do `.app` entra no `app-build.yml` e no `Scripts/build-app.sh`.
  - Aceite: CA11-2.

- [x] **T11.3 [PROJ][CI] `project.yml` da loja** — loja · `v10/loja` (contrato §5.1) · App build 37381465494 (`ci/v10-loja`); integrada no App build 37395008741
  - Escopo: `project.yml`; `.github/workflows/app-build.yml` e `Scripts/build-app.sh` (checagens do Watch, do manifesto e do IPA).
  - Fazer: o app do iPhone sem o app do Watch (L6: sai a dependência no `project.yml`; o target fica no projeto para o M3), com as checagens de Watch do `app-build.yml` e do `build-app.sh` invertidas; `MARKETING_VERSION` 1.0.0 (L7); `ITSAppUsesNonExemptEncryption` = `NO` (o app não usa criptografia além da do próprio iOS); o texto de gravação do Saúde (`NSHealthUpdateUsageDescription`) passa a citar as sessões de força e as de aeróbico, que desde a 2.4 também vão ao Saúde (RF-13), e o de leitura troca "Os dados ficam só neste aparelho" por "usa esses dados só no aparelho" (L1). O IPA de teste do dono continua: o artefato `PersonalTrainer-for-resigning` e o arquivo `PersonalTrainer-iphone-only-for-resigning.ipa` mantêm o nome (o guia de instalação cita esse nome). O bundle ID **não** muda nesta fase (T11.10 pendente).
  - Dependências: T11.1 (uma [PROJ] por vez); T11.10 para o bundle ID, numa tarefa [PROJ] seguinte.
  - Aceite: CA11-6.

- [x] **T11.4 [CI] Sem sideload no app (L4)** — sideload · `v10/sideload` (contrato §5.2) · Core tests 37382224213 e App build 37382224427 (`ci/v10-sideload`)
  - Escopo: a lista exata está no contrato §5.2. `App/RootView.swift` e `App/AppEnvironment+Factories.swift` já foram ajustados no andaime (`edc8201`) e ficam com o integrador.
  - Fazer: tirar a C4, a notificação da véspera, a seção "Avisos", "Como renovar", o `ProvisioningExpiryReader`, o `ProvisioningProfileParser` e todo texto com "Impactor". Os cases `CoachRule.installExpiry` e `CoachAction.howToRenew` ficam, sem uso, porque o `rawValue` está gravado no log do diálogo (AGENTS §4: case persistido não some nem muda de nome). Uma cópia de teste que vem da 2.4 pode ter o aviso da véspera agendado (identificador `coach.expiryReminder`): cancelar esse pedido uma vez. Também: "Spinning ou bicicleta" vira "Bicicleta indoor" no `displayName` do `OutsideActivityKind`, sem mudar o raw value (L8, marca de terceiros), e o texto do Ajustes sobre o backup diz o fato sem absoluto (L2).
  - Teste (R7): "L4 …" no TrainerCore: o diálogo nunca gera mensagem da C4, com qualquer entrada; no app, o cancelamento do aviso antigo.
  - Dependências: T11.0 (SPEC) e o andaime.
  - Aceite: CA11-3.

- [x] **T11.5 [CI] Sobre e Privacidade (L2, L5)** — sobre · `v10/sobre` (contrato §5.3) · App build 37381049724 (`ci/v10-sobre`)
  - Escopo: `PersonalTrainer/Features/Settings/MoreOptionsView.swift` (seção Sobre, inclusive o item "Avaliar o Magister" da T11.6), as views novas `PrivacyView.swift`, `PrivacyText.swift` e `AppLinks.swift` em `Features/Settings/`, os textos do backup (`SettingsViewModel.swift`, `Services/Backup/BackupService.swift`), o texto do perfil de saúde (`Features/Health/HealthProfileView.swift`) e os testes listados no contrato.
  - Fazer: na seção Sobre, a versão (já existe), a página "Privacidade" (L2) e a linha do aviso de saúde (L5). Os links da política e do suporte e o item "Avaliar o Magister" usam constantes opcionais num lugar só (`AppLinks`, hoje `nil`): sem o endereço, a linha não aparece. Textos factuais, sem promessa absoluta e sem mensagem de efeito (decisão 20). O backup sugere "Guarde-o num lugar só seu" (diretriz 5.1.3(ii)), e o arquivo passa a se chamar `Magister-backup-AAAA-MM-DD.json` (achado da T11.0; a importação aceita qualquer `.json`).
  - Dependências: nenhuma de código (a seção "Avisos" é da T11.4, noutro arquivo).
  - Aceite: CA11-4.

- [x] **T11.6 [CI] Pedido de avaliação (L3)** — avaliacao · `v10/avaliacao` (contrato §5.4) · App build 37393614387 e Core tests 37393614634 (`ci/v10-avaliacao`)
  - Escopo: no TrainerCore, `Sources/TrainerCore/AppStore/` (pasta nova: `RatingPromptPolicy.swift`, `RatingPromptInput.swift`, `RatingSessionEnding.swift`) e `Tests/TrainerCoreTests/RatingPromptPolicyTests.swift`; no app, `Services/RatingPrompt/` (protocolo + Live + Fake, R9, e o `RatingPromptGate`), o resultado da gravação no Saúde por sessão (`Services/HealthKit/HealthKitWorkoutRecorder.swift` e `HealthRecordOutcome.swift`), o pedido com `@Environment(\.requestReview)` no resumo da sessão (`Features/Session/SessionFlowView.swift` e `SessionSummaryView.swift`) e os testes do app. O item "Avaliar o Magister" do Sobre ficou com a T11.5 (mesmo arquivo). A ARCHITECTURE §17 já tem as duas pastas novas.
  - Fazer: a L3 inteira, com os detalhes fixados na SPEC (L3, "Detalhes fixados na fase 2"). A função pura recebe a data da primeira sessão concluída, o número de sessões concluídas, `now`, a versão atual, a versão e a data do último pedido, como a sessão terminou e se o app veio da loja, e diz se pede ou não.
  - Teste (R7): tabela "L3 …" com cada condição.
  - Dependências: nenhuma de código; o integrador passa o `LiveRatingPromptStore` ao `SessionFlowView`.
  - Aceite: CA11-5.

- [x] **Integração da fase 2** — integrador · `v10/integration` → `ci/v10-final` (contrato §7) · dce26a3: App build 37395008741 (com o IPA) e Core tests 37395008576, verdes na primeira rodada. Revisão estática adversarial com 1 achado (A1, major: nada impedia o primeiro envio com a política e o suporte vazios em `AppLinks`), corrigido pelo corretor só no plano (T11.7, T11.9 e CA11-7; o app não muda). Mesclada no `main` em 2026-10-06; o código final é o do App build 37395008741 (os commits depois de dce26a3 só mudam documentação, que não dispara o App build).
  - Fazer: juntar `v10/loja`, `v10/sideload`, `v10/sobre` e `v10/avaliacao`; ligar o pedido de avaliação no `AppEnvironment` e no `RootView`; rodar as conferências de CA11-1 a CA11-6; IPA no `ci/v10-final`.

- [ ] **T11.7 [PROJ][USER] Envio à loja (`release.yml`)**
  - Escopo: `.github/workflows/release.yml`, `ExportOptions.plist`, `Scripts/build-release.sh`; `PersonalTrainer/Features/Settings/AppLinks.swift` (só os valores de `privacyPolicyURL` e `supportURL`); na ARCHITECTURE, uma ADR para a distribuição pela loja.
  - Fazer: um workflow manual que gera o build assinado para distribuição e o envia ao App Store Connect com a chave da API, com o número do build automático (L7). Os segredos (a chave da API e o que mais a assinatura pedir) o dono cadastra nos Secrets do GitHub **[USER]**; o workflow nunca os imprime (AGENTS §7).
  - Antes do primeiro envio: `AppLinks.privacyPolicyURL` e `AppLinks.supportURL` recebem os endereços publicados da T11.9. A diretriz 5.1.1(i) pede o link da política dentro do app (e a Apple cobra mais de quem usa o Saúde); com `nil`, a linha não aparece na página Privacidade (L2) e a revisão da loja recusa o app. O `Scripts/build-release.sh` falha se um dos dois ainda for `nil`. O app sem endereço continua como está: a linha fica escondida, sem texto provisório.
  - Dependências: T11.3; T11.10 (bundle ID); T11.9 publicada no site do dono (os endereços da política e do suporte); a conta paga do Apple Developer Program ativa e o app criado no App Store Connect **[USER]**.
  - Aceite: CA11-7.

- [ ] **T11.8 [PROJ][CI] Capturas de 6,9" no simulador**
  - Escopo: um workflow manual de capturas em `.github/workflows/` e o script dele em `Scripts/build-*.sh`. Se precisar de dados de exemplo, um modo só para o simulador, com os arquivos do app listados na tarefa antes de começar.
  - Fazer: rodar o app no simulador de um iPhone de 6,9", com dados de exemplo inventados (nunca dados reais), e salvar como artefato do run as telas que o dono escolher (sugestão: Início, Hoje, sessão guiada, Metas da semana e "Como fazer").
  - Dependências: T11.3 e T11.7 (uma [PROJ] por vez); T11.4 e T11.5 (telas finais).
  - Aceite: CA11-8.

- [ ] **T11.9 Textos da loja: política, suporte, termos e ficha**
  - Escopo: `docs/store/` (pasta nova, em pt-BR): a política de privacidade, a página de suporte, os termos de uso e a ficha da loja.
  - Fazer: a política com os fatos de L1 (o app não envia dados a ninguém; o backup do iPhone no iCloud é da Apple; o que o app lê e grava no Saúde; o backup; apagar o app apaga os dados dele, e os treinos gravados no Saúde ficam no app Saúde, onde a pessoa pode apagá-los); o suporte (o contato entra quando o dono decidir, sem dado pessoal no repositório); os termos com a frase de L5; a ficha da loja (nome "Magister: Treino com Ciência", subtítulo a escolher, descrição, palavras-chave, o rótulo "Dados não coletados" e a classificação de idade quando o dono decidir). Linguagem de L8, sem promessas absolutas, frases curtas. As páginas precisam de um endereço público (o site do dono, pendente).
  - Dependências: T11.0. Textos com "com base científica", nunca "validado cientificamente" (decisão 22). Bloqueia a T11.7: os endereços publicados da política e do suporte entram em `AppLinks` antes do primeiro envio.
  - Aceite: CA11-9.

- [ ] **T11.11 [CI] Linha de idade no Sobre** — depois da cota de uso (decisão do dono de 2026-10-05: 16+)
  - Fazer: acrescentar "Indicado para 16 anos ou mais; menores de 18, com acompanhamento." ao aviso do Sobre (L5), com a SPEC e o teste do texto exato (R7).
- [ ] **T11.10 [USER] Bundle ID da loja** — bloqueada pelo dono (o nome já foi decidido em 2026-10-05: "Magister: Treino com Ciência")
  - Fazer (só o dono): escolher o nome na loja e o bundle ID da loja. O Impactor já instala a cópia de teste como `com.personaltrainer.app.<TEAMID>`, então a versão da loja é outro app no iPhone em qualquer caso, e os dados passam pelo backup (exportar na cópia de teste, importar na da loja). Depois do primeiro envio, o bundle ID não muda mais (AGENTS §7). Também esperam o dono: a classificação de idade (entra na T11.9) e o modelo do plano pago com o uso de IA (fora do M6).
  - Dependências: nenhuma. Bloqueia o bundle ID da T11.3, a T11.7 e o nome final da T11.9.
  - Aceite: as escolhas anotadas na SPEC, como complemento da decisão 22, numa tarefa de documentos.

**Achados ao escrever a T11.0** (fora do escopo dela; R10):
- O nome sugerido do arquivo de backup, `PersonalTrainer-backup-AAAA-MM-DD.json` (`Services/Backup/BackupService.swift`), aparece para a pessoa no app Arquivos e usa "Personal" (L8). **Decidido na fase 2:** troca na T11.5 para `Magister-backup-AAAA-MM-DD.json`; a importação não depende do nome (o seletor aceita qualquer `.json`, conferido no `SettingsView` e no `SettingsViewModel`).
- A ARCHITECTURE ainda descreve a validade da instalação no Coach (§17) e só o IPA sem assinatura; a T11.4 e a T11.7 atualizam. **Fase 2:** o §17 já foi atualizado pelo arquiteto (Coach sem a C4, `AppStore/`, `RatingPrompt/`, manifesto, Watch fora do build do iPhone); a ADR da loja continua com a T11.7.
- Os roteiros de instalação por sideload (`WINDOWS_SETUP.md`, `docs/install/`) continuam certos só para a cópia de teste.
- O README ainda tem a seção "Estado (2026-09-22)", desatualizada.

---

## Achados de campo

_(preencher após T1.12 e T3.10: o que atrapalhou na academia, o que ficou pequeno demais, o que a regra de progressão fez de estranho)_
