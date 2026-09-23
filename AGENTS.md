# AGENTS — Regras para agentes de código (Claude Code, Codex e humanos)

Versão 0.1 · 2026-09-22. Vale para qualquer agente que edite este repositório.

## 1. Leia nesta ordem antes de qualquer tarefa

1. [SPEC.md](SPEC.md) §7 (regras de domínio) — é a fonte de verdade do comportamento.
2. [ARCHITECTURE.md](ARCHITECTURE.md) §3 (dependências), §5 (esquema), §7 (caminho de escrita), §14 (anti-retrabalho).
3. [TASKS.md](TASKS.md) — a tarefa que você vai executar, seu **Escopo** e suas **dependências**.
4. Este arquivo.

Se algo na tarefa contradiz a SPEC ou a ARCHITECTURE, **pare e reporte**; não "resolva" escolhendo um lado em silêncio.

## 2. Ambiente

- **Não existe Mac.** A máquina de desenvolvimento é Windows 11; o código do app (iOS/watchOS) só compila no GitHub Actions (runner `macos-26`, projeto gerado por XcodeGen). Tarefas marcadas **[CI]** em TASKS.md produzem código que você não consegue compilar: siga a regra R11.
- `Packages/TrainerCore` é Swift puro e compila/testa localmente. No Windows use **somente** `powershell -ExecutionPolicy Bypass -File Scripts/swift-test.ps1` (carrega o Visual Studio 2022 e o SDK do Swift 6.4; aceita `-Filter <regex>` e `-Build`). Chamar `swift` direto falha. No CI Linux, o job "Core tests" roda `swift test` em `container: swift:6.3`.
- Repositório canônico: `C:\Users\leona\Developer\PersonalTrainer`. Não desenvolva dentro de OneDrive/iCloud Drive: eles corrompem `.git`. Agentes em paralelo trabalham em **worktrees** separados (um `.build` por worktree); nunca rode `swift test` em dois processos sobre o mesmo diretório.
- Sem dependências externas no app (SwiftPM de terceiros, CocoaPods). XcodeGen é ferramenta de build instalada só no runner. Se achar que precisa de outra, reporte em vez de adicionar.
- Nunca manipule credenciais Apple ou GitHub: o usuário digita tudo nas ferramentas dele. Ver [WINDOWS_SETUP.md](WINDOWS_SETUP.md).

## 3. Regras invioláveis

| # | Regra | Como verificar |
|---|-------|----------------|
| R1 | `Packages/TrainerCore` só importa `Foundation`. | `Scripts/check-boundaries.sh` (T0.10) ou `grep -rE "import (SwiftData|HealthKit|UIKit|SwiftUI|WatchConnectivity|WatchKit)" Packages/TrainerCore/Sources` deve retornar vazio. |
| R2 | Nenhuma métrica de frequência cardíaca entra em `ProgressionRule`, `WorkoutSelector`, `DeloadPolicy`. A struct `SetResult` e `ExerciseHistoryEntry` não ganham campo de FC. | Revisão de PR; grep por `heartRate` em `TrainerCore/Engine` deve retornar vazio. |
| R3 | O motor não chama `Date()`. `now` é parâmetro. | grep por `Date()` em `TrainerCore/Engine` retorna vazio. |
| R4 | Views não escrevem no `ModelContext`. Escrita de sessão só via `SessionCoordinator.apply(SessionEvent)`; catálogo/programa só via `*Repository`. | grep por `modelContext.insert\|modelContext.delete\|\.save()` em `PersonalTrainer/Features` retorna vazio. |
| R5 | `project.yml`, `.github/workflows/*`, `*.entitlements` e `Scripts/build-*.sh` só em tarefas **[PROJ]**. `Persistence/Schema/` só em tarefas **[SCHEMA]**. Uma por vez. `*.xcodeproj` e `Info.plist` são gerados e não entram no Git. | Se sua tarefa não tem a tag, não toque nesses arquivos. Se precisar, pare e reporte. |
| R6 | Toda mudança de esquema SwiftData = novo `SchemaVN.swift` + estágio no `MigrationPlan` + teste que abre fixture da versão anterior. Nunca editar `SchemaV1` depois de M0 fechar. | Revisão de PR. |
| R7 | Toda regra de negócio nova ou alterada começa na SPEC (tabela P/S/D numerada) e tem ao menos um teste de tabela com o nome da regra. | O PR toca `SPEC.md` **e** um `*Tests.swift`. |
| R8 | Identificadores estáveis são `UUID` gerados no cliente. Nunca usar `PersistentIdentifier` fora de `Persistence/`. | grep por `PersistentIdentifier` fora de `Persistence/` retorna vazio. |
| R9 | Serviços com efeito externo (HealthKit, WCSession, notificações) têm protocolo + `Live` + `Fake`. Previews e testes usam `Fake`. | Revisão de PR. |
| R10 | Não implementar além do escopo da tarefa. Se notar algo fora do escopo, anote em "Achados" no PR; não conserte. | Diff do PR contém só arquivos do **Escopo** da tarefa. |
| R11 | Código **[CI]** (app iOS/watchOS) é escrito sem compilador. Use só APIs que conhece com certeza (iOS 18 SDK), prefira a forma mais simples e documentada, releia cada arquivo inteiro após editar e entregue uma lista explícita de **incertezas** (o que só o CI vai confirmar). Nada de `fatalError`/`try!`/força-unwrap fora de testes. | O PR lista "Verificado" e "Incerto"; um revisor estático adversarial roda antes do merge; o primeiro run do CI fecha a tarefa. |

