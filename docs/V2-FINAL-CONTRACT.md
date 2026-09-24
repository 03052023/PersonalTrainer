# Contrato da rodada final da versão 2 (ondas 2 e 3)

Versão 1 · 2026-09-23. Base: `main` 818d007 (M2 + correções, M4/M5 core verdes no CI, App build verde no run 35945596092). Regras de domínio em SPEC §7.5, §7.8, §7.9, §7.10 e §7.11; convenções em AGENTS.md.

## 0. Como testar sem compilador local

O Smart App Control bloqueia o toolchain Swift nesta máquina (erro 4551). Não altere essa configuração.
- **TrainerCore:** faça commit, depois `git push origin <seu-branch>` (antes, no PowerShell: `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"`). O workflow "Core tests" roda sozinho em push que toca `Packages/**` ou `PersonalTrainer/Resources/Seed/**`. Para esperar o resultado e ler os erros (as anotações são públicas):
  `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\watch-ci.ps1 -Sha <commit completo> -Minutes 25 -Expected 1`
- **App (iOS):** um push para um branch `ci/<nome>` roda o "App build" (xcodegen, testes no simulador, IPA) em 20–30 min, com erros publicados como anotações. Use `-Expected 2` quando o push também tocar o TrainerCore.
- Swift 6.3 no Linux: em `@Test(arguments:)`, use constantes com tipo explícito (`static let cases: [Caso] = [...]`), nunca literais de tupla com membros implícitos.

## 1. Onda 2 — TrainerCore (quatro tarefas paralelas, escopos disjuntos)

### 1.1 `v2/deload-scheduler` — Engine/DeloadScheduler (SPEC §7.5 rearme, §7.11 C1)

Arquivos: `Packages/TrainerCore/Sources/TrainerCore/Engine/DeloadScheduler.swift`, `Engine/DeloadStatus.swift`, `Domain/DeloadDecisions.swift`, `Tests/TrainerCoreTests/DeloadSchedulerTests.swift`. Não altere `DeloadPolicy` (a não ser para corrigir bug provado por teste, com nota no relatório).

```swift
/// Decisões do usuário sobre deload, persistidas pelo app em JSON (não em SwiftData).
public struct DeloadDecisions: Codable, Sendable, Hashable {
    public var manualRequestedAt: Date?   // (c) "Fazer semana leve agora"
    public var dismissedAt: Date?         // "Seguir normal" no C1: adia os gatilhos (a)/(b)
    public init(manualRequestedAt: Date? = nil, dismissedAt: Date? = nil)
}

public enum DeloadStatus: Sendable, Hashable {
    case inactive
    /// O próximo plano deve ser deload; nenhuma sessão de deload começou ainda.
    case pending(trigger: DeloadTrigger)
    /// Passagem de deload em andamento, iniciada em `start` (startedAt da 1ª sessão de deload).
    case active(start: Date)
}

public enum DeloadScheduler {
    public static func status(
        normalPrescriptions: [ExercisePrescription],   // prescrição normal (sem deload) de cada exercício do programa ativo
        histories: [UUID: [ExerciseHistoryEntry]],      // por exerciseID, qualquer ordem
        sessions: [SessionSummary],                     // todas as sessões conhecidas, qualquer ordem
        programDayCount: Int,
        decisions: DeloadDecisions,
        weeksBetweenDeloads: Int = DeloadPolicy.defaultWeeksBetweenDeloads,
        now: Date
    ) -> DeloadStatus
}
```

Semântica a fixar em testes de tabela (nome do teste começa pela regra: `C1_…`, `D_rearm_…`):
- **Execução de deload** = sessões com `isDeload`. O início do deload corrente é o `startedAt` da primeira sessão de deload da sequência mais recente (sequência = sessões de deload sem sessão normal concluída com série de trabalho entre elas). Se `DeloadPolicy.isDeloadActive` diz que a passagem não terminou → `.active(start:)`.
- **Fim do último deload** = `startedAt` da sessão que completou a passagem (a última de deload da sequência).
- **Rearme (a):** uma prescrição com `decrease` só conta se a entrada mais recente não-deload do histórico daquele exercício é posterior ao fim do último deload **e** a `dismissedAt`. As demais são tratadas como não-redução na contagem.
- **(b):** a referência de tempo é o mais recente entre início do último deload e `dismissedAt`; sem nenhum dos dois, a primeira sessão.
- **Manual:** `manualRequestedAt` posterior ao início do último deload (ou sem deload) e sem sessão de deload desde o pedido → `.pending(.manual)`.
- Prioridade: `.active` > manual > (a) > (b). Programa sem dias → `.inactive`. Determinístico: a ordem da entrada não importa.

