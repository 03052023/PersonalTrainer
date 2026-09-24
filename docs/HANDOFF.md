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

Caminho alternativo local, que o agente do M4 usou com sucesso e que fica **só no scratchpad, nunca no repositório**: compilar com o ambiente do `swift-test.ps1` + `--build-system native` (o `swiftc` roda; o bloqueado é o `clang.exe` usado como linker), linkar com o `link.exe` do MSVC (assinado pela Microsoft) usando `/INCREMENTAL:NO` (o incremental quebra a descoberta de testes do Swift Testing) e rodar o binário com `--testing-library swift-testing`. Mesmo assim, o CI continua sendo a verificação oficial.

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
| `m4/review-core` | 4f13278; só tipagem conferida (`swiftc -typecheck`), testes não rodados | TrainerCore/Review: 1RM estimado, ProgramReviewer R1–R7 + C2 (troca de programa como sugestão), PersonalRecordDetector (C6); 70 testes |
| `m4/engine-policies` | 7aebbf1; 217/217 testes passaram localmente pelo caminho alternativo (ver §2) | FrequencyAwareSelector S5–S7, DeloadPolicy (gatilho, prescrição, duração), DeloadTrigger, `SessionSummary.isDeload` |

**Pontos da SPEC que os agentes do M4 deixaram para decisão** (detalhes em `docs/m4-agent-results.json`, campo `specIssues`). Resolver na SPEC antes de ligar o deload no `SessionPlanner`:
1. **Rearme do deload (bloqueante):** depois da semana leve, as mesmas notas `decrease` continuam lá e o gatilho (a) dispararia outro deload na hora. Proposta: só contar reduções cuja sessão de origem é posterior ao fim do último deload.
2. **Carga do deload:** a SPEC diz round↓(0,85·L); a assinatura recebe só a prescrição normal, então usa 0,85 × carga prescrita. Decidir se aceita ou se passa L.
3. **§7.5 (b):** "N semanas de treino" contra "N semanas desde o último deload" (C1); foi implementado como tempo decorrido.
4. **R5:** "por 2 revisões seguidas" exigiria memória de revisões; foi implementado como estagnação ≥ 3 sessões → mudar faixa de repetições e ≥ 6 → trocar exercício.
5. **T4.3 / CA4-4:** a troca de programa por mesociclo virou sugestão opcional (C2), não troca automática; `Engine/ProgramRotationPolicy.swift` não foi criado. Ajustar CA4-4.
6. Programa mais novo que a janela de 4 semanas: R3/R4 não rodam (decisão conservadora, falta na SPEC).
7. Faltam tópicos de referência próprios para "mudar faixa de repetições" e "trocar programa" (hoje usam `topic.substitution`).
| `v2/core-integration` | **verde no CI** (run 35944194119, commit 6c16ab3) | `main` 3128a5a + `m5/health-core` + `m4/engine-policies` + `m4/review-core` mesclados sem conflito; todo o TrainerCore (incluindo os 70 testes da revisão, que nunca tinham rodado) passa no Linux. Mesclar este branch no `main` em vez dos três separados |
| `handoff/identity-and-state` | este documento + DESIGN.md + ícone final no catálogo | mesclar no `main` na rodada final |

Resultados detalhados dos agentes do M5 (incertezas, perguntas, referências a adicionar): `docs/m5-agent-results.json`.

Worktrees em `C:\Users\leona\Developer\pt-wt\*`. Os dos `m2/*` já foram mesclados e podem ser removidos (`git worktree remove --force`; se o caminho for longo demais, `Remove-Item -LiteralPath "\\?\<caminho>" -Recurse -Force`).

## 5. Decisões do usuário (identidade)

