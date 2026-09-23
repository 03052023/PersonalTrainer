# ARCHITECTURE — Personal Trainer Automático

Versão 0.1 · 2026-09-22. Regras de produto em [SPEC.md](SPEC.md); tarefas em [TASKS.md](TASKS.md); regras para agentes em [AGENTS.md](AGENTS.md).

---

## 1. Visão geral

```
┌─────────────────────────── iPhone — FONTE DA VERDADE ───────────────────────────┐
│  PersonalTrainer (app SwiftUI, iOS 18+)                                          │
│                                                                                  │
│   Features/        Home · Session · History · Catalog · Program · Settings       │
│        │  (Views + ViewModels; leitura via @Query, escrita só via Services)      │
│        ▼                                                                         │
│   Services/        SessionPlanner ── monta a próxima sessão (usa o motor)        │
│                    SessionCoordinator ── ÚNICO caminho de escrita da sessão      │
│                    HealthKitService ── HKWorkout + leitura de FC (protocolo)     │
│                    WatchSyncService ── WCSession (M3; stub em M0)                │
│                    SeedLoader · BackupService · RestTimer                        │
│        │                                                                         │
│        ▼                                                                         │
│   Persistence/     SwiftData SchemaV1 · ModelContainerFactory · Mappers          │
│        │                                                                         │
│        ▼                                                                         │
│  ┌────────────────────────────────────────────┐                                  │
│  │ TrainerCore (Swift Package, Swift puro)    │  ◄── compartilhado com o Watch   │
│  │  Domain/   structs Codable+Sendable        │                                  │
│  │  Engine/   ProgressionRule · WorkoutSelector                                  │
│  │  Sync/     SessionEvent · ActiveSessionSnapshot (DTOs versionados)            │
│  │  Sem UIKit · sem SwiftData · sem HealthKit · sem WatchConnectivity            │
│  └────────────────────────────────────────────┘                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
                              ▲                    │  WatchConnectivity
                              │ importa            ▼
┌───────────────────────── Apple Watch — CLIENTE FINO (M3) ────────────────────────┐
│  PersonalTrainerWatch (app companion SwiftUI, watchOS 11+)                       │
│   ActiveSessionStore   snapshot Codable em arquivo (SEM SwiftData)               │
│   WorkoutManager       HKWorkoutSession + HKLiveWorkoutBuilder → FC ao vivo      │
│   WatchSyncService     recebe snapshot; envia SessionEvents (fila garantida)     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Três ideias sustentam tudo:

1. **O motor não conhece Apple.** `TrainerCore` só depende de Foundation. Roda em testes de linha de comando, no iPhone e no relógio sem mudança.
2. **Toda escrita de sessão é um `SessionEvent`.** A UI do iPhone, a UI do relógio e o importador de backup produzem os mesmos eventos; só o `SessionCoordinator` os aplica ao SwiftData. Quando o Watch chegar, não há nova lógica de escrita, só um novo produtor de eventos.
3. **Um só banco.** O relógio nunca tem SwiftData. Ele guarda apenas o snapshot da sessão ativa e uma fila de eventos ainda não entregues.

## 2. Targets, pacotes e versões

| Nome | Tipo | Depende de | Responsabilidade |
|------|------|------------|------------------|
| `TrainerCore` | Swift Package (`Packages/TrainerCore`) | Foundation | Domínio, motor, DTOs de sync, cálculo de resumo (tonelagem, frequência). 100 % testável com `swift test`. |
| `PersonalTrainer` | App iOS | TrainerCore, SwiftData, HealthKit, WatchConnectivity, UserNotifications | UI iPhone, persistência, serviços. |
| `PersonalTrainerWatch` | App watchOS (companion, embutido no app iOS) | TrainerCore, HealthKit, WatchConnectivity | UI relógio, `HKWorkoutSession`, snapshot local. Criado vazio em M0, implementado em M3. |
| `TrainerCoreTests` | Testes (Swift Testing) | TrainerCore | Casos de tabela do motor. |
| `PersonalTrainerTests` | Testes (XCTest, simulador) | PersonalTrainer | Persistência in-memory, mappers, coordinator. |

**Decisões de toolchain**

- Xcode 16 ou superior. Projeto único `PersonalTrainer.xcodeproj` com **synchronized folders** (pastas sincronizadas): arquivos adicionados no disco entram no target automaticamente, sem editar `project.pbxproj`. Isso é o que permite vários agentes criarem arquivos em paralelo sem conflito de merge no projeto.
- Deployment: iOS 18.0 / watchOS 11.0. Motivo: SwiftData amadureceu bastante no 18; abaixo disso há bugs conhecidos de relacionamento e migração. Ajustar para cima se os aparelhos permitirem; nunca para baixo de 17.
- Swift 6 language mode em `TrainerCore` (obrigatório: tudo é value type `Sendable`, custo zero). Swift 6 mode nos apps também, com SwiftData confinado a `@MainActor` (§10). Se isso travar um agente, o fallback permitido é Swift 5 mode **apenas no target do app**, registrado como ADR.
- Nenhuma dependência de terceiros. Nem pacotes SwiftPM externos, nem CocoaPods.
- Bundle IDs: `<TEAM>.PersonalTrainer` e `<TEAM>.PersonalTrainer.watchkitapp`. Grupo de HealthKit e background modes definidos em T0.1.

## 3. Camadas e regras de dependência

```
Features ──► Services (via protocolos) ──► Persistence ──► TrainerCore
   │                                            ▲
   └──── @Query (só leitura) ───────────────────┘
