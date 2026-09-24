# Passagem de bastão — estado em 2026-09-23

Documento para continuar o projeto num chat novo. Leia inteiro antes de agir. Os documentos de referência continuam sendo SPEC.md, ARCHITECTURE.md, TASKS.md, AGENTS.md, WINDOWS_SETUP.md e docs/M2-CONTRACT.md.

## 1. Quem é o usuário e como trabalhar

- Leonardo, pt-BR, leigo em programação e design; quer explicações passo a passo, curtas e concretas.
- Só tem Windows 11 (nunca terá Mac). iPhone 17 (iOS 26.6.2) e Apple Watch Series 7 (watchOS 26.5). Conta Apple gratuita (não quer pagar por enquanto).
- Instala o app com o **Impactor** (sideload) usando o arquivo `PersonalTrainer-iphone-only-for-resigning.ipa` do workflow "App build (manual)". O app expira a cada 7 dias; renova reinstalando por cima (os dados ficam).
- Repositório público: https://github.com/03052023/PersonalTrainer (remote `origin`). `git push` no shell do agente só funciona com `$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"`.
- Ele valoriza: tudo determinístico, baseado em ciência com referências visíveis ("Por quê?"), nada de cultura de academia, objetivos no centro, sem IA (uma camada paga com IA é ideia futura, fora do escopo).

## 2. Bloqueio importante do ambiente

O **Controle Inteligente de Aplicativos do Windows (Smart App Control)** está ativo e bloqueia o compilador Swift (`swiftc.exe`, erro 4551). `Scripts/swift-test.ps1` **não roda mais localmente**. Não desligar (é configuração de segurança e não volta sem reinstalar o Windows).

**Como testar o TrainerCore agora:** enviar o branch ao GitHub (`git push origin <branch>`); o workflow "Core tests" (Linux, swift:6.3) roda sozinho em push que toca `Packages/**`. Ler o resultado pela API pública (`https://api.github.com/repos/03052023/PersonalTrainer/actions/runs`) e os erros pelas anotações do job (`/check-runs/<job_id>/annotations`). O log completo exige login, e o agente não usa as credenciais do usuário. O branch `m5/health-core` já tem o passo "Report failures as annotations" em `.github/workflows/core-tests.yml`; ao integrar, esse arquivo vai para `main`.

Armadilha do Swift 6.3 no Linux: listas de tuplas com membros implícitos dentro de `@Test(arguments: [...])` estouram o tempo de inferência. Declare os casos antes, como constantes com tipo explícito.

## 3. O que já está no `main` (commit 3128a5a ou posterior)

- M0 e M1 completos e verdes no CI; o app M1 roda no iPhone do usuário.
- M2 mesclado (12 branches `m2/*`) e ligado pelo integrador: SchemaV2 com migração, seed v2 (7 programas de 5 exercícios, mais de 70 exercícios com padrão de movimento), repositórios de programa e catálogo, abas Programa e Ajustes, onboarding de objetivo, botão Trocar, editar/apagar série, minimizar sessão, apagar treino, escolher dia A/B/C, gráfico por exercício, frequência semanal, backup JSON, HealthKit (gravar ou vincular treino e FC da sessão), catálogo de referências e botão "Por quê?".
- **Verificar ao começar:** a revisão do M2 (4 revisores: compilação, runtime/migração, comportamento, referências) e o corretor estavam rodando quando este documento foi escrito (workflow `personaltrainer-m2`, run `wf_ae35ef39-540`, só visível na sessão antiga). Se `git log main` **não** tiver um commit "fix(M2): apply review findings", rode de novo a revisão e a correção sobre `main` (o roteiro está no transcript antigo; refaça com 4 revisores somente leitura + 1 corretor).

## 4. Branches fora do `main`

| Branch | Estado | Observação |
|--------|--------|-----------|
| `m5/health-core` | **verde no CI** (run 35942940487) | TrainerCore/Health: zonas de FC (Tanaka, ACSM, Karvonen), minutos aeróbicos, VO2máx com tabela FRIEND 2015 conferida, recuperação, passos, sugestões; e o passo de anotações no core-tests.yml |
| `m5/health-reader` | escrito, não compilado | `HealthDataReading`, `LiveHealthDataReader`, `FakeHealthDataReader` |
| `m5/health-ui` | escrito, não compilado | `HealthViewModel`, `HealthCardView`, `HealthDetailView`, gráficos, perfil |
| `m4/review-core` | commit feito, testes não rodados | TrainerCore/Review: 1RM estimado, ProgramReviewer R1–R7, RecoveryContext, PersonalRecordDetector |
| `m4/engine-policies` | **em andamento** (alterações não commitadas no worktree `pt-wt/m4-engine`) | FrequencyAwareSelector S5–S7, DeloadPolicy, `SessionSummary.isDeload`. Se o agente não terminou, termine a partir do worktree |
| `handoff/identity-and-state` | este documento + DESIGN.md + candidatos de ícone | mesclar no `main` na rodada final |

Resultados detalhados dos agentes do M5 (incertezas, perguntas, referências a adicionar): `docs/m5-agent-results.json`.

Worktrees em `C:\Users\leona\Developer\pt-wt\*`. Os dos `m2/*` já foram mesclados e podem ser removidos (`git worktree remove --force`; se o caminho for longo demais, `Remove-Item -LiteralPath "\\?\<caminho>" -Recurse -Force`).

