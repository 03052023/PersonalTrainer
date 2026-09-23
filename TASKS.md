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

- [ ] **T1.12 [CI] Instalar no iPhone e treinar uma vez** — G5
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
- [ ] **T2.22 [CI] Dias do programa: adicionar, remover, renomear, reordenar (RF-36)** (pedido do usuário, 2026-09-23) — `ProgramRepositoring` ganha `addDay(programID:name:) -> UUID` (novo dia com o próximo rótulo livre: A, B, C, D, E…), `removeDay(id:)` (mínimo 1 dia; se era o dia da última sessão, S2 recomeça em D1), `renameDay(id:to:)`, `moveDay(id:toIndex:)` (renumera `order`); limites 1–7 dias; UI no `ProgramDetailView`. Rodada seguinte à integração do M2 (os agentes atuais já estavam em execução quando o pedido chegou).
- [~] **T2.12 [CI] Escolha do objetivo na edição de programa** — Escopo: `Features/Program/GoalPicker.swift`, ajuste em T2.6. Depende de: T2.11.
- [~] **T2.9 [CI] Substituir exercício + editar/excluir série + abandonar** — G2 — Escopo: `Features/Session/ExercisePickerSheet.swift`, `Features/Session/SetEditSheet.swift`, ajustes em `ActiveSessionViewModel`. Eventos já existem (T1.3). Depende de: T1.5, T2.5. Aceite: CA2-3, CA2-8.
- [~] **T2.10 [CI] Resumo enriquecido + gráfico de carga por exercício** — G3 — Escopo: `Features/History/ExerciseProgressChart.swift` (Swift Charts), `SessionSummaryView` com tonelagem e FC. Depende de: T2.2, T2.3.

---

## M3 — Apple Watch

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

## M4 — Inteligência de programa

**Objetivo:** seleção por frequência, deload automático, troca de programa ao fim do mesociclo. Tudo em `TrainerCore` com testes; UI mínima.

**Critérios de aceitação M4**

| CA | Verificação |
|----|-------------|
| CA4-1 | Com Peito 2/2 e Pernas 0/2 na semana, seletor escolhe o dia de pernas mesmo fora da ordem de rotação (teste S5–S7). |
| CA4-2 | Grupo treinado há 30 h exclui o dia candidato; se todos excluídos, cai na rotação (teste S6). |
| CA4-3 | ≥ 50 % dos exercícios com `decrease` → próxima passagem da rotação é deload com séries ⌈0,6·S⌉, carga 0,85·L, RIR 4; a passagem seguinte volta às cargas pré-deload (teste). |
| CA4-4 | Após N semanas configuradas, programa ativo muda para o próximo da lista e as cargas por exercício são preservadas (teste de integração). |
| CA4-5 | Home exibe um aviso de uma linha explicando a escolha ("Pernas: abaixo da meta semanal" / "Semana de deload"). |

### Tarefas M4

- [ ] **T4.1 FrequencyAwareSelector** — Escopo: `Engine/FrequencyAwareSelector.swift` + testes. Depende de: T0.4, T2.3. Sem Mac.
- [ ] **T4.2 DeloadPolicy** — Escopo: `Engine/DeloadPolicy.swift`, ajuste em `DoubleProgressionRule` para ignorar entradas `wasDeload` + testes. Depende de: T0.3. Sem Mac.
- [ ] **T4.3 ProgramRotationPolicy** — Escopo: `Engine/ProgramRotationPolicy.swift` + testes. Depende de: T0.2. Sem Mac.
- [ ] **T4.5 Revisão periódica em TrainerCore (SPEC §7.8 R1–R5, R7)** — Escopo: `Sources/TrainerCore/Review/EstimatedOneRepMax.swift`, `Review/ReviewReport.swift`, `Review/ProgramSuggestion.swift`, `Review/ProgramReviewer.swift` + testes de tabela por regra. Entradas: histórico por exercício, `SessionSummary`s, programa, objetivo, `now`. Saída: `ReviewReport` com sinais e `[ProgramSuggestion]` (deload, volume ±, troca de exercício/faixa, frequência), cada uma com regra, motivo e números. `Review/` é módulo separado de `Engine/` (que continua sem qualquer referência a FC, R2). Sem Mac.
- [ ] **T4.7 [CI] Tela de sugestões na abertura** — Escopo: `Features/Review/*`, `Services/Review/ReviewScheduler.swift` (a cada `reviewIntervalWeeks`, ou gatilho de deload), aplicação de sugestões aceitas via `ProgramRepository`. Recusar mantém o programa; cada decisão fica registrada. Depende de: T4.5, T2.6. A modulação por recuperação (R6) chega em T5.4.
- [ ] **T4.4 [CI] Integrar políticas no SessionPlanner + configurações** — Escopo: `SessionPlanner.swift`, `Features/Settings/ProgramPolicyView.swift`, `Features/Home/PlannerReasonBanner.swift`. Depende de: T4.1–T4.3. Aceite: CA4-5.