```

| Regra | Motivo |
|-------|--------|
| `TrainerCore` não importa nada além de Foundation. Verificado por CI: `grep -r "import SwiftData\|import HealthKit\|import UIKit\|import WatchConnectivity" Packages/TrainerCore/Sources` deve retornar vazio. | Testabilidade e reuso no Watch. |
| Views podem ler com `@Query` e `@Environment(\.modelContext)`. Views **nunca** chamam `modelContext.insert/delete` nem alteram `@Model` de sessão diretamente. | Um só caminho de escrita facilita sync, undo e testes. |
| Escrita de sessão: só `SessionCoordinator.apply(_ event: SessionEvent)`. Escrita de catálogo/programa: `CatalogRepository`, `ProgramRepository`. | Ver §7. |
| Serviços com efeitos externos (HealthKit, WCSession, notificações, relógio) ficam atrás de protocolos com implementação `Live` e `Fake`. | Previews, testes e simulador sem HealthKit. |
| ViewModels são `@Observable` classes `@MainActor`; recebem serviços por injeção via `AppEnvironment`. | Sem singletons ocultos. |

## 4. Modelo de domínio (TrainerCore, value types)

Todos `struct`, `Codable`, `Sendable`, `Hashable`. Identificadores são `UUID` gerados no cliente (estáveis entre iPhone, Watch e backup).

```swift
// Domain/MuscleGroup.swift
public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
  case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core
}
public enum Equipment: String, Codable, Sendable { case barbell, dumbbell, machine, cable, bodyweight, smith, kettlebell }
public enum LoadUnit: String, Codable, Sendable { case kilograms, plates, level }

// Domain/ExerciseDefinition.swift  (catálogo)
public struct ExerciseDefinition {
  id: UUID, slug: String, name: String,
  primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup],
  equipment: Equipment, loadUnit: LoadUnit, loadIncrement: Double,
  isUnilateral: Bool, machineNotes: String?
}

// Domain/ProgramTemplate.swift
public struct ProgramTemplate { id, name, days: [ProgramDayTemplate], isActive }
public struct ProgramDayTemplate { id, name, order, exercises: [ExerciseTarget] }
public struct ExerciseTarget {
  id, exerciseID: UUID, order: Int,
  sets: Int, repMin: Int, repMax: Int, targetRIR: Int, restSeconds: Int, startingLoad: Double?
}

// Domain/Prescription.swift  (saída do motor)
public enum PrescriptionNote: String, Codable, Sendable { case calibrate, increase, hold, retry, decrease, returning, deload }
public struct ExercisePrescription {
  exerciseID, load: Double?, sets, repMin, repMax, targetReps, targetRIR, restSeconds, note
}

// Domain/SetResult.swift  (entrada do motor — NÃO tem campo de FC, por construção)
public struct SetResult { load: Double, reps: Int, rir: Int?, isWarmup: Bool, completedAt: Date }
public struct ExerciseHistoryEntry { sessionID: UUID, date: Date, sets: [SetResult], wasDeload: Bool }