## 4. Convenções de código

- **Swift 6 language mode**, strict concurrency. `TrainerCore`: tudo `struct`/`enum`, `Sendable`, sem classes. App: ViewModels são `@Observable final class` marcados `@MainActor`.
- **Nomes em inglês** no código (tipos, funções, arquivos). **Textos de UI em pt-BR**, fixos no código, em `Text("Concluir série")`. Sem `Localizable.strings`, sem `.xcstrings`.
- Um tipo público por arquivo; nome do arquivo = nome do tipo. Extensões grandes em `Tipo+Assunto.swift`.
- Pastas seguem ARCHITECTURE §17. Não crie pastas novas de topo sem atualizar ARCHITECTURE §17 no mesmo PR.
- Unidades: carga sempre `Double` em kg (ou placas/nível conforme `LoadUnit`), tempo em segundos `Int`, datas `Date` em UTC; formatação só na View.
- Enums persistidos: `String` `rawValue` estável em inglês; nunca renomear um case existente (adicione outro e migre).
- Erros: tipos `enum XError: Error` por serviço; nunca `fatalError` fora de precondições de programação; falha de HealthKit/WCSession nunca interrompe o fluxo da sessão.
- Logs: `os.Logger` com `subsystem = bundle id`, `category` = nome do serviço. Sem `print`.
- Testes: Swift Testing em `TrainerCore` (`@Test("P4 …")`), XCTest no app. Nome do teste começa pela regra da SPEC quando aplicável: `P6_secondConsecutiveFailureSameLoad_decreases`.
- Comentários explicam **porquê**, não o quê. Referencie a regra: `// SPEC P6`.

## 5. Fluxo de trabalho por tarefa

1. **Reivindicar**: mude o status em TASKS.md para `[~] <agente> · <branch>` em um commit só com essa linha. Branch: `task/T1.6-set-entry-view`.
2. **Confirmar escopo**: liste os arquivos que vai criar/editar. Se algum está fora do **Escopo** da tarefa ou pertence a uma tarefa `[~]` de outro agente, pare e reporte.
3. **Implementar** com testes. Rode o que der: `swift test` no pacote; `xcodebuild test` no Mac.
4. **Verificar R1–R10** (greps acima) antes de abrir PR.
5. **PR** com título `T1.6: componente de registro de série`, corpo: o que fez, como testou, critérios de aceitação cobertos (`CA1-3 parcial`), achados fora de escopo.
6. **Fechar**: após merge, status `[x]` e, se todos os CAs do milestone estão verificados, anote a data no cabeçalho do milestone.

Conflito em TASKS.md é sempre de uma linha de status; resolva mantendo as duas alterações.

## 6. Mapa de propriedade (quem pode tocar em quê)

