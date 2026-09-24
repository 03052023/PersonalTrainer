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

## 3. O que já está no `main` (1f82b66 ou posterior)

- M0 e M1 completos; o app M1 roda no iPhone do usuário.
- **M2 completo e verde:** 12 partes mescladas, revisadas por 4 lentes e corrigidas (eab3e3b). Core tests verde (run 35945595815) e **App build verde na primeira tentativa** (run 35945596092, branch `ci/app-check`): compila, passa nos testes do simulador e gera o IPA. Falta só a verificação no aparelho (HealthKit real, migração do store da M1).
- **Cálculo do M4 e do M5 mesclado** (via `v2/core-integration`): saúde (zonas, minutos aeróbicos, VO2máx FRIEND, recuperação, passos, sugestões), semana leve (DeloadPolicy), seletor por frequência (S5–S7), revisão periódica (R1–R7, C2) e melhores marcas (C6).
- **Identidade:** ícone final no catálogo com as aparências escura e tingida; nome **Magister** no `project.yml` (T2.23 [PROJ]).
- **CI de app por push:** um push em `ci/<nome>` roda o App build, e as falhas aparecem como anotações públicas. Não é preciso pedir ao usuário para clicar.
- **SPEC com as pendências resolvidas** (818d007): rearme do deload, carga e duração do deload, R3–R5, tabela de objetivos igual ao `GoalDefaults`, **Completo = corpo todo** (decisão do usuário), pescoço conta como costas, FRIEND no A3, A5 atualizado e decisão 16 (nome e ícone). CA4-3, CA4-4 e CA5-5 ajustados; T4.3 fechada como sugestão.
- **Contrato da rodada final:** `docs/V2-FINAL-CONTRACT.md` (onda 2 = TrainerCore; onda 3 = app + integrador).

## 4. Em andamento e fora do `main`

Onda 2 concluída e mesclada no `main` (fbdf75d): `DeloadScheduler`, `TrainerCore/Coach` (C1–C8, `CoachLog`, `ReviewSchedule`, `ProvisioningProfileParser`), Completo corpo todo com id novo (o A/B/C da M1 fica intacto e inativo no seed) e referências novas. Todos verdes no CI.

**Onda 3 (app) concluída** (workflow `wf_d47ca6cb-752`): os 5 branches `v3/health`, `v3/planner`, `v3/coach`, `v3/program-days` e `v3/design` ficaram verdes no App build. Os relatórios, com a API para o integrador, estão em `docs/wave3-agent-results.json`.

**Integração:** o branch `v3/integration` (worktree `pt-wt/w3-integration`) tem os 5 mesclados sem conflito, e o shim do diálogo já foi apagado (ad4eb3e, enviado para `ci/v3-merge`). **Falta o integrador** (contrato §2.6): ligar Home, Root e Ajustes, `AppEnvironment` (`healthReader`, `coach`, `deloadDecisions`), aba Hoje, Começar e flor; acrescentar `Services/Decisions` ao ARCHITECTURE §17; iterar em `ci/v3-final`. Depois, revisão adversarial, correção e merge no `main`.

Pendências do corretor do M2 que não bloqueiam: C10 (blocos de intervalos do Combate e de equilíbrio/mobilidade viram lembretes C8) e C11 (exercício do seed editado exige SchemaV3 antes de um seed v3). Os programas Foco inferior e Foco superior ainda usam os descansos antigos (180/120 s) e não foram revisados para 2×/semana.

## 5. Decisões do usuário (identidade)

- **Nome: Magister** (uma palavra; latim para "mestre, quem ensina e guia"). Nome exibido `Magister` nos dois targets (`CFBundleDisplayName` em `project.yml`). Bundle IDs NÃO mudam.
- **Ícone — DECIDIDO (2026-09-23): candidato n1.** Conceito A (5 pétalas separadas em forma de gota) **todas creme** `#F1EDE4`, **miolo areia** `#E9DCC6`, sobre **azul-marinho** `#2B3F58` → `#1C2B40`. Já está pronto no catálogo deste branch: `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/` com `AppIcon.png`, `AppIcon-dark.png`, `AppIcon-tinted.png` e `Contents.json` com `appearances` (luminosity dark/tinted). Gerador: `docs/design/render-app-icon.ps1`; conferência: `docs/design/candidates/AppIcon-checks.png`. DESIGN.md §2 já descreve este ícone. Ordem das pétalas (horária a partir do topo): Longevidade, Hipertrofia, Força, Combate, Resistência; no app cada pétala ganha a cor do objetivo (DESIGN §3).
- Histórico descartado: halter azul (M1), marrom-bege, rosácea creme (conceito B) em musgo e azuis, conceito A em azuis vivos, conceito A com pétalas discretas sobre azul profundo (`render-a-muted.ps1`, m1–m4).
- Acento do app mantido em `#355A7C` / `#9DBAD6`, um tom acima do marinho do ícone. O marinho puro se confundiria com o texto marrom-escuro (justificativa em DESIGN §3).
- **Guia de design:** `DESIGN.md` (versão 1.1) — fundo bege-linho, acento azul profundo (`#355A7C` claro / `#9DBAD6` escuro, contrastes AA calculados), tokens por objetivo, tipografia New York nos títulos e SF Rounded nos números, voz sem jargão de academia, aba "Hoje" (`sun.max`), botão "Começar", Home com o objetivo no topo. **Ajuste pendente:** a seção 2 descreve o conceito B; atualizar para o conceito A escolhido e trocar as cores de objetivo pela paleta das pétalas.

## 6. Rodada final da versão 2 (o que falta fazer)

1. ~~Revisão e correção do M2~~; ~~M4/M5 core verdes~~; ~~SPEC resolvida~~; ~~ícone e nome~~ (tudo no `main`).
2. **Onda 2 (TrainerCore)**: conferir e mesclar os 4 branches `v2/*` (§4).
3. **Onda 3 (app)**, conforme `docs/V2-FINAL-CONTRACT.md` §2: Saúde (mescla `m5/health-reader` e `m5/health-ui`), Planejador (semana leve, seletor por frequência, decisões em JSON), Diálogo (feed C1–C8, expiração dos 7 dias com notificação, revisão periódica aplicável, melhores marcas), Dias D/E (T2.22) e Design (tokens, flor, aba Hoje, Começar). Implementadores em pastas disjuntas e um integrador único em `App/`, `Features/Home` e `Features/Settings`.
4. App build em `ci/<nome>` até ficar verde; revisão adversarial (compilação, migração do store real, comportamento vs SPEC) e correção.
5. Push do `main` e de `ci/release`. O usuário baixa o artefato `PersonalTrainer-for-resigning` do run verde e instala o `PersonalTrainer-iphone-only-for-resigning.ipa` por cima, pelo Impactor. Explicar o passo a passo (ele é leigo).

Opcional antes disso: o IPA do run 35945596092 (M2 + ícone + nome) já pode ser instalado para testar no aparelho a migração da M1 e o HealthKit.

## 7. Como os agentes trabalharam bem neste projeto

Contratos escritos primeiro pelo arquiteto → implementadores em worktrees separados (um branch cada, escopo de arquivos exclusivo) → integrador único no `main` → revisores somente leitura com lentes distintas → corretor único. Código de app é escrito às cegas (sem Xcode): exigir lista de "verificado/incerto" e revisão estática antes do CI. O limite de uso do plano do usuário já foi atingido duas vezes com muitos agentes ao mesmo tempo; prefira ondas menores.