---

## M5 — Saúde aeróbica e recuperação (SPEC §7.10)

**Antecipado em 2026-09-23 a pedido do usuário:** construído em paralelo com o M2 e entregue na mesma versão (antes de M3 e M4). Depende do HealthKit funcionar no aparelho com a instalação pelo Impactor (verificado no primeiro treino finalizado).

**Objetivo:** o app lê do HealthKit o que o Watch já mede (treinos aeróbicos, FC, VO2max, HRV, FC de repouso, sono) e devolve três coisas: minutos aeróbicos da semana contra a meta, tendência de VO2max e recuperação, e sugestões práticas ("use o Watch à noite", "caminhe 20 min ao ar livre", "faça o aeróbico na quinta, não na véspera de pernas"). Sem IA. Nada aqui grava no HealthKit nem altera a musculação.

**Critérios de aceitação M5**

| CA | Verificação |
|----|-------------|
| CA5-1 | Uma caminhada de 30 min registrada pelo Watch com FC em 70 % da FCmáx aparece como 30 min moderados; uma corrida de 20 min a 85 % aparece como 20 vigorosos = 40 moderados-equivalentes (teste de tabela A1/A2). |
| CA5-2 | Card "Saúde" na Home mostra "Aeróbico: X/150 min" da semana corrente e o último VO2max com a faixa por idade/sexo. |
| CA5-3 | Sem HRV/sono em 5 dos últimos 7 dias → sugestão "Use o Apple Watch à noite"; com dados → sem sugestão (teste A4). |
| CA5-4 | Sem `vo2Max` há 60 dias → sugestão de caminhada/corrida ao ar livre (teste A3). |
| CA5-5 | Sugestão de encaixe nunca cai na véspera ou no dia de um treino de inferior (teste A5). |
| CA5-6 | Nenhuma referência a FC em `Packages/TrainerCore/Sources/TrainerCore/Engine` (`check-boundaries.sh` continua verde). |

- [~] **T5.1 Regras de saúde em TrainerCore (A1–A6)** — Escopo: `Sources/TrainerCore/Health/HeartRateZones.swift` (FCmáx Tanaka, limiares ACSM, zonas), `Health/AerobicWeek.swift` (minutos por intensidade a partir de intervalos de FC já agregados por treino), `Health/Vo2MaxTrend.swift` (tendência + tabela de referência por idade/sexo), `Health/RecoveryTrend.swift` (médias 7 vs 28 dias, alertas), `Health/HealthSuggestions.swift` (A3, A4, A5 com o calendário do programa) + testes de tabela. Entradas são structs simples (`AerobicWorkoutSummary`, `DailyRecoverySample`); nada de HealthKit aqui. Sem Mac.
- [~] **T5.2 [CI] Leitura de saúde no HealthKit** — Escopo: `Services/HealthKit/LiveHealthKitService+Health.swift` (+ protocolo e fake): treinos aeróbicos dos últimos 28 dias com amostras de FC agregadas por minuto, `vo2Max` (180 dias), `heartRateVariabilitySDNN`, `restingHeartRate`, `sleepAnalysis`, `dateOfBirth`/`biologicalSex` (só para FCmáx e faixa de VO2max; opcional se negado). Depende de: T2.1.
- [~] **T5.3 [CI] Card "Saúde" e tela de detalhe** — Escopo: `Features/Health/*` (card na Home, tela com semana aeróbica, VO2max, recuperação, lista de sugestões com "ok, entendi"). Depende de: T5.1, T5.2.
- [~] **T5.4 Modulação da revisão por recuperação (SPEC §7.8 R6)** — Escopo: `Sources/TrainerCore/Review/RecoveryContext.swift` (só tendências agregadas), ajuste em `ProgramReviewer` + testes. Depende de: T4.5, T5.1. Nunca toca `Engine/`.

---

## Achados de campo

_(preencher após T1.12 e T3.10: o que atrapalhou na academia, o que ficou pequeno demais, o que a regra de progressão fez de estranho)_
