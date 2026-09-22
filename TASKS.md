# TASKS — Plano de execução

Versão 0.1 · 2026-09-22. Regras em [SPEC.md](SPEC.md), desenho em [ARCHITECTURE.md](ARCHITECTURE.md), conduta dos agentes em [AGENTS.md](AGENTS.md).

## Como usar este arquivo

- Cada tarefa é pequena (meio dia a um dia de trabalho de um agente), tem **arquivos que pode criar/editar** ("Escopo") e **dependências** explícitas. Duas tarefas sem dependência entre si e sem interseção de escopo podem rodar em paralelo (Claude Code em uma, Codex em outra).
- Tarefas marcadas **[PROJ]** editam `project.pbxproj`, entitlements ou `Info.plist`. Só uma **[PROJ]** por vez, nunca em paralelo com outra **[PROJ]**.
- Tarefas marcadas **[SCHEMA]** editam `Persistence/Schema/`. Só uma por vez.
- Tarefas marcadas **[MAC]** exigem macOS + Xcode. As demais (só `Packages/TrainerCore`) rodam em qualquer SO com toolchain Swift 6.
- Status: `[ ]` a fazer · `[~]` em andamento (escrever o agente e a branch) · `[x]` concluída (PR mergeado) · `[-]` cancelada.
- Um milestone só fecha quando **todos** os seus critérios de aceitação (CA) foram verificados manualmente ou por teste e anotados aqui.

Grupos paralelos: dentro de cada milestone, tarefas com a mesma letra de grupo (**G1**, **G2**…) podem rodar simultaneamente; grupos são sequenciais entre si.

---

## M0 — Esqueleto compilável e motor testado

**Objetivo:** projeto abre no Xcode, compila para iPhone e Watch (vazio), `TrainerCore` tem domínio, motor v1 e DTOs de sync com testes verdes. Nenhuma tela funcional ainda.

**Critérios de aceitação M0**

| CA | Verificação |
|----|-------------|
| CA0-1 | `swift test` em `Packages/TrainerCore` passa com ≥ 1 teste por regra P1–P8, P11, P12 e S1–S4. |
| CA0-2 | `xcodebuild -scheme PersonalTrainer -destination 'generic/platform=iOS'` compila sem warnings de concorrência não tratados. |
| CA0-3 | Target `PersonalTrainerWatch` compila e instala no simulador pareado mostrando texto "Em breve". |
| CA0-4 | Entitlement HealthKit e strings `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription` presentes nos dois targets; `WKBackgroundModes` contém `workout-processing`. |
| CA0-5 | `ModelContainerFactory.make(.inMemory)` abre `SchemaV1` em teste XCTest e insere/lê um `WorkoutSessionModel` com um `SetLogModel`. |
| CA0-6 | `grep` de imports proibidos em `Packages/TrainerCore/Sources` retorna vazio (ver AGENTS.md). |
| CA0-7 | `ActiveSessionSnapshot` e `SessionEvent` fazem round-trip JSON em teste e rejeitam `schemaVersion` maior que o suportado. |

### Tarefas M0

- [ ] **T0.1 [PROJ][MAC] Criar projeto Xcode e targets** — G1
  - Escopo: `PersonalTrainer.xcodeproj`, `PersonalTrainer/Support/*`, `PersonalTrainerWatch/Support/*`, `PersonalTrainer/App/PersonalTrainerApp.swift` (só `@main` com `Text`), `PersonalTrainerWatch/App/*App.swift` (idem), `.gitignore`.
  - Fazer: app iOS 18 + companion watchOS 11, synchronized folders, referência local ao pacote `Packages/TrainerCore` nos dois targets, entitlement HealthKit nos dois, plist strings, background mode `workout-processing` no Watch, Swift 6 mode, Team/bundle IDs placeholder documentados no README.
  - Depende de: nada. Bloqueia: todas as **[MAC]**.
  - Aceite: CA0-2, CA0-3, CA0-4.

- [ ] **T0.2 Domínio em TrainerCore** — G1
  - Escopo: `Packages/TrainerCore/Sources/TrainerCore/Domain/*`, `Package.swift`.
  - Fazer: todos os structs/enums da ARCHITECTURE §4, `Codable`, `Sendable`, `Hashable`, com `init` públicos e valores padrão da SPEC §7.2. Helper `Load.round(_:toIncrement:)` (arredondamento ↓ e ↑).
  - Depende de: nada. Bloqueia: T0.3, T0.4, T0.5, T0.6, T0.7.
  - Aceite: compila em `swift build`; teste de round-trip Codable de cada struct; teste de arredondamento.