// Domain/SessionSummary.swift  (entrada do seletor)
public struct SessionSummary { id, programDayID, startedAt, endedAt, status, primaryMusclesTrained: Set<MuscleGroup>, workingSetCount }
```

## 5. Esquema de persistência — SwiftData `SchemaV1` (iPhone)

```
ExerciseModel 1 ──── * ProgramExerciseModel * ──── 1 ProgramDayModel * ──── 1 ProgramModel
      │
      └──── * SessionExerciseModel * ──── 1 WorkoutSessionModel
                     │
                     └──── * SetLogModel
UserSettingsModel (linha única)
```

| Modelo | Campos principais | Relações / regras de exclusão |
|--------|-------------------|-------------------------------|
| `ExerciseModel` | `uuid` (`.unique`), `slug` (`.unique`), `name`, `primaryMusclesRaw: String` (CSV de rawValues), `secondaryMusclesRaw`, `equipmentRaw`, `loadUnitRaw`, `loadIncrement`, `isUnilateral`, `machineNotes`, `isArchived` | Nunca é deletado fisicamente (`isArchived`) — o histórico aponta para ele. |
| `ProgramModel` | `uuid`, `name`, `isActive`, `createdAt` | `days` cascade. |
| `ProgramDayModel` | `uuid`, `name`, `order` | `exercises` cascade. `program` inverso. |
| `ProgramExerciseModel` | `uuid`, `order`, `sets`, `repMin`, `repMax`, `targetRIR`, `restSeconds`, `startingLoad?` | `exercise` → `ExerciseModel` (nullify). |
| `WorkoutSessionModel` | `uuid`, `programDayUUID` (cópia, não relação), `programDayName` (snapshot), `statusRaw`, `startedAt`, `endedAt?`, `notes`, `hkWorkoutUUID?`, `avgHeartRate?`, `maxHeartRate?`, `isDeload`, `sourceRaw` (`iphone`/`watch`) | `exercises` cascade. |
| `SessionExerciseModel` | `uuid`, `order`, `exerciseUUID` (cópia), `exerciseName` (snapshot), `prescribedLoad?`, `prescribedSets`, `prescribedRepMin`, `prescribedRepMax`, `prescribedRIR`, `restSeconds`, `noteRaw`, `wasSkipped`, `substitutedFromUUID?` | `exercise` → `ExerciseModel` (nullify); `sets` cascade; `session` inverso. |
| `SetLogModel` | `uuid` (`.unique`), `index`, `load`, `reps`, `rir?`, `isWarmup`, `completedAt`, `sourceRaw`, `updatedAt` | `sessionExercise` inverso. |
| `UserSettingsModel` | `weekStartsOnMonday`, `weeklyTargetsRaw` (JSON string), `healthKitEnabled`, `defaultRestSeconds`, `schemaSeedVersion` | Linha única, criada no primeiro launch. |

**Decisões de esquema (e porquê)**

1. **`uuid` explícito em todo modelo**, com `@Attribute(.unique)` onde faz sentido. `PersistentIdentifier` do SwiftData não é estável entre aparelhos nem entre backup/restauração. Obs.: `.unique` é incompatível com CloudKit; como CloudKit está fora de escopo, aceitamos. Se um dia entrar, remove-se o `.unique` e dedup passa a ser feito no coordinator (que já dedupa por `uuid`).
2. **Enums e arrays guardados como `String` raw / CSV.** `#Predicate` não filtra por enum nem por array `Codable` de forma confiável; strings filtram. Propriedades computadas expõem os tipos ricos.
3. **Snapshots em vez de relações onde o histórico não pode mudar.** A sessão copia `programDayName`, `exerciseName` e a prescrição inteira. Editar o programa depois não reescreve o histórico. A relação com `ExerciseModel` existe só para navegação e nunca é `cascade`.
4. **`VersionedSchema` + `SchemaMigrationPlan` desde o dia 1**, mesmo com uma só versão. Adicionar `SchemaV2` depois é um arquivo novo, não uma refatoração.
5. **Um `ModelContainerFactory`** com dois modos: `.persistent` (app) e `.inMemory` (previews, testes). Nenhum outro lugar constrói `ModelContainer`.
6. **Sem `@Model` no relógio.** Ver §9.

**Mapeamento** (`Persistence/Mappers/`): funções puras `ExerciseModel → ExerciseDefinition`, `[SessionExerciseModel] → [ExerciseHistoryEntry]`, `WorkoutSessionModel → SessionSummary`. Só esse diretório conhece os dois lados.

## 6. Motor de treino (TrainerCore/Engine)