| Área | Dono típico | Paralelizável com |
|------|-------------|-------------------|
| `Packages/TrainerCore/Domain` | T0.2 e depois só tarefas que adicionam tipos novos | Tudo, desde que só adicione arquivos |
| `Packages/TrainerCore/Engine` | Uma tarefa de motor por vez (T0.3, T0.4, T2.8, T4.x) | UI, Persistence |
| `Packages/TrainerCore/Sync` | T0.7, T3.2 | Tudo exceto entre si |
| `Persistence/Schema` | **[SCHEMA]** exclusiva | Nada dentro da pasta |
| `Persistence/Mappers`, `Repositories` | T0.9, T2.5, T2.6 | UI, Engine |
| `Services/Session` (Coordinator) | T1.3; depois só com tarefa explícita | UI |
| `Services/*` outros | Uma tarefa por subpasta | Entre subpastas |
| `Features/<Nome>` | Uma tarefa por feature | Outras features |
| `PersonalTrainerWatch/**` | Tarefas T3.x | Tudo do iPhone |
| `project.yml`, `.github/workflows/`, `Scripts/build-*.sh`, `*/Support/*.entitlements` | **[PROJ]** exclusiva | Nada |
| `Validation/DeviceProbe/**` | T0.0 apenas (probe isolado; não é o app) | Tudo |
| `Scripts/swift-test.ps1`, `Scripts/check-boundaries.sh` | Infra; mudar só com motivo e em tarefa própria | — |
| `SPEC.md`, `ARCHITECTURE.md` | Qualquer tarefa que mude regra/desenho, na mesma PR | — (conflitos são raros e textuais) |

## 7. O que NÃO fazer

- Não adicionar CloudKit, iCloud sync, contas, backend, analytics, pacotes de terceiros.
- Não colocar SwiftData no target do Watch.
- Não usar FC para carga, volume, deload ou seleção de treino, nem "só como desempate".
- Não criar `ExerciseState` ou cache de progressão persistido; a prescrição é derivada do histórico (ADR 003).
- Não localizar strings, não criar `.xcstrings`.
- Não "melhorar" a regra de progressão dentro de uma tarefa de UI. Regras mudam via SPEC + teste, em tarefa própria.
- Não editar arquivos de outra tarefa em andamento. Não refatorar o que não está no seu escopo.
- Não usar `Task.sleep` como sincronização em testes; use expectativas/`AsyncStream`.
- Não pedir permissão de HealthKit ou notificações no launch; só na primeira ação que precisa.
- Não usar capabilities indisponíveis na conta Apple gratuita: Push Notifications, iCloud/CloudKit, Siri, Sign in with Apple, Associated Domains, NFC. Um entitlement desses faz a assinatura local falhar.
- Não alterar bundle IDs (`com.personaltrainer.app`, `com.personaltrainer.app.watchkitapp`) nem adicionar extensões/widgets: cada App ID consome a cota semanal da conta gratuita.
- Não rodar `swift test` diretamente nem em dois worktrees ao mesmo tempo no mesmo diretório (ver §2).

## 8. Modelo de prompt para delegar uma tarefa

```
Você vai executar a tarefa <ID> de TASKS.md no repositório PersonalTrainer.
Leia SPEC.md §7, ARCHITECTURE.md §3/§5/§7/§14 e AGENTS.md antes.
Escopo permitido: <lista de arquivos da tarefa>. Não toque em nada fora dele.
Dependências já concluídas: <IDs>. Não recrie o que elas entregaram; importe.
Entregue: código + testes + verificação R1–R10 + PR no formato do AGENTS.md §5.
Se encontrar contradição entre documentos ou precisar de arquivo fora do escopo, pare e reporte.
```

## 9. Definição de pronto (DoD) para qualquer tarefa

- [ ] Compila (`swift build` ou `xcodebuild`) sem warnings novos.
- [ ] Testes da tarefa passam; testes existentes continuam passando.
- [ ] R1–R10 verificados.
- [ ] Só arquivos do escopo no diff.
- [ ] Critérios de aceitação cobertos listados no PR.
- [ ] Se mudou regra ou desenho: SPEC/ARCHITECTURE atualizados na mesma PR.
- [ ] Status em TASKS.md atualizado.