- [ ] **T0.3 Motor de progressão v1** — G2
  - Escopo: `Sources/TrainerCore/Engine/ProgressionRule.swift`, `Engine/DoubleProgressionRule.swift`, `Tests/TrainerCoreTests/DoubleProgressionRuleTests.swift`.
  - Fazer: protocolo + implementação de P1–P8, P11, P12 (P9 fica para M2). Casos de tabela nomeados por regra, incluindo: sem histórico com/sem `startingLoad`; sucesso simples; sucesso com RIR alto (+2·inc); manter com meta de reps; falha 1ª vez; falha 2ª vez mesma carga; falha 2ª vez carga diferente (→ `retry`, não `decrease`); séries incompletas; 0 séries de trabalho ignora sessão; aquecimento ignorado; carga mínima; determinismo (duas chamadas iguais).
  - Depende de: T0.2.
  - Aceite: CA0-1 (parte P).

- [ ] **T0.4 Seletor de treino v1 (rotação)** — G2
  - Escopo: `Sources/TrainerCore/Engine/WorkoutSelector.swift`, `Engine/RotationSelector.swift`, `Tests/.../RotationSelectorTests.swift`.
  - Fazer: S1–S4. Casos: sem sessões → D1; após Dn → D1; sessão abandonada com séries conta; abandonada sem séries não conta; override manual (`lastChosenDayID` como parâmetro).
  - Depende de: T0.2.
  - Aceite: CA0-1 (parte S).

- [ ] **T0.5 [SCHEMA][MAC] SwiftData SchemaV1 + container factory** — G2
  - Escopo: `PersonalTrainer/Persistence/Schema/SchemaV1.swift`, `Persistence/MigrationPlan.swift`, `Persistence/ModelContainerFactory.swift`, `PersonalTrainerTests/Persistence/SchemaV1Tests.swift`.
  - Fazer: os 8 modelos da ARCHITECTURE §5 exatamente (nomes, campos, inversos, delete rules), `VersionedSchema`, `SchemaMigrationPlan` com um estágio, factory `.persistent`/`.inMemory`.
  - Depende de: T0.1, T0.2 (raw values dos enums).
  - Aceite: CA0-5.

- [ ] **T0.6 Dados semente (JSON + loader puro)** — G2
  - Escopo: `PersonalTrainer/Resources/Seed/exercises.v1.json`, `Resources/Seed/program-default.v1.json`, `Sources/TrainerCore/Domain/SeedBundle.swift` (struct Codable que representa os dois arquivos), `Tests/.../SeedBundleTests.swift`.
  - Fazer: ~40 exercícios comuns de academia com slugs, grupos, equipamento e incremento; programa A/B/C de 3 dias × 5–6 exercícios com parâmetros da SPEC. Teste que decodifica os JSONs (copiados para os testes do pacote como fixture) e valida: slugs únicos, todo exercício do programa existe no catálogo, `repMin < repMax`, `loadIncrement > 0`.
  - Depende de: T0.2. Não toca no app (o `SeedLoader` que grava no SwiftData é T1.10).
  - Aceite: teste verde; JSON legível à mão.

- [ ] **T0.7 DTOs de sync** — G2
  - Escopo: `Sources/TrainerCore/Sync/SessionEvent.swift`, `Sync/ActiveSessionSnapshot.swift`, `Sync/SyncSchema.swift` (`currentVersion`), `Tests/.../SyncDTOTests.swift`.
  - Fazer: conforme ARCHITECTURE §7 e §9. Decoder que rejeita `schemaVersion > currentVersion` com erro tipado.
  - Depende de: T0.2.
  - Aceite: CA0-7.

- [ ] **T0.8 [MAC] Protocolos de serviços externos + Fakes** — G2
  - Escopo: `PersonalTrainer/Services/HealthKit/HealthKitServicing.swift`, `Services/HealthKit/FakeHealthKitService.swift`, `Services/WatchSync/WatchSyncServicing.swift`, `Services/WatchSync/NoopWatchSyncService.swift`, `Services/Notifications/NotificationScheduling.swift` + `Fake`.
  - Fazer: só protocolos e fakes (ARCHITECTURE §8, §9). Nenhum `import HealthKit` real ainda — `LiveHealthKitService` é T2.1.
  - Depende de: T0.1.
  - Aceite: compila; fakes usáveis em previews.