```swift
public protocol ProgressionRule: Sendable {
  func prescribe(target: ExerciseTarget, exercise: ExerciseDefinition,
                 history: [ExerciseHistoryEntry],   // ordenado do mais recente ao mais antigo
                 now: Date) -> ExercisePrescription
}
public struct DoubleProgressionRule: ProgressionRule { /* P1–P12 da SPEC */ }

public protocol WorkoutSelector: Sendable {
  func nextDay(program: ProgramTemplate, recentSessions: [SessionSummary], now: Date) -> ProgramDayTemplate
}
public struct RotationSelector: WorkoutSelector { /* S1–S4 */ }
// M4: FrequencyAwareSelector: WorkoutSelector { /* S5–S7 */ }, DeloadPolicy
```

- Funções puras; `now` é sempre parâmetro. Sem `Date()` dentro do motor.
- O motor recebe **histórico já filtrado por exercício** (o app faz a query); ele não sabe o que é banco.
- Testes são **casos de tabela**: cada regra da SPEC vira ao menos um caso nomeado (`P4_allSetsAtRepMax_increasesOneIncrement`). A SPEC é a fonte; se o teste e a SPEC divergem, corrige-se a SPEC ou o código, nunca só o teste.
- `SessionPlanner` (app) orquestra: seleciona o dia → para cada `ExerciseTarget`, busca histórico → `prescribe` → cria `WorkoutSessionModel` com snapshots. Só ele chama o motor.

## 7. Caminho de escrita: `SessionEvent` → `SessionCoordinator`

```swift
// TrainerCore/Sync/SessionEvent.swift
public struct SessionEvent: Codable, Sendable, Identifiable {
  public let id: UUID            // idempotência
  public let sessionID: UUID
  public let occurredAt: Date
  public let source: DeviceSource // .iphone / .watch / .importer
  public let kind: Kind
  public enum Kind: Codable, Sendable {
    case sessionStarted(programDayID: UUID)
    case setLogged(sessionExerciseID: UUID, setID: UUID, index: Int, load: Double, reps: Int, rir: Int?, isWarmup: Bool)
    case setUpdated(setID: UUID, load: Double, reps: Int, rir: Int?)
    case setDeleted(setID: UUID)
    case exerciseSkipped(sessionExerciseID: UUID)
    case exerciseSubstituted(sessionExerciseID: UUID, newExerciseID: UUID)
    case sessionFinished(endedAt: Date)
    case sessionAbandoned(endedAt: Date)
    case heartRateSummary(avg: Double, max: Double, hkWorkoutUUID: UUID?)
  }
}
```

`SessionCoordinator` (`@MainActor`, app iOS):

1. Recebe evento → verifica `appliedEventIDs` (tabela simples ou `Set` persistido em `UserDefaults` com janela de 30 dias) → ignora duplicata.
2. Aplica ao SwiftData → `try context.save()` **imediatamente** (RNF-03).
3. Publica em `eventsApplied` (`AsyncStream`) para que `WatchSyncService` reenvie o snapshot atualizado (M3) e `HealthKitService` reaja a `sessionFinished` (M2).

Regra de conflito (M3): `SetLogModel` identificado por `setID` gerado por quem registrou. `setUpdated` usa last-write-wins por `occurredAt`. Na prática, o usuário não registra a mesma série em dois aparelhos ao mesmo tempo; a regra existe para nunca travar.

## 8. HealthKit

| Fase | Quem roda a sessão de treino | Quem grava o `HKWorkout` | FC |
|------|------------------------------|--------------------------|----|
| M2 (só iPhone) | Ninguém (não existe `HKWorkoutSession` no iOS para força) | iPhone, via `HKWorkoutBuilder`, ao `sessionFinished` | Lida do HealthKit após o fim: amostras `heartRate` no intervalo `[startedAt, endedAt]`, gravadas passivamente pelo Watch se estava no pulso. |
| M3 (com Watch) | Watch, `HKWorkoutSession` + `HKLiveWorkoutBuilder` | Watch | Ao vivo no relógio; resumo enviado ao iPhone via `heartRateSummary`. |

**Invariante: exatamente um `HKWorkout` por sessão.** `WorkoutSessionModel.hkWorkoutUUID` é a trava. O `HealthKitService` do iPhone só grava se `hkWorkoutUUID == nil` **e** a sessão não tem `source == .watch` com sessão de treino ativa. Ao receber `heartRateSummary` com `hkWorkoutUUID`, o iPhone só armazena.

