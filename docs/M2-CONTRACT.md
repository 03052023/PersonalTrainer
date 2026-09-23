# Contrato do M2 (fonte única para agentes paralelos)

Escrito pelo arquiteto em 2026-09-23. Nomes aqui são **exatos**: agentes em paralelo escrevem contra eles sem ver o código uns dos outros. Se algo aqui contradiz a SPEC, pare e reporte.

## 1. TrainerCore (já em `main`)

- `ProgramGoal` (`hypertrophy`, `strength`, `endurance`, `longevity`, `combat`), `displayName`, `referenceTopic`.
- `MovementPattern` (20 cases, ver `Domain/MovementPattern.swift`), `displayName`.
- `ExerciseDefinition` ganhou `movementPattern: MovementPattern?` e `isCustom: Bool` (init com defaults; decodificação tolerante).
- `ProgramTemplate` ganhou `goal: ProgramGoal?`, `summary: String?`, `effectiveGoal`.
- `ScientificReference`, `ReferenceCatalog` (`references(for:)`, `topic(for: PrescriptionNote)`, `.empty`). Chaves de tópico documentadas no arquivo.

### A implementar no M2 (TrainerCore, testável no Windows)

- `Domain/GoalDefaults.swift`: `public struct GoalDefaults: Sendable, Hashable { compoundRepRange: ClosedRange<Int>; isolationRepRange: ClosedRange<Int>; targetRIR: Int; weeklySetsPerMuscle: ClosedRange<Int>; compoundRestSeconds: Int; isolationRestSeconds: Int; setsPerExercise: Int }` e `extension ProgramGoal { public var defaults: GoalDefaults }` (tabela SPEC §7.9) e `extension MovementPattern { public var isCompound: Bool }` (compostos: horizontalPush, verticalPush, horizontalPull, verticalPull, squat, lunge, hinge, hipThrust, carry, explosive).
- `Domain/ExerciseSubstitution.swift`: `public enum ExerciseSubstitution { public static func candidates(for exercise: ExerciseDefinition, in catalog: [ExerciseDefinition], excluding: Set<UUID> = [], limit: Int = 5) -> [ExerciseDefinition] }`.
- `Domain/ReferenceValidator.swift`: `public enum ReferenceValidator { public static func validate(_ catalog: ReferenceCatalog) throws }` + `public enum ReferenceValidationError`.
- Seed v2: `PersonalTrainer/Resources/Seed/exercises.v2.json`, `programs.v2.json`, `references.v1.json`. Os arquivos v1 são removidos.

## 2. SchemaV2 (app, `Persistence/Schema/SchemaV2.swift`)

Redeclara os 8 modelos de V1 (mesmos nomes, mesmos campos) e acrescenta, todos com valor padrão na declaração para migração leve:

| Modelo | Campo novo | Tipo / padrão | Computed exposto |
|--------|-----------|---------------|------------------|
| `ExerciseModel` | `movementPatternRaw` | `String? = nil` | `movementPattern: MovementPattern?` |
| `ExerciseModel` | `isCustom` | `Bool = false` | — |
| `ProgramModel` | `goalRaw` | `String = "hypertrophy"` | `goal: ProgramGoal?` |
| `ProgramModel` | `summary` | `String? = nil` | — |
| `SessionExerciseModel` | `prescribedTargetReps` | `Int = 0` (0 = desconhecido → usar `prescribedRepMin`) | — |
| ~~`UserSettingsModel`~~ | ~~`hasCompletedOnboarding`~~ | removido: onboarding usa `@AppStorage("hasCompletedOnboarding")` | — |

- `MigrationPlan`: `schemas = [SchemaV1.self, SchemaV2.self]`, `stages = [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]`.
- `CurrentSchema.swift`: typealiases passam a apontar para `SchemaV2.*`; `typealias CurrentSchema = SchemaV2`.
- Inits dos modelos V2: mesmos parâmetros de V1 **mais** os novos, todos com default no fim da lista (call sites existentes continuam compilando).
- `SeedLoader.currentSeedVersion = 2`; recursos `exercises.v2` e `programs.v2`; política v2: upsert de exercícios por slug (preserva `machineNotes`, `isArchived`, e nunca toca `isCustom == true`); insere cada programa do seed cujo `uuid` ainda não existe, **inativo** se já houver programa ativo; nunca altera programas existentes. Primeiro launch: o programa marcado `isActive` no seed fica ativo.