- [ ] **T0.9 [MAC] Mappers SwiftData ↔ TrainerCore** — G3
  - Escopo: `PersonalTrainer/Persistence/Mappers/*`, `PersonalTrainerTests/Persistence/MapperTests.swift`.
  - Fazer: `ExerciseModel ⇄ ExerciseDefinition`, `ProgramModel → ProgramTemplate`, `[SessionExerciseModel] → [ExerciseHistoryEntry]` (filtrando por `exerciseUUID`, ordenado do mais recente), `WorkoutSessionModel → SessionSummary`.
  - Depende de: T0.2, T0.5.
  - Aceite: testes de ida e volta em container in-memory.

- [ ] **T0.10 [MAC] Verificação de fronteira em CI local** — G3
  - Escopo: `Scripts/check-boundaries.sh`, `Scripts/test-core.sh`.
  - Fazer: script que roda o `grep` de imports proibidos e `swift test` do pacote; documentar no README.
  - Depende de: T0.2.
  - Aceite: CA0-6.

---

## M1 — MVP utilizável na academia (iPhone)

**Objetivo:** usar de verdade no próximo treino. Programa vem do JSON semente. Sem HealthKit, sem Watch, sem edição, sem export.

**Critérios de aceitação M1**

| CA | Verificação |
|----|-------------|
| CA1-1 | Instalação limpa → Home mostra "Dia A" com todos os exercícios do JSON, cada um com "S × min–max · carga ou '—' · RIR T · descanso". |
| CA1-2 | Tocar **Iniciar** → tela de sessão; a primeira série do primeiro exercício vem pré-preenchida com a prescrição. |
| CA1-3 | **Concluir série** persiste em < 100 ms perceptível e inicia o timer com o `restSeconds` do exercício; o timer dispara notificação local com o app em segundo plano. |
| CA1-4 | Matar o app no meio da sessão e reabrir → Home mostra **Retomar**; todas as séries concluídas estão lá. |
| CA1-5 | **Finalizar** → Home mostra "Dia B". Voltar a treinar A depois de B e C → as cargas de A refletem P4/P5/P6 conforme os registros (teste de integração T1.11 + verificação manual com um exercício). |
| CA1-6 | Pular exercício → aparece como pulado no histórico; não afeta a prescrição futura desse exercício (P7 com 0 séries). |
| CA1-7 | Histórico lista sessões por data com dia, duração e nº de séries; detalhe mostra cada série (carga × reps @ RIR). |
| CA1-8 | Toda a Home e a sessão ativa funcionam em modo avião. |
| CA1-9 | Nenhuma View chama `modelContext.insert/delete` (grep em `Features/` retorna vazio). |

### Tarefas M1

- [ ] **T1.1 [MAC] AppEnvironment, injeção e navegação raiz** — G1
  - Escopo: `PersonalTrainer/App/AppEnvironment.swift`, `App/RootView.swift`, `App/PersonalTrainerApp.swift` (substituir placeholder).
  - Fazer: `AppEnvironment` (`@Observable`, `@MainActor`) segurando container, `SessionCoordinator`, `SessionPlanner`, serviços (fakes por padrão em DEBUG/simulador); `TabView` Home · Histórico; `.modelContainer`.
  - Depende de: T0.5, T0.8. Interfaces de `SessionCoordinator`/`SessionPlanner` são definidas aqui como protocolos vazios para que T1.2/T1.3 preencham em paralelo.
  - Aceite: app abre em duas abas vazias.

- [ ] **T1.2 [MAC] SessionPlanner** — G2
  - Escopo: `Services/Planning/SessionPlanner.swift`, `PersonalTrainerTests/Services/SessionPlannerTests.swift`.
  - Fazer: `nextPlan() -> SessionPlan` (DTO: dia + prescrições, sem gravar) e `startSession(from plan) -> UUID` (cria `WorkoutSessionModel` com snapshots via evento `sessionStarted`). Usa `RotationSelector` + `DoubleProgressionRule` + mappers. Recusa iniciar se já há `inProgress`.
  - Depende de: T0.3, T0.4, T0.9, T1.1.
  - Aceite: teste: seed in-memory → `nextPlan()` retorna Dia A com cargas `nil`/`startingLoad`.

