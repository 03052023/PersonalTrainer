# PersonalTrainer

App pessoal de musculação para iPhone + Apple Watch que funciona como personal trainer automático: diz o treino do dia (exercícios, séries, repetições, cargas), registra o resultado e recalcula o próximo treino de forma determinística.

| Documento | Conteúdo |
|-----------|----------|
| [SPEC.md](SPEC.md) | Produto, fluxos, requisitos e **regras de domínio** (progressão, seleção, deload, política de FC). |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Targets, camadas, modelos de dados, motor, sync Watch, HealthKit, riscos, ADRs. |
| [TASKS.md](TASKS.md) | Milestones com critérios de aceitação e tarefas pequenas para execução paralela. |
| [AGENTS.md](AGENTS.md) | Regras para Claude Code, Codex e humanos que editam o repositório. |

## Estado

- [x] Documentação inicial (M0 em planejamento).
- [ ] T0.1 — projeto Xcode (exige Mac). Ver TASKS.md.

## Requisitos de desenvolvimento

- macOS + Xcode 16 ou superior para os apps.
- Qualquer SO com toolchain Swift 6 para `Packages/TrainerCore`:

```bash
cd Packages/TrainerCore && swift test
```

## Onde desenvolver

Clone em um caminho ASCII sem espaços no Mac (ex.: `~/Developer/PersonalTrainer`). Não desenvolva dentro de OneDrive/iCloud Drive.

## Placeholders a preencher em T0.1

- Team ID e bundle IDs (`<TEAM>.PersonalTrainer`, `<TEAM>.PersonalTrainer.watchkitapp`).
- Deployment target real do seu iPhone/Watch (mínimo iOS 18 / watchOS 11).