```swift
public protocol HealthKitServicing: Sendable {
  var isAvailable: Bool { get }
  func requestAuthorization() async throws
  func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) async throws -> UUID   // retorna HKWorkout.uuid
  func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary?
}
```

Tipos: escrita `HKWorkoutType`; leitura `heartRate`. Metadados do workout: `HKMetadataKeyExternalUUID = sessionUUID` (permite reconciliar e detectar duplicatas). `Info.plist`: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`. Entitlement HealthKit nos dois targets (definido em T0.1 mesmo sem uso, para não mexer em projeto depois).

`FakeHealthKitService` grava em memória e devolve FC sintética: é o que roda no simulador e nos previews.

## 9. Apple Watch (M3)

**Papel:** cliente fino da sessão ativa. Não planeja, não progride, não persiste histórico.

| Canal WCSession | Direção | Uso | Semântica |
|-----------------|---------|-----|-----------|
| `updateApplicationContext` | iPhone → Watch | `ActiveSessionSnapshot` (sessão inteira com prescrições e séries já feitas) | Só o último estado vale. Ideal para "qual é a sessão agora". |
| `transferUserInfo` | Watch → iPhone | `SessionEvent` (um por chamada) | Fila FIFO garantida, sobrevive a desconexão e a reboot. É por isso que o relógio funciona com o iPhone no armário. |
| `sendMessage` | ambos | Atalhos quando `isReachable` (ex.: "iniciou pelo relógio, mande o snapshot") | Best effort; sempre com fallback nos dois canais acima. |

**Snapshot** (`TrainerCore/Sync/ActiveSessionSnapshot.swift`): `schemaVersion`, `session` (ids, nome do dia, exercícios com prescrição e séries já registradas), `generatedAt`. Um campo `schemaVersion: Int` desde M0; o receptor rejeita versão maior que a conhecida e mostra "Atualize o app do iPhone".

**Persistência no relógio:** `ActiveSessionStore` grava o snapshot e a fila de eventos pendentes em JSON no `Application Support` do relógio. Sem SwiftData: evita um segundo esquema, uma segunda migração e um segundo conjunto de bugs num aparelho onde depurar é lento.

**Sessão de treino:** `WorkoutManager` inicia `HKWorkoutSession(activityType: .traditionalStrengthTraining)` ao começar a sessão. Isso dá FC ao vivo, mantém o app em primeiro plano/Always On e concede runtime em background (`WKBackgroundModes: workout-processing`). Ao finalizar: `builder.endCollection` → `finishWorkout` → envia `heartRateSummary(hkWorkoutUUID:)` ao iPhone.

**Iniciar pelo relógio:** o relógio envia `sessionStarted` via `transferUserInfo`; o iPhone planeja e devolve o snapshot. Enquanto não chega, o relógio mostra o último snapshot conhecido de "próximo treino" (o iPhone envia esse snapshot preventivamente toda vez que a Home é calculada). Assim o relógio consegue começar mesmo com o iPhone desligado, desde que tenha sido sincronizado ao menos uma vez após a última sessão.

**Reconciliação:** o iPhone aplica eventos do relógio pelo `SessionCoordinator` como qualquer outro; dedup por `event.id`. Depois de aplicar, reenvia snapshot. Se o relógio receber um snapshot que não contém uma série que ele já tem na fila, ele mantém a série local até o evento ser confirmado (`WCSessionUserInfoTransfer.isTransferring == false`).

## 10. Concorrência

- Tudo que toca SwiftData roda em `@MainActor` (contexto principal). Volume de dados de um usuário não justifica `ModelActor` em v1; se um dia a Home demorar > 100 ms, o `SessionPlanner` migra para `ModelActor` sem mudar sua API (retorna DTOs).
- `TrainerCore` é 100 % `Sendable`; o motor pode rodar em qualquer executor.
- Serviços `Live` de HealthKit e WCSession encapsulam callbacks em `async`/`AsyncStream`; delegates de WCSession saltam para `MainActor` antes de tocar no coordinator.
- Timer de descanso: `RestTimer` é `@Observable`, calcula com `endDate` (não com contagem de ticks), agenda `UNNotificationRequest` ao iniciar e cancela ao pular. Sobrevive ao app em segundo plano sem lógica extra.

## 11. Dados semente e configuração

- `Resources/Seed/exercises.v1.json` e `Resources/Seed/program-default.v1.json` no bundle do iPhone. Formato = os structs de `TrainerCore/Domain` (mesmo Codable do backup).
- `SeedLoader` roda no primeiro launch (`UserSettingsModel.schemaSeedVersion < bundle seed version`) e faz upsert por `slug`. Nunca sobrescreve exercícios editados pelo usuário (`isArchived`/notas preservados); só adiciona novos.
- Na M1 o programa é editado **no JSON** e reinstalando o app. É deliberado: elimina uma tela inteira do MVP.

## 12. Backup (M2)

`BackupService.export() -> BackupDocument` (Codable: catálogo, programas, sessões, séries, settings, `schemaVersion`). Exportado via `fileExporter` para o app Arquivos (pasta iCloud Drive do app, se houver — isso é sync "grátis" de backup sem CloudKit). Importação em instalação limpa: apaga tudo, insere, valida contagens. A importação reusa os DTOs de domínio; não há um segundo formato.

## 13. Estratégia de testes

| Camada | Ferramenta | O que cobre |
|--------|-----------|-------------|
| `TrainerCore` | Swift Testing, `swift test` (roda em qualquer SO com toolchain Swift) | Todas as regras P/S da SPEC como casos de tabela; determinismo (mesma entrada duas vezes); arredondamento; codificação/decodificação de DTOs de sync com versão. |
| Persistence | XCTest no simulador, container `.inMemory` | Migração V1 abre; mappers ida e volta; `SessionCoordinator` aplica cada `SessionEvent.Kind`; idempotência (mesmo evento duas vezes = uma série); cascade de exclusão. |
| Integração | XCTest | Loop completo: seed → planejar → 3 sessões simuladas → prescrição muda como esperado. |
| UI | Manual + previews com `Fake*` | Fluxo F1–F5 no simulador e no aparelho. Sem testes de UI automatizados em v1. |

## 14. Decisões anti-retrabalho (Watch e HealthKit)

| # | Decisão tomada em M0 | Retrabalho que evita |
|---|----------------------|----------------------|
| AR-1 | `TrainerCore` sem dependências Apple. | Reescrever/duplicar o domínio para o relógio. |
| AR-2 | `SessionEvent` + `SessionCoordinator` como único caminho de escrita, já com `source` e `id` de idempotência. | Refatorar toda a UI do iPhone quando o relógio começar a registrar séries. |
| AR-3 | `ActiveSessionSnapshot` e `schemaVersion` definidos e testados (codificação) em M0, mesmo sem consumidor. | Descobrir em M3 que o modelo de sessão não é serializável ou não tem ids estáveis. |
| AR-4 | `uuid` do cliente em todos os modelos; `SetLogModel.uuid` único. | Dedup e merge impossíveis com `PersistentIdentifier`. |
| AR-5 | `hkWorkoutUUID`, `avgHeartRate`, `maxHeartRate`, `sourceRaw` em `WorkoutSessionModel` desde `SchemaV1`. | Migração de esquema em M2 e M3 só para adicionar colunas. |
| AR-6 | `HealthKitServicing` protocolo + `Fake` em M0; entitlement e strings de Info.plist criados em T0.1. | Mexer em projeto/entitlements (área de conflito) depois; reescrever chamadas quando o gravador muda de iPhone para Watch. |
| AR-7 | Target do Watch criado vazio em T0.1, com background mode e entitlement. | Segunda rodada de edição do `.pbxproj` com risco de conflito. |
| AR-8 | `WatchSyncServicing` protocolo com `NoopWatchSync` em M0; o coordinator já publica `eventsApplied`. | Encaixar sync no coordinator depois de ele estar cheio de UI acoplada. |
| AR-9 | Motor recebe `now` e histórico como parâmetros. | Motor que lê o banco ou o relógio do sistema não roda no Watch nem em teste. |
| AR-10 | Snapshot de prescrição na sessão (não referência ao programa). | Edição de programa (M2) e troca automática (M4) corrompendo histórico. |

## 15. Riscos e mitigações

### SwiftData

| Risco | Mitigação |
|-------|-----------|
| Migração leve falha silenciosamente ou perde dados ao mudar campo/relação. | `VersionedSchema` desde V1; toda mudança = nova versão + teste que abre um store V(n−1) gravado em fixture; backup JSON antes de atualizar o app (M2). |
| `#Predicate` não suporta enum, arrays, `contains` complexo, optionals encadeados. | Enums como `String` raw; CSV para arrays; filtrar em memória quando o volume é pequeno (histórico de um exercício). |
| `@Model` não é `Sendable`; erros de concorrência em Swift 6. | Tudo `@MainActor`; DTOs cruzam fronteiras, modelos não. |
| `@Attribute(.unique)` com `insert` de duplicata faz **upsert** silencioso (sobrescreve). | Coordinator checa existência por `uuid` antes de inserir; testes de idempotência. |
| Relações opcionais/inversas mal declaradas causam crash em runtime, não em compile. | Um único arquivo `SchemaV1.swift`, revisado por checklist (inverso declarado nos dois lados, `deleteRule` explícito). |
| `@Query` re-renderiza a tela inteira em cada `save()` durante a sessão. | Sessão ativa lê do ViewModel (estado em memória alimentado pelo coordinator), não de `@Query`. `@Query` só em listas (histórico, catálogo). |
| Store corrompido = perda total (sem nuvem). | Export JSON (M2) e lembrete semanal opcional; store fica em `Application Support` incluído no backup do iCloud do iPhone. |