## 3. Protocolos do app (já em `main`)

- `SessionCoordinating`: novos requisitos `deleteSession(id:)`, `substituteExercise(sessionID:sessionExerciseID:with:now:)` (padrão lança `.unsupported`). `SessionCoordinatorError.unsupported`.
- `SessionPlanning`: `activeProgramDays()`, `activeProgramGoal()`, `substitutionPlan(replacing:target:newExerciseID:now:)`, `substitutes(for:limit:)`.
- `HealthKitServicing`: `findOverlappingStrengthWorkout(start:end:)`.
- `ProgramRepositoring` + `ProgramRepositoryError` + `ProgramLimits` (Persistence/Repositories).
- `CatalogRepositoring` + `ExerciseDraft` + `CatalogRepositoryError`.
- `BackupServicing` + `BackupImportReport` + `BackupError` (Services/Backup).

## 4. Tipos concretos a criar (nomes exatos)

| Tipo | Arquivo | Init |
|------|---------|------|
| `ProgramRepository: ProgramRepositoring` | Persistence/Repositories/ProgramRepository.swift | `init(modelContext: ModelContext)` |
| `CatalogRepository: CatalogRepositoring` | Persistence/Repositories/CatalogRepository.swift | `init(modelContext: ModelContext)` |
| `BackupService: BackupServicing` | Services/Backup/BackupService.swift | `init(modelContext: ModelContext)` |
| `LiveHealthKitService: HealthKitServicing` | Services/HealthKit/LiveHealthKitService.swift | `init()` |
| `HealthKitWorkoutRecorder` (`@MainActor final class`) | Services/HealthKit/HealthKitWorkoutRecorder.swift | `init(healthKit: any HealthKitServicing, coordinator: any SessionCoordinating)`; `func start()` inicia uma `Task` que consome `coordinator.eventsApplied`; em `sessionFinished`: se `hkWorkoutUUID == nil`, pede autorização (1ª vez), procura treino sobreposto, vincula ou grava, lê `heartRateSummary` e aplica `heartRateSummary(...)` via `coordinator.apply`. Falhas só logam. |
| `ReferenceLibrary` (`enum`) | Services/References/ReferenceLibrary.swift | `static func load(bundle: Bundle) -> ReferenceCatalog` (lê `references.v1.json`, valida, devolve `.empty` em falha e loga) |

## 5. Views compartilhadas (nomes exatos)

| View | Dono | Assinatura |
|------|------|-----------|
| `WhySheet` | Features/References/WhySheet.swift (T2.18) | `init(topic: String, catalog: ReferenceCatalog)` — título, explicação de `catalog.explanations[topic]`, lista de referências (autores, ano, título, fonte, nível, link DOI com `Link`). Vazio → "Sem referências para este item." |
| `WhyButton` | Features/References/WhyButton.swift (T2.18) | `init(topic: String, catalog: ReferenceCatalog)` — botão pequeno `Label("Por quê?", systemImage: "questionmark.circle")` que apresenta `WhySheet` em `.sheet`. Esconde-se se `catalog.references(for: topic)` está vazio. |
| `ExercisePickerView` | Features/Catalog/ExercisePickerView.swift (T2.5) | `init(exercises: [ExerciseDefinition], title: String, highlighted: [ExerciseDefinition] = [], onPick: @escaping (ExerciseDefinition) -> Void, onCancel: @escaping () -> Void)` — `NavigationStack` com busca por nome, seção "Sugeridos" (os `highlighted`, ex.: substitutos) e seções por grupo primário. |

## 6. AppEnvironment (integrador)

Ganha: `programs: any ProgramRepositoring`, `catalog: any CatalogRepositoring`, `backup: any BackupServicing`, `references: ReferenceCatalog`, `healthRecorder: HealthKitWorkoutRecorder?`. `live()` usa `LiveHealthKitService()` quando `isAvailable`, senão `FakeHealthKitService()`.

## 7. Navegação (integrador)

`TabView`: **Treino** (Home), **Histórico**, **Programa** (lista de programas + editor + catálogo), **Ajustes** (backup, sobre/referências). Primeiro launch com `@AppStorage("hasCompletedOnboarding") == false`: sheet de onboarding para escolher objetivo e formato (Features/Program/OnboardingView.swift).