- [ ] **T1.3 [MAC] SessionCoordinator** — G2
  - Escopo: `Services/Session/SessionCoordinator.swift`, `Services/Session/AppliedEventStore.swift`, `PersonalTrainerTests/Services/SessionCoordinatorTests.swift`.
  - Fazer: `apply(_:)` para todos os `SessionEvent.Kind` (M1 usa `sessionStarted`, `setLogged`, `exerciseSkipped`, `sessionFinished`, `sessionAbandoned`; os demais implementados mas sem UI); `save()` imediato; dedup por `event.id`; `AsyncStream<SessionEvent>` `eventsApplied`; `activeSession() -> WorkoutSessionModel?`.
  - Depende de: T0.5, T0.7, T1.1.
  - Aceite: teste por `Kind`; teste de idempotência; teste de que `setLogged` está no disco após `apply` (reabrir contexto).

- [ ] **T1.4 [MAC] Tela Home** — G3
  - Escopo: `Features/Home/HomeView.swift`, `Features/Home/HomeViewModel.swift`, `Features/Home/PrescriptionRow.swift`.
  - Fazer: card "Próximo treino: <dia>", lista de `PrescriptionRow`, botão Iniciar/Retomar. Formatação pt-BR ("60 kg", "3 × 8–12", "RIR 2", "2 min"). A Home **não** conhece `ActiveSessionView`: expõe `onStart(sessionID)` e quem liga Home → Sessão é `RootView` (T1.8), evitando dependência com T1.5 dentro do mesmo grupo paralelo.
  - Depende de: T1.2, T1.3.
  - Aceite: CA1-1, CA1-2 (navegação).

- [ ] **T1.5 [MAC] Tela de sessão ativa (estrutura)** — G3
  - Escopo: `Features/Session/ActiveSessionView.swift`, `Features/Session/ActiveSessionViewModel.swift`, `Features/Session/ExerciseProgressList.swift`.
  - Fazer: ViewModel mantém estado em memória da sessão (não `@Query`), lista de exercícios com progresso "2/3", exercício atual destacado, botões Pular / Finalizar (com confirmação). Delega registro de série ao componente T1.6 via closure e ao coordinator via evento.
  - Depende de: T1.3. Pode rodar em paralelo com T1.4 e T1.6 usando dados de preview.
  - Aceite: CA1-4, CA1-6 (fluxo), CA1-9.

- [ ] **T1.6 [MAC] Componente de registro de série** — G3
  - Escopo: `Features/Session/SetEntryView.swift`, `Features/Session/LoadStepper.swift`, `Features/Session/RIRPicker.swift`.
  - Fazer: view pura (entrada: `SetDraft`; saída: `onComplete(SetDraft)`), steppers grandes de carga (passo = `loadIncrement`, toque longo acelera) e reps, seletor RIR 0–5 em segmentos, toggle aquecimento, botão **Concluir série** ≥ 56 pt. Sem acesso a coordinator/SwiftData.
  - Depende de: T0.2 apenas. Totalmente paralelizável.
  - Aceite: previews com Dynamic Type XXL sem quebra; RNF-06.

- [ ] **T1.7 [MAC] Timer de descanso** — G3
  - Escopo: `Services/RestTimer/RestTimer.swift`, `Features/Session/RestTimerView.swift`, `Services/Notifications/LiveNotificationScheduler.swift`.
  - Fazer: `RestTimer` `@Observable` baseado em `endDate`; agenda `UNNotificationRequest` ao iniciar, cancela ao pular; haptic ao zerar em primeiro plano; view compacta (anel + "1:32" + botões +30 s / Pular). Pedir permissão de notificação na primeira vez.
  - Depende de: T0.8 (protocolo). Totalmente paralelizável.
  - Aceite: CA1-3 (parte timer); timer correto após app em background por 2 min.

- [ ] **T1.8 [MAC] Finalizar sessão + resumo** — G4
  - Escopo: `Features/Session/SessionSummaryView.swift`, `Features/Session/ActiveSessionViewModel+Finish.swift`.
  - Fazer: emitir `sessionFinished`, mostrar resumo (duração, séries de trabalho, exercícios pulados), botão Fechar → Home recalcula.
  - Depende de: T1.5.
  - Aceite: CA1-5 (fluxo).

- [ ] **T1.9 [MAC] Histórico (lista + detalhe)** — G3
  - Escopo: `Features/History/HistoryListView.swift`, `Features/History/SessionDetailView.swift`.
  - Fazer: `@Query` de `WorkoutSessionModel` ordenado por `startedAt` desc; linha com dia, data, duração, nº séries; detalhe com exercícios e séries "60 kg × 10 @ RIR 2", pulados marcados.
  - Depende de: T0.5. Paralelizável com toda a G3.
  - Aceite: CA1-7.