### HealthKit

| Risco | Mitigação |
|-------|-----------|
| Indisponível no simulador (sem FC) e no iPad. | `isHealthDataAvailable()` + `FakeHealthKitService`; toda a UI funciona com `nil` em FC. |
| Status de autorização de **leitura** é opaco (o sistema não revela negação). | Tratar "sem amostras" e "negado" igual: exibir "FC indisponível". Nunca bloquear fluxo por HealthKit. |
| Workouts duplicados (iPhone e Watch gravando). | Invariante `hkWorkoutUUID` (§8) + `HKMetadataKeyExternalUUID`. |
| `HKWorkoutSession` só existe no watchOS. | Não tentar FC ao vivo no iPhone em M2; ler passivamente depois. |
| Entitlement/plist esquecidos = crash ao pedir autorização. | Configurados em T0.1 e verificados no critério de aceitação de M0. |

### watchOS

| Risco | Mitigação |
|-------|-----------|
| `sendMessage` falha se o outro lado não está ativo; `updateApplicationContext` descarta intermediários. | Eventos sempre por `transferUserInfo`; estado sempre por `applicationContext`; `sendMessage` só como acelerador. |
| App do relógio suspenso no meio da sessão. | `HKWorkoutSession` ativa concede runtime e Always On. Sem ela, o app é suspenso em segundos. |
| Simuladores pareados instáveis; ciclo de build lento. | Toda lógica de sync em `TrainerCore` (testável sem relógio); UI do relógio mínima; testar em aparelho real. |
| Bateria em 90 min. | Usar apenas `HKLiveWorkoutBuilder` (taxa de FC gerenciada pelo sistema); sem polling; `TimelineView` com `isLuminanceReduced` para Always On. |
| Divergência de dados entre relógio e iPhone. | Relógio não tem banco; qualquer divergência se resolve reenviando o snapshot. |
| Entrada de dados pequena. | Digital Crown para carga (passo = `loadIncrement`) e reps; botões de 1 toque para RIR (0–4); confirmação única. |

