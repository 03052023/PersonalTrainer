# PersonalTrainer

**Magister**: app de treino de força e cardio para iPhone, com lançamento planejado na App Store do Brasil. É uma ferramenta de organização e acompanhamento de treino, baseada em estudos publicados: diz o treino do dia (exercícios, séries, repetições, cargas), registra o resultado e recalcula o próximo treino de forma determinística. Os dados ficam no aparelho. O app do Apple Watch está planejado para o M3.

| Documento | Conteúdo |
|-----------|----------|
| [SPEC.md](SPEC.md) | Produto, fluxos, requisitos e **regras de domínio** (progressão, seleção, deload, política de FC). |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Targets, camadas, modelos de dados, motor, sync Watch, HealthKit, riscos, ADRs. |
| [TASKS.md](TASKS.md) | Milestones com critérios de aceitação e tarefas pequenas para execução paralela. |
| [AGENTS.md](AGENTS.md) | Regras para Claude Code, Codex e humanos que editam o repositório. |

## Ambiente atual

Windows 11, sem Mac. iPhone 17 (iOS 26.6.2) e Apple Watch Series 7 (watchOS 26.5), conta Apple gratuita (hoje, na cópia de teste).
Builds Apple no GitHub Actions (`macos-26`, Xcode 26.6, projeto gerado por XcodeGen); a cópia de teste é instalada por sideload no Windows: roteiro e riscos em [WINDOWS_SETUP.md](WINDOWS_SETUP.md).
A partir da 2.5 (SPEC §7.18, decisão 22), a distribuição passa a ser pela App Store, com a conta paga do Apple Developer Program; o sideload fica só para testes.

## Estado (2026-09-22)

- [x] Documentação (SPEC, ARCHITECTURE, TASKS, AGENTS) alinhada com a implementação.
- [x] `TrainerCore`: domínio, motor de progressão (P1–P12), rotação (S1–S4), resumos, DTOs de sync, seed — **186 testes passando no Windows**.
- [x] App: esquema SwiftData V1, mappers, protocolos e fakes, projeto `project.yml`, workflows de CI — **compilados e testados no GitHub Actions em 2026-09-23** (repositório público `03052023/PersonalTrainer`; os três workflows verdes).
- [x] **M0 fechado.**
- [x] **M1 verde no CI (2026-09-23):** Home com o treino do dia, sessão ativa com registro de séries e timer de descanso, resumo ao finalizar, histórico, seed automático; teste de ponta a ponta cobrindo P4/P5/P6. Instalador em cada run de "App build (manual)".
- [ ] **Próximo:** instalar no iPhone (T0.0 V3–V5 e T1.12, ver WINDOWS_SETUP.md); depois M2 (HealthKit, edição, backup).
- Decisões de 2026-09-23: sem IA em nenhuma fase; M5 passa a ser saúde aeróbica e recuperação (SPEC §7.10).

## Requisitos de desenvolvimento

- Motor (`Packages/TrainerCore`) no Windows: Visual Studio 2022 com "Desktop development with C++" + Swift 6.4 para Windows.

```bash
powershell -ExecutionPolicy Bypass -File Scripts/swift-test.ps1
```

- App iOS/watchOS: só no GitHub Actions. Nunca compilado localmente.

## Onde desenvolver

Cópia de trabalho: `C:\Users\leona\Developer\PersonalTrainer`. Não desenvolva dentro de OneDrive/iCloud Drive (corrompe `.git`). Agentes em paralelo usam worktrees em `C:\Users\leona\Developer\pt-wt\`.

## Identificadores

- Bundle IDs atuais: `com.personaltrainer.app` (iPhone) e `com.personaltrainer.app.watchkitapp` (Watch). Os da App Store esperam uma decisão (TASKS T11.10) e, depois do primeiro envio à loja, não mudam.
- `DEVELOPMENT_TEAM` vazio: o CI gera IPA sem assinatura; a assinatura da cópia de teste acontece na ferramenta de sideload. O envio à loja terá workflow próprio (TASKS T11.7).
- Deployment: iOS 18.0 / watchOS 11.0.