- [ ] **T1.10 [MAC] SeedLoader no primeiro launch** — G2
  - Escopo: `Services/Seed/SeedLoader.swift`, `PersonalTrainerTests/Services/SeedLoaderTests.swift`.
  - Fazer: ler JSONs do bundle, upsert por `slug`, criar `UserSettingsModel`, gravar `schemaSeedVersion`; idempotente.
  - Depende de: T0.5, T0.6, T0.9.
  - Aceite: rodar duas vezes não duplica; teste in-memory.

- [ ] **T1.11 [MAC] Teste de integração do loop completo** — G4
  - Escopo: `PersonalTrainerTests/Integration/FullLoopTests.swift`.
  - Fazer: seed → plano A → iniciar → registrar 3×12 em um exercício com `startingLoad` 40 → finalizar → plano B → … → plano A de novo → afirmar carga 42,5 e nota `increase`; variante de falha dupla → `decrease`.
  - Depende de: T1.2, T1.3, T1.10.
  - Aceite: CA1-5.

- [ ] **T1.12 [MAC] Instalar no iPhone e treinar uma vez** — G5
  - Escopo: nenhum arquivo; anotar achados em `TASKS.md` seção "Achados de campo".
  - Depende de: tudo de M1.
  - Aceite: CA1-1 a CA1-9 marcados manualmente.

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

- [ ] **T2.1 [MAC] LiveHealthKitService — gravar HKWorkout** — G1 — Escopo: `Services/HealthKit/LiveHealthKitService.swift`, `Services/HealthKit/HealthKitWorkoutRecorder.swift` (reage a `sessionFinished` via `eventsApplied`, checa `hkWorkoutUUID == nil`, grava, emite `heartRateSummary` com o UUID). Depende de: T0.8, T1.3. Aceite: CA2-1.
- [ ] **T2.2 [MAC] Leitura de FC pós-sessão** — G1 — Escopo: `LiveHealthKitService+HeartRate.swift`, `Features/History/HeartRateSection.swift`. `HKStatisticsQuery` avg/max no intervalo. Depende de: T2.1. Aceite: CA2-2.
- [ ] **T2.3 Cálculo de resumo em TrainerCore** — G1 — Escopo: `Sources/TrainerCore/Summary/SessionStats.swift` (duração, tonelagem, séries de trabalho), `Summary/WeeklyFrequency.swift` (SPEC §7.4), testes. Depende de: T0.2. Sem Mac.
- [ ] **T2.4 [MAC] Backup export/import** — G1 — Escopo: `Services/Backup/BackupDocument.swift`, `BackupService.swift`, `Features/Settings/BackupView.swift`, testes de round-trip in-memory. Depende de: T0.9, T1.3. Aceite: CA2-5.
- [ ] **T2.5 [MAC] Edição de catálogo** — G2 — Escopo: `Features/Catalog/*`, `Persistence/Repositories/CatalogRepository.swift`. Depende de: T0.5. Aceite: RF-15.
- [ ] **T2.6 [MAC] Edição de programa** — G2 — Escopo: `Features/Program/*`, `Persistence/Repositories/ProgramRepository.swift`. Depende de: T0.5, T2.5 (picker de exercício). Aceite: CA2-4.
- [ ] **T2.7 [MAC] Painel de frequência semanal** — G2 — Escopo: `Features/Home/WeeklyFrequencyCard.swift`, `Features/Settings/WeeklyTargetsView.swift`. Depende de: T2.3. Aceite: CA2-6.
- [ ] **T2.8 Regra P9 (retorno após pausa)** — G1 — Escopo: `DoubleProgressionRule.swift` + testes. Depende de: T0.3. Sem Mac. Aceite: CA2-7.
- [ ] **T2.9 [MAC] Substituir exercício + editar/excluir série + abandonar** — G2 — Escopo: `Features/Session/ExercisePickerSheet.swift`, `Features/Session/SetEditSheet.swift`, ajustes em `ActiveSessionViewModel`. Eventos já existem (T1.3). Depende de: T1.5, T2.5. Aceite: CA2-3, CA2-8.
- [ ] **T2.10 [MAC] Resumo enriquecido + gráfico de carga por exercício** — G3 — Escopo: `Features/History/ExerciseProgressChart.swift` (Swift Charts), `SessionSummaryView` com tonelagem e FC. Depende de: T2.2, T2.3.