### Gerais

| Risco | Mitigação |
|-------|-----------|
| Repositório dentro de OneDrive com acento e espaço no caminho. | Desenvolver no Mac em caminho ASCII sem espaços (ex.: `~/Developer/PersonalTrainer`); usar git, não OneDrive, para sincronizar. OneDrive corrompe `.git` com sincronizações parciais. |
| Conflito de `project.pbxproj` entre agentes paralelos. | Synchronized folders; `.pbxproj` só é editado em tarefas marcadas `[PROJ]` em TASKS.md, uma por vez. |
| Motor "esperto demais" cedo. | Regras P1–P8 fixas por 4 semanas de uso real antes de qualquer ajuste; mudanças só via SPEC + teste de tabela. |

## 16. ADRs (registro de decisões)

| ADR | Decisão | Alternativa rejeitada | Motivo |
|-----|---------|-----------------------|--------|
| 001 | iPhone fonte da verdade; Watch sem banco. | SwiftData + CloudKit nos dois aparelhos. | Sync de dois stores é a maior fonte de bugs possível num app pessoal; CloudKit adiciona latência, exige conta e proíbe `.unique`. |
| 002 | WatchConnectivity para sync. | Workout mirroring (iOS 17) como canal de dados. | Mirroring exige sessão de treino ativa nos dois lados e é menos documentado; WC cobre também o "próximo treino" fora de sessão. |
| 003 | Prescrição derivada do histórico a cada planejamento (sem tabela `ExerciseState`). | Cache de estado por exercício. | Histórico de um exercício são dezenas de linhas; derivar é barato e elimina inconsistência entre cache e histórico. |
| 004 | Só RIR persistido. | RIR e RPE. | Uma métrica, uma regra. RPE = 10 − RIR na exibição. |
| 005 | Strings pt-BR fixas. | String Catalog. | Um usuário, um idioma; `.xcstrings` é JSON que conflita em merge paralelo. |
| 006 | Programa editado em JSON na M1. | Tela de edição na M1. | Corta ~30 % do MVP sem afetar o objetivo (não pensar na academia). |
| 007 | `HKWorkoutBuilder` no iPhone em M2, migrando para o Watch em M3. | Esperar o Watch para gravar no HealthKit. | Entrega valor cedo; a migração é troca de quem chama `saveStrengthWorkout`, controlada pelo invariante `hkWorkoutUUID`. |