### 1.2 `v2/coach-core` — pasta nova `TrainerCore/Coach` (SPEC §7.11 C1–C8)

Arquivos: `Packages/TrainerCore/Sources/TrainerCore/Coach/*.swift`, `Tests/TrainerCoreTests/Coach*Tests.swift`, e a linha da pasta `Coach/` em ARCHITECTURE.md §17. Consome tipos existentes (`ReviewReport`, `ProgramSuggestion`, `HealthSuggestion`, `PersonalRecord`, `ProgramGoal`). Não depende de `DeloadScheduler`: recebe o status já calculado como `CoachDeloadState`.

```swift
public enum CoachRule: String, Codable, CaseIterable, Sendable { case deload, review, health, installExpiry, comeback, personalRecord, backup, longevity } // C1…C8
public enum CoachAction: String, Codable, Sendable { case ok, keepNormal, apply, notNow, neverAgain, understood, remindTomorrow, howToRenew, start, seeProgress, backupNow, later, done, skip }
public enum CoachDeloadState: Sendable, Hashable { case none; case scheduled(trigger: DeloadTrigger, since: Date); case running(start: Date) }

public struct CoachMessage: Identifiable, Codable, Sendable, Hashable {
    public let id: String             // estável e com o período: "deload:2026-09-21", "health:vo2Stale:2026-09-23", "expiry:2026-09-30"
    public let rule: CoachRule
    public let itemKey: String        // alvo de "Não sugerir mais isto" (silencia rule+itemKey)
    public let title: String          // pt-BR, voz do DESIGN.md §6 (sem jargão de academia)
    public let reason: String         // uma frase com os números
    public let referenceTopic: String? // chave do references.v1.json, ou nil (C4, C7)
    public let actions: [CoachAction]
    public let priority: Int          // menor = mais importante; C4 e C1 no topo
    public let highlightsOnLaunch: Bool
    public let suggestionID: String?  // C2: ProgramSuggestion.id; C6: exerciseID
}

public struct CoachLogEntry: Codable, Sendable, Hashable { public let messageID: String; public let rule: CoachRule; public let itemKey: String; public let action: CoachAction; public let date: Date }
public struct CoachLog: Codable, Sendable, Hashable {
    public var entries: [CoachLogEntry]
    public var lastReviewAt: Date?
    public init(entries: [CoachLogEntry] = [], lastReviewAt: Date? = nil)
    public mutating func record(_ message: CoachMessage, action: CoachAction, at date: Date)
}

public struct CoachInput: Sendable {
    public var deload: CoachDeloadState
    public var review: ReviewReport?                // só quando a revisão está vencida (ReviewSchedule)
    public var healthSuggestions: [HealthSuggestion]
    public var provisioningExpiry: Date?
    public var lastSessionStart: Date?
    public var nextDayName: String?
    public var personalRecords: [PersonalRecord]    // da última sessão concluída
    public var exerciseNames: [UUID: String]
    public var lastBackupAt: Date?
    public var completedSessionCount: Int
    public var goal: ProgramGoal?
    public var longevityDoneThisWeek: Set<String>   // "balance", "mobility"
    // init público com valores padrão vazios/nil
}

public enum CoachFeedBuilder {
    public static func feed(input: CoachInput, log: CoachLog, now: Date, calendar: Calendar) -> [CoachMessage]
}
public enum ReviewSchedule {
    public static let defaultIntervalWeeks = 4
    public static func isDue(lastReviewAt: Date?, firstSessionAt: Date?, now: Date, intervalWeeks: Int = defaultIntervalWeeks) -> Bool
}
public enum ProvisioningProfileParser {
    /// Extrai `ExpirationDate` do plist XML embutido no CMS do `embedded.mobileprovision`.
    /// Procura "<?xml" … "</plist>" nos bytes e usa PropertyListSerialization. nil se não achar.
    public static func expirationDate(from data: Data) -> Date?
}
```

Regras (uma linha de teste por fronteira):
- Cadências da tabela SPEC §7.11. Uma mensagem respondida com qualquer ação some; o período no `id` controla quando a mesma regra volta.
  - C3: no máximo 1 por tipo a cada 3 dias; "Lembrar amanhã" reaparece no dia seguinte.
  - C4: a partir de 2 dias antes da expiração, uma por dia.
  - C5: ≥ 6 dias sem sessão; a partir de 21 dias, avisa que as cargas vêm reduzidas (P9).
  - C7: backup há ≥ 14 dias, ou nunca feito com ≥ 5 sessões; uma por semana.
  - C8: só com objetivo Longevidade, uma por semana, se equilíbrio ou mobilidade não foram marcados.