- **Nome: Magister** (uma palavra; latim para "mestre, quem ensina e guia"). Nome exibido `Magister` nos dois targets (`CFBundleDisplayName` em `project.yml`). Bundle IDs NÃO mudam.
- **Ícone — DECIDIDO (2026-09-23): candidato n1.** Conceito A (5 pétalas separadas em forma de gota) **todas creme** `#F1EDE4`, **miolo areia** `#E9DCC6`, sobre **azul-marinho** `#2B3F58` → `#1C2B40`. Já está pronto no catálogo deste branch: `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/` com `AppIcon.png`, `AppIcon-dark.png`, `AppIcon-tinted.png` e `Contents.json` com `appearances` (luminosity dark/tinted). Gerador: `docs/design/render-app-icon.ps1`; conferência: `docs/design/candidates/AppIcon-checks.png`. DESIGN.md §2 já descreve este ícone. Ordem das pétalas (horária a partir do topo): Longevidade, Hipertrofia, Força, Combate, Resistência; no app cada pétala ganha a cor do objetivo (DESIGN §3).
- Histórico descartado: halter azul (M1), marrom-bege, rosácea creme (conceito B) em musgo e azuis, conceito A em azuis vivos, conceito A com pétalas discretas sobre azul profundo (`render-a-muted.ps1`, m1–m4).
- Acento do app mantido em `#355A7C` / `#9DBAD6`, um tom acima do marinho do ícone. O marinho puro se confundiria com o texto marrom-escuro (justificativa em DESIGN §3).
- **Guia de design:** `DESIGN.md` (versão 1.1) — fundo bege-linho, acento azul profundo (`#355A7C` claro / `#9DBAD6` escuro, contrastes AA calculados), tokens por objetivo, tipografia New York nos títulos e SF Rounded nos números, voz sem jargão de academia, aba "Hoje" (`sun.max`), botão "Começar", Home com o objetivo no topo. **Ajuste pendente:** a seção 2 descreve o conceito B; atualizar para o conceito A escolhido e trocar as cores de objetivo pela paleta das pétalas.

## 6. Rodada final da versão 2 (o que falta fazer)

1. Confirmar/terminar a revisão e a correção do M2 (seção 3).
2. ~~Core tests verde para M4 + M5~~ (feito em `v2/core-integration`). Resolver na SPEC os pontos do M4 listados na §4, principalmente o rearme do deload.
3. Mesclar no `main`: `v2/core-integration`, `m5/health-reader`, `m5/health-ui`, `handoff/identity-and-state`.
4. Integração (app, compilado só no CI):
   - Card Saúde na Home e `HealthViewModel` no AppEnvironment (`LiveHealthDataReader` quando disponível).
   - Referências novas no `references.v1.json`: `topic.sleep`, `topic.steps`, FRIEND 2015 (doi 10.1016/j.mayocp.2015.07.026), Tanaka 2001 (10.1016/S0735-1097(00)01054-8), ACSM 2011 (10.1249/MSS.0b013e318213fefb), OMS 2020 (10.1136/bjsports-2020-102955) — verificar no Crossref.
   - Deload no `SessionPlanner` (sessões `isDeload`, prescrição reduzida, desfazer), `FrequencyAwareSelector` com chave em Ajustes (padrão ligado com ≥ 4 dias), revisão periódica a cada 4 semanas.
   - **Diálogo do app (SPEC §7.11, C1–C8, T4.8):** `CoachFeedBuilder`, `CoachLogStore` (JSON), `ProvisioningExpiryReader` (lê `ExpirationDate` do `embedded.mobileprovision` e agenda notificação na véspera), feed na Home e destaque na abertura.
   - **T2.22:** dias do programa (adicionar/remover/renomear/reordenar, 1–7).
   - **Passada de design** conforme DESIGN.md (AccentColor, tokens, aba "Hoje", "Começar", objetivo no topo com a flor, fim dos símbolos de halter/figura de musculação).
   - Ícone: já pronto neste branch (entra com o merge). Falta o nome Magister no `project.yml` (`CFBundleDisplayName`, tarefa [PROJ]).
   - SPEC: decisão 16 (nome e ícone), §7.10 A3 citando FRIEND, redação do CA5-5 ("nunca vigoroso" em vez de "nunca no dia").
5. Revisão adversarial de tudo (compilação, runtime/migração do store do usuário, comportamento vs SPEC, referências) e correção.
6. Push do `main`; o usuário roda "App build (manual)" e instala o novo `.ipa` só-iPhone por cima pelo Impactor. Explicar o passo a passo (ele é leigo).

## 7. Como os agentes trabalharam bem neste projeto

Contratos escritos primeiro pelo arquiteto → implementadores em worktrees separados (um branch cada, escopo de arquivos exclusivo) → integrador único no `main` → revisores somente leitura com lentes distintas → corretor único. Código de app é escrito às cegas (sem Xcode): exigir lista de "verificado/incerto" e revisão estática antes do CI. O limite de uso do plano do usuário já foi atingido duas vezes com muitos agentes ao mesmo tempo; prefira ondas menores.