## 5. Decisões do usuário (identidade)

- **Nome: Magister** (uma palavra; latim para "mestre, quem ensina e guia"). Nome exibido `Magister` nos dois targets (`CFBundleDisplayName` em `project.yml`). Bundle IDs NÃO mudam.
- **Ícone (decisão mais recente, 2026-09-23):** **conceito A** (5 pétalas separadas em forma de gota, miolo claro) sobre o **azul-marinho** da antiga "opção 5" (`#2B3F58` → `#1C2B40`), com **pétalas bem claras**. Candidatos em `docs/design/candidates/icon-navy-n1..n3.png` e `navy-light-compare.png`; gerador em `docs/design/render-a-navy.ps1` (PowerShell + System.Drawing, 1024 px). n1 = todas creme com miolo areia; n2 = quase brancas com tons sutis por objetivo; n3 = claras com cores um pouco mais visíveis. **Pendente: ele escolher n1, n2 ou n3** (ou pedir ajuste). Ordem das pétalas (horária a partir do topo): Longevidade, Hipertrofia, Força, Combate, Resistência. Se ele escolher n2/n3, a família de cor de cada pétala vira a cor do objetivo no app, em versão mais escura para ter contraste na interface.
- Histórico descartado: halter azul (M1), marrom-bege, rosácea creme (conceito B) em musgo e azuis, conceito A em azuis vivos, conceito A com pétalas discretas sobre azul profundo (`render-a-muted.ps1`, m1–m4).
- Consequência para o acento do app: o DESIGN.md usa azul profundo (`#355A7C` / `#9DBAD6`); com o fundo do ícone em azul-marinho, conferir se o acento deve escurecer para combinar (manter contraste AA).
- **Guia de design:** `DESIGN.md` (versão 1.1) — fundo bege-linho, acento azul profundo (`#355A7C` claro / `#9DBAD6` escuro, contrastes AA calculados), tokens por objetivo, tipografia New York nos títulos e SF Rounded nos números, voz sem jargão de academia, aba "Hoje" (`sun.max`), botão "Começar", Home com o objetivo no topo. **Ajuste pendente:** a seção 2 descreve o conceito B; atualizar para o conceito A escolhido e trocar as cores de objetivo pela paleta das pétalas.

## 6. Rodada final da versão 2 (o que falta fazer)

1. Confirmar/terminar a revisão e a correção do M2 (seção 3).
2. Terminar `m4/engine-policies`; enviar `m4/*` e `m5/*` ao GitHub e deixar o Core tests verde (corrigir pelas anotações).
3. Mesclar no `main`: `m5/health-core`, `m5/health-reader`, `m5/health-ui`, `m4/engine-policies`, `m4/review-core`, `handoff/identity-and-state`.
4. Integração (app, compilado só no CI):
   - Card Saúde na Home e `HealthViewModel` no AppEnvironment (`LiveHealthDataReader` quando disponível).
   - Referências novas no `references.v1.json`: `topic.sleep`, `topic.steps`, FRIEND 2015 (doi 10.1016/j.mayocp.2015.07.026), Tanaka 2001 (10.1016/S0735-1097(00)01054-8), ACSM 2011 (10.1249/MSS.0b013e318213fefb), OMS 2020 (10.1136/bjsports-2020-102955) — verificar no Crossref.
   - Deload no `SessionPlanner` (sessões `isDeload`, prescrição reduzida, desfazer), `FrequencyAwareSelector` com chave em Ajustes (padrão ligado com ≥ 4 dias), revisão periódica a cada 4 semanas.
   - **Diálogo do app (SPEC §7.11, C1–C8, T4.8):** `CoachFeedBuilder`, `CoachLogStore` (JSON), `ProvisioningExpiryReader` (lê `ExpirationDate` do `embedded.mobileprovision` e agenda notificação na véspera), feed na Home e destaque na abertura.
   - **T2.22:** dias do programa (adicionar/remover/renomear/reordenar, 1–7).
   - **Passada de design** conforme DESIGN.md (AccentColor, tokens, aba "Hoje", "Começar", objetivo no topo com a flor, fim dos símbolos de halter/figura de musculação).
   - Ícone final (paleta escolhida, conceito A) em `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024, opaco) e nome Magister no `project.yml`.
   - SPEC: decisão 16 (nome e ícone), §7.10 A3 citando FRIEND, redação do CA5-5 ("nunca vigoroso" em vez de "nunca no dia").
5. Revisão adversarial de tudo (compilação, runtime/migração do store do usuário, comportamento vs SPEC, referências) e correção.
6. Push do `main`; o usuário roda "App build (manual)" e instala o novo `.ipa` só-iPhone por cima pelo Impactor. Explicar o passo a passo (ele é leigo).

## 7. Como os agentes trabalharam bem neste projeto

Contratos escritos primeiro pelo arquiteto → implementadores em worktrees separados (um branch cada, escopo de arquivos exclusivo) → integrador único no `main` → revisores somente leitura com lentes distintas → corretor único. Código de app é escrito às cegas (sem Xcode): exigir lista de "verificado/incerto" e revisão estática antes do CI. O limite de uso do plano do usuário já foi atingido duas vezes com muitos agentes ao mesmo tempo; prefira ondas menores.