- `neverAgain` silencia rule+itemKey para sempre.
- Tópicos: C1 `rule.D`; C2 o `referenceTopic` da sugestão; C3 o da sugestão de saúde; C5 `rule.P9`; C6 `topic.e1rm`; C8 `goal.longevity`; C4 e C7 nil.
- Ordem estável: prioridade, depois `id`.

### 1.3 `v2/seed-fullbody` — programa Completo corpo todo (SPEC §7.9, decisão 8)

Arquivos: `PersonalTrainer/Resources/Seed/programs.v2.json`, `Packages/TrainerCore/Tests/TrainerCoreTests/SeedBundleTests.swift` e, se o esquema de seed exigir, `Domain/SeedValidator.swift` (só validação). Leia `PersonalTrainer/Services/Seed/SeedLoader.swift` para saber como o seed chega a um store que já tem dados.
- Instalações novas: o programa padrão (ativo) de hipertrofia é corpo todo: 3 dias, 5 exercícios por dia, cada grande grupo 2×/semana, compostos com 4 séries e isolados com 3. Faixas, RIR e descanso seguem §7.9.
- Quem vem da M1 (o usuário real) não pode perder nada. O histórico é por exercício, então trocar de programa preserva as cargas. Nenhum programa existente no store pode ser sobrescrito sem o usuário pedir. Se o id do "Completo" atual coincide com o programa da M1, crie o corpo todo com **id novo** e deixe o A/B/C existente intacto (renomeado no seed só se o loader não sobrescrever o do usuário). Documente a escolha no relatório.
- Foco inferior e foco superior: revise pela mesma lógica (grupo em foco 2×/semana e perto do topo da faixa, o resto em manutenção), dentro de 5 exercícios por dia.
- Rode também o App build, com push para `ci/seed-fullbody`: `SeedLoaderTests` e `FullLoopTests` do app leem o seed.

### 1.4 `v2/references` — catálogo (RF-32)

Arquivos: `PersonalTrainer/Resources/Seed/references.v1.json`, `Packages/TrainerCore/Tests/TrainerCoreTests/ReferenceCatalogTests.swift`.
- Criar os tópicos `topic.sleep` (consenso AASM/SRS; Watson 2015), `topic.steps` (Paluch 2022) e `topic.e1rm` (Epley; validade das equações de 1RM estimado). Cada um com explicação de 1 a 3 frases e ≥ 2 fontes quando houver.
- Acrescentar FRIEND 2015 (Kaminsky, doi 10.1016/j.mayocp.2015.07.026) em `topic.vo2max`, e Tanaka 2001 (10.1016/S0735-1097(00)01054-8), ACSM 2011 (Garber, 10.1249/MSS.0b013e318213fefb) e OMS 2020 (Bull, 10.1136/bjsports-2020-102955) em `topic.aerobic` e onde couber (`goal.longevity`).
- Conferir todo DOI novo em `https://api.crossref.org/works/<doi>`: título, primeiro autor e ano. Não inventar nada. `ReferenceValidator` precisa continuar passando.

## 2. Onda 3 — app (depois da onda 2; implementadores em pastas disjuntas + integrador único)

| Tarefa | Pasta dona | Entrega |
|---|---|---|
| Saúde | `Features/Health`, `Services/Health` | mesclar `m5/health-reader` e `m5/health-ui`; `HealthViewModel` recebe `HealthDataReading` |
| Planejador | `Services/Planning`, `Services/Decisions` | `DeloadScheduler` + `DeloadPolicy.deloadPrescription` + `FrequencyAwareSelector` (chave em Ajustes; padrão ligado com ≥ 4 dias) no `SessionPlanner`; `SessionPlan.isDeload` e `reason`; `DeloadDecisionsStore` (JSON em Application Support) |
| Diálogo | `Features/Coach`, `Services/Coach` | `CoachLogStore` (JSON), `ProvisioningExpiryReader` (Bundle `embedded.mobileprovision` → parser do core) + notificação local na véspera, execução da revisão quando `ReviewSchedule.isDue`, aplicar `ProgramSuggestion` via `ProgramRepositoring`, `PersonalRecordDetector` ao concluir a sessão |
| Dias D/E | `Features/Program` | T2.22: adicionar/remover/renomear/reordenar dias (1–7) pelo `ProgramRepositoring` |
| Design | `Features/DesignSystem` (nova), `Resources/Assets.xcassets/AccentColor.colorset` | tokens do DESIGN.md §3, `FlowerView` (a flor com a pétala do objetivo), troca de símbolos (§8) |
| Integrador | `App/*`, `Features/Home/*`, `Features/Settings/*` | liga tudo: Home com objetivo + flor no topo, cartão de hoje e botão **Começar**, feed do diálogo, cartão de Saúde; aba **Hoje** (`sun.max`); Ajustes com as chaves novas |
