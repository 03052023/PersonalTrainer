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

## 3. Estado: versão 2 pronta (`main` a0fdb68, 2026-09-24)

- **Versão 2 (Magister) completa e verde:** M2 + M4 + M5 + identidade. App build final verde no **run 35997614062** (branch `ci/swap-only`, commit a79c558: versão 2 + troca só de substitutos (RF-34)). O artefato `PersonalTrainer-for-resigning` (IPA só-iPhone para o Impactor) expira em 2026-09-27; depois disso, empurrar o `main` para qualquer `ci/<nome>` gera outro.
- Caminho: onda 2 (TrainerCore: DeloadScheduler, Coach C1–C8, Completo corpo todo, referências), onda 3 (app: saúde, planejador, diálogo, dias D/E, design), integrador, 2 revisores adversariais (17 achados, 5 major, todos corrigidos) e um polimento (fundo linho, "Semana leve", título Magister nas notificações).
- **Falta só a verificação no aparelho:** migração do store da M1, HealthKit real (leitura e gravação), aviso de expiração, aparência do ícone e das telas. Pedir ao usuário prints de qualquer problema.
- Pendências da versão 2.1: lista em TASKS.md, seção M4 ("Pendências para a versão 2.1").

## 4. Branches

Todos os `m2/*`, `m4/*`, `m5/*`, `v2/*`, `v3/*` e `handoff/*` já estão no `main`; os worktrees em `C:\Users\leona\Developer\pt-wt\` podem ser removidos. Branches `ci/*` servem só para disparar o App build.

## 5. Decisões do usuário (identidade)

- **Nome: Magister** (uma palavra; latim para "mestre, quem ensina e guia"). Nome exibido `Magister` nos dois targets (`CFBundleDisplayName` em `project.yml`). Bundle IDs NÃO mudam.
- **Ícone — DECIDIDO (2026-09-23): candidato n1.** Conceito A (5 pétalas separadas em forma de gota) **todas creme** `#F1EDE4`, **miolo areia** `#E9DCC6`, sobre **azul-marinho** `#2B3F58` → `#1C2B40`. Já está pronto no catálogo deste branch: `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/` com `AppIcon.png`, `AppIcon-dark.png`, `AppIcon-tinted.png` e `Contents.json` com `appearances` (luminosity dark/tinted). Gerador: `docs/design/render-app-icon.ps1`; conferência: `docs/design/candidates/AppIcon-checks.png`. DESIGN.md §2 já descreve este ícone. Ordem das pétalas (horária a partir do topo): Longevidade, Hipertrofia, Força, Combate, Resistência; no app cada pétala ganha a cor do objetivo (DESIGN §3).
- Histórico descartado: halter azul (M1), marrom-bege, rosácea creme (conceito B) em musgo e azuis, conceito A em azuis vivos, conceito A com pétalas discretas sobre azul profundo (`render-a-muted.ps1`, m1–m4).
- Acento do app mantido em `#355A7C` / `#9DBAD6`, um tom acima do marinho do ícone. O marinho puro se confundiria com o texto marrom-escuro (justificativa em DESIGN §3).
- **Guia de design:** `DESIGN.md` (versão 1.1) — fundo bege-linho, acento azul profundo (`#355A7C` claro / `#9DBAD6` escuro, contrastes AA calculados), tokens por objetivo, tipografia New York nos títulos e SF Rounded nos números, voz sem jargão de academia, aba "Hoje" (`sun.max`), botão "Começar", Home com o objetivo no topo. **Ajuste pendente:** a seção 2 descreve o conceito B; atualizar para o conceito A escolhido e trocar as cores de objetivo pela paleta das pétalas.

## 5b. Versão 2.1 entregue (2026-09-24)

Escopo e contrato em `docs/V21-CONTRACT.md`: modo casa (RF-42, §7.13), medida (RF-43), RIR explicado (RF-41), textos de relógio genérico, ajustes B7/B10/A4-B8/A5. O "Como fazer" (RF-40) fica para a versão seguinte.
- Onda A no `main`: `v4/core-home` e `v4/health-texts`, verdes. Andaime (72b5fb5) verde.
- Onda B: `v4/home-mode` (ca7394a, App build 36025529850 verde), `v4/session-measure` (e0be816, verde) e `v4/health-coach` (5219f7e, verde).
- Integração, revisão (8 achados, 3 major) e correção: `main` 7a60541. App build 36037123014 (IPA para instalar, disponível até 2026-09-27) e Core tests 36038514976, os dois verdes.
- Página de instalação da Amanda: `docs/install/instalar-magister.html`, publicada como artifact privado https://claude.ai/artifact/YExae7s4NkzJqLzSQuHrvH (o dono compartilha pelo menu Share). Próximo: "Como fazer" (RF-40, T6.1 e T6.4–T6.9) e as pendências da 2.1 no TASKS.

## 6. Próximos passos

1. O usuário instala o IPA do run 35997614062 por cima do app atual, pelo Impactor, e testa.
2. Corrigir o que aparecer no aparelho (App build em `ci/<nome>` até ficar verde; depois `main`).
3. Versão 2.1 (TASKS.md) e, quando o usuário quiser, M3 (app do Apple Watch).

## 7. Como os agentes trabalharam bem neste projeto

Contratos escritos primeiro pelo arquiteto → implementadores em worktrees separados (um branch cada, escopo de arquivos exclusivo) → integrador único no `main` → revisores somente leitura com lentes distintas → corretor único. Código de app é escrito às cegas (sem Xcode): exigir lista de "verificado/incerto" e revisão estática antes do CI. O limite de uso do plano do usuário já foi atingido duas vezes com muitos agentes ao mesmo tempo; prefira ondas menores.