## 17. Estrutura de pastas prevista

```
PersonalTrainer/                        ← raiz do repo (no Mac: ~/Developer/PersonalTrainer)
├── SPEC.md · ARCHITECTURE.md · TASKS.md · AGENTS.md · README.md
├── PersonalTrainer.xcodeproj            [PROJ] criado em T0.1
├── Packages/
│   └── TrainerCore/
│       ├── Package.swift
│       ├── Sources/TrainerCore/{Domain,Engine,Sync,Summary}/
│       └── Tests/TrainerCoreTests/
├── PersonalTrainer/                     (target iOS — synchronized folder)
│   ├── App/            PersonalTrainerApp.swift · AppEnvironment.swift · RootView.swift
│   ├── Features/       Home/ · Session/ · History/ · Catalog/ · Program/ · Settings/
│   ├── Services/       SessionPlanner · SessionCoordinator · HealthKit/ · WatchSync/ · RestTimer/ · Seed/ · Backup/
│   ├── Persistence/    Schema/SchemaV1.swift · MigrationPlan.swift · ModelContainerFactory.swift · Mappers/ · Repositories/
│   ├── Resources/      Seed/*.json · Assets.xcassets
│   └── Support/        Info.plist · PersonalTrainer.entitlements
├── PersonalTrainerWatch/                (target watchOS — synchronized folder; vazio até M3)
│   ├── App/ · Features/ · Services/ · Support/
└── PersonalTrainerTests/
```

## 18. ADR 008 — Windows e validação gratuita em macOS hospedado

Decisão de 2026-09-22, decorrente da restrição explícita do usuário: manter Swift/HealthKit/Watch;
editar no Windows fora do OneDrive e compilar targets Apple em runner macOS padrão do GitHub.
A referência ao repositório no Mac em §17 descreve a alternativa anterior; a cópia de trabalho
atual fica em `C:\Users\leona\Developer\PersonalTrainer`. Não há Mac pessoal disponível.

T0.0 [PROJ][MAC-CI] precede a construção do app: um probe isolado, sem SwiftData, sem gravação
HealthKit, sem WCSession e sem dependência de TrainerCore. Não substitui as interfaces do produto.
Adiciona à estrutura de §17: `Validation/DeviceProbe/{Shared,iPhone,Watch,DeviceProbe.xcodeproj}`,
`.github/workflows/device-probe.yml`, `Scripts/build-device-probe.sh`,
`Scripts/check-device-probe.py` e `WINDOWS_SETUP.md`. O gerador do projeto usa Python padrão;
esta exceção de projeto isolado usa referências explícitas, não altera a decisão de pastas
sincronizadas do futuro projeto principal. Apple SDKs nunca são compilados no Windows.

CI: somente workflow_dispatch, timeout 20 min, sem credenciais Apple, sem dados de saúde e
artefato de um dia. Executar apenas com gasto excedente bloqueado em US$ 0; manter repo privado.
IPA recebe assinatura ad-hoc sem identidade Apple para carregar o entitlement HealthKit; exige
reassinatura/provisionamento local antes da instalação. A assinatura final deve preservar a
relação dos bundle IDs iPhone/Watch e o entitlement de ambos. Validar em hardware e na renovação
antes de anunciar suporte gratuito. Ferramenta experimental de instalação não é dependência do app.

As regras de domínio, camadas, idempotência e garantia de uma só gravação de treino permanecem
como definidas acima; não são implementadas nem substituídas pelo probe.