---

## M3 — Apple Watch

**Objetivo:** treinar só com o relógio, iPhone no armário. FC ao vivo. Zero perda ou duplicação de séries.

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

- [ ] **T3.1 [PROJ][MAC] Configurar WCSession nos dois targets** — G1 — Escopo: `Services/WatchSync/LiveWatchSyncService.swift` (iOS), `PersonalTrainerWatch/Services/PhoneSyncService.swift`, ativação em ambos os `App.swift`. Depende de: T0.7, T0.8. Só configuração e canais; sem UI.
- [ ] **T3.2 Fila e reconciliação em TrainerCore** — G1 — Escopo: `Sources/TrainerCore/Sync/PendingEventQueue.swift`, `Sync/SnapshotReconciler.swift`, testes. Regras da ARCHITECTURE §9. Depende de: T0.7. Sem Mac.
- [ ] **T3.3 [MAC] ActiveSessionStore no relógio** — G2 — Escopo: `PersonalTrainerWatch/Services/ActiveSessionStore.swift` (JSON em Application Support, snapshot + fila). Depende de: T3.2.
- [ ] **T3.4 [MAC] Snapshot publisher no iPhone** — G2 — Escopo: `Services/WatchSync/SnapshotPublisher.swift` (constrói `ActiveSessionSnapshot` do `WorkoutSessionModel` e do `nextPlan()`, envia em `eventsApplied` e ao calcular a Home). Depende de: T3.1, T1.2, T1.3.
- [ ] **T3.5 [MAC] UI do relógio — sessão** — G3 — Escopo: `PersonalTrainerWatch/Features/Session/*` (exercício atual, série atual, Crown para carga/reps, RIR em botões, Concluir). Depende de: T3.3. Emite `SessionEvent` para a fila.
- [ ] **T3.6 [MAC] WorkoutManager (HKWorkoutSession + FC ao vivo)** — G3 — Escopo: `PersonalTrainerWatch/Services/WorkoutManager.swift`, `Features/Session/HeartRateView.swift`. Depende de: T3.3. Envia `heartRateSummary(hkWorkoutUUID:)` ao finalizar.
- [ ] **T3.7 [MAC] Timer de descanso no relógio** — G3 — Escopo: `PersonalTrainerWatch/Features/Session/WatchRestTimerView.swift` (reusa `RestTimer` se movido para TrainerCore em T3.2, senão cópia mínima), `WKInterfaceDevice.play(.notification)`. Depende de: T3.3.
- [ ] **T3.8 [MAC] iPhone: não duplicar HKWorkout quando origem é Watch** — G3 — Escopo: `HealthKitWorkoutRecorder.swift` (ajuste da trava §8). Depende de: T2.1, T3.4. Aceite: CA3-5.
- [ ] **T3.9 [MAC] Home do relógio (próximo treino + Iniciar)** — G4 — Escopo: `PersonalTrainerWatch/Features/Home/*`. Depende de: T3.4, T3.5. Aceite: CA3-2.
- [ ] **T3.10 [MAC] Teste de campo M3** — G5 — Cenários CA3-1 a CA3-7 no aparelho; achados em "Achados de campo".

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
- [ ] **T4.4 [MAC] Integrar políticas no SessionPlanner + configurações** — Escopo: `SessionPlanner.swift`, `Features/Settings/ProgramPolicyView.swift`, `Features/Home/PlannerReasonBanner.swift`. Depende de: T4.1–T4.3. Aceite: CA4-5.

---

## M5 — Análise periódica por IA (opcional)

- [ ] **T5.1** Pacote de análise: `BackupService.exportAnalysisPackage()` gera Markdown + JSON com últimas 8 semanas por exercício (cargas, reps, RIR, notas, frequência, FC média) — sem dados pessoais além do treino. Sem Mac para a parte em TrainerCore.
- [ ] **T5.2** Importar programa sugerido: `program-*.json` no mesmo formato do seed vira novo `ProgramModel` inativo, para o usuário ativar.
- [ ] **T5.3** (Só se desejado) chamada opcional à API Claude a partir do iPhone, com chave do usuário em Keychain, desligada por padrão. Nunca no caminho da sessão.

---

## Achados de campo

_(preencher após T1.12 e T3.10: o que atrapalhou na academia, o que ficou pequeno demais, o que a regra de progressão fez de estranho)_
