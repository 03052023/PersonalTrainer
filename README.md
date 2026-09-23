# PersonalTrainer

App pessoal de musculação para iPhone + Apple Watch que funciona como personal trainer automático: diz o treino do dia (exercícios, séries, repetições, cargas), registra o resultado e recalcula o próximo treino de forma determinística.

| Documento | Conteúdo |
|-----------|----------|
| [SPEC.md](SPEC.md) | Produto, fluxos, requisitos e **regras de domínio** (progressão, seleção, deload, política de FC). |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Targets, camadas, modelos de dados, motor, sync Watch, HealthKit, riscos, ADRs. |
| [TASKS.md](TASKS.md) | Milestones com critérios de aceitação e tarefas pequenas para execução paralela. |
| [AGENTS.md](AGENTS.md) | Regras para Claude Code, Codex e humanos que editam o repositório. |

## Ambiente atual

Windows 11, sem Mac, custo zero. iPhone 17 (iOS 26.6.2) e Apple Watch Series 7 (watchOS 26.5), conta Apple gratuita.
Builds Apple no GitHub Actions (`macos-26`, Xcode 26.6, projeto gerado por XcodeGen); instalação por sideload no Windows.
A instalação gratuita dos apps ainda precisa ser comprovada nos aparelhos: roteiro e riscos em [WINDOWS_SETUP.md](WINDOWS_SETUP.md).

## Estado (2026-09-22)

- [x] Documentação (SPEC, ARCHITECTURE, TASKS, AGENTS) alinhada com a implementação.
- [x] `TrainerCore`: domínio, motor de progressão (P1–P12), rotação (S1–S4), resumos, DTOs de sync, seed — **186 testes passando no Windows**.
- [x] App: esquema SwiftData V1, mappers, protocolos e fakes, projeto `project.yml`, workflows de CI — escritos e revisados, **aguardam o primeiro run do GitHub Actions** (TASKS T0.11).
- [ ] T0.11 — publicar o repositório e obter o primeiro run verde. Depois: M1 (telas e sessão ativa).

## Requisitos de desenvolvimento

- Motor (`Packages/TrainerCore`) no Windows: Visual Studio 2022 com "Desktop development with C++" + Swift 6.4 para Windows.

```bash
powershell -ExecutionPolicy Bypass -File Scripts/swift-test.ps1
```

- App iOS/watchOS: só no GitHub Actions. Nunca compilado localmente.

## Onde desenvolver

Cópia de trabalho: `C:\Users\leona\Developer\PersonalTrainer`. Não desenvolva dentro de OneDrive/iCloud Drive (corrompe `.git`). Agentes em paralelo usam worktrees em `C:\Users\leona\Developer\pt-wt\`.

## Identificadores

- Bundle IDs: `com.personaltrainer.app` (iPhone) e `com.personaltrainer.app.watchkitapp` (Watch). Fixos: cada mudança consome App IDs da conta gratuita.
- `DEVELOPMENT_TEAM` vazio: o CI gera IPA sem assinatura; a assinatura acontece na ferramenta de sideload.
- Deployment: iOS 18.0 / watchOS 11.0.
