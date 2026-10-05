# Passagem de bastão — estado em 2026-10-05 (versão 2.4 entregue, §5e; lançamento na App Store em preparo, §5f)

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

## 5c. Versão 2.2 (simplificação) entregue (2026-09-27)

O dono usou a 2.1 no aparelho (instalação e migração funcionaram) e pediu os pontos S1–S10 (TASKS, seção Versão 2.2). A proposta foi aprovada com as telas de exemplo em `docs/design/v22/mockup.html` (artifact NAhQznJgc8DJNaiThpm2SZ). Decisões dele em `docs/design/v22/proposal.json` → `ownerAnswers`:
- flor 6 · Brisa;
- RIR interno e invisível ao usuário;
- Combate = "Potência e resistência";
- proposta inteira aprovada: ficha de consulta com Feito, objetivo = plano, Hoje enxuta, peso do corpo sem carga, sem a chave de aquecimento.

Construído pelo workflow `wf_fdd53fa1-c8f`: contrato em `docs/V22-CONTRACT.md`, 7 tarefas `v5/*` verdes, integração e revisão (13 achados; os 4 major foram corrigidos), `main` 6a26655. IPA no App build 36362402317 (disponível até 2026-10-01T00:41Z). Página e PDF da Amanda atualizados para esse run. Pendências menores no TASKS (A4 carga digitada perdida ao Voltar, A5 evolução de peso do corpo em kg, A7 "Sair sem registrar" deixa sessão abandonada, B6, texto do ProgramReviewer).

## 5d. Versão 2.3 entregue (2026-10-04): App build 37254171858 (IPA até 2026-10-08), main 6eec103; 8 achados minor da revisão ficaram para a 2.4 (ver journal do workflow wf_99b0843b-ca9). Próxima versão (2.4): atividades fora do app (notas, item 19).

Pedidos do dono:
- D1: "Corpo todo" vira "Equilibrado", 4 dias alternando Superior e Inferior.
- D2: "Resistência muscular" vira "Fôlego", cardiovascular, medido em minutos.
- D3: carga opcional em qualquer exercício.
- D4: medida `minutes`.
- D5: "Como fazer" com desenhos de todos os exercícios dos programas.
- Sessão ainda mais simples depois de "Começar".
- Estética mais bonita, "budista, porém estoica", com animação de abertura.

Workflow `wf_b80f610e-930`:
- **Pesquisa de estética:** 3 frentes + síntese em `docs/design/v23-aesthetics/directions.html`.
- **Núcleo:** contrato `docs/V23-CORE-CONTRACT.md`, branches `v6/core` e `v6/guide-engine`, desenhos em lotes `v6/guides-N` juntados em `v6/guide-engine`.
- **Ao retomar:** mostrar as 3 direções ao dono, fazer a onda de telas (sessão guiada, passada estética, UI do Como fazer e do Fôlego) sobre `v6/*` e gerar um IPA novo. Atualizar a página e o PDF da Amanda.

### 5d.1 Estado em 2026-09-28

- **Estética escolhida: A · Tinta e papel, com mensagens estoicas** (artifact LBdKARcqRc6rfFvRE3qRjf). Mais pedidos do dono: pólen na abertura, desenhos aprovados e uma tela inicial bonita antes do treino do dia (docs/design/v23-owner-notes.md, item 14). **Etapa das telas no workflow `wf_99b0843b-ca9`** (arquiteto mescla v6/guide-engine no main e escreve docs/V23-UI-CONTRACT.md → worktrees `pt-wt/w7-*` → v7/integration → ci/v7-final → revisão → correção → merge no main). Ao retomar: se interrompido, `resumeFromRunId`; depois, gerar o IPA do run final e atualizar a página e o PDF da Amanda (docs/install/, build-pdf.ps1 no scratchpad).
- **Animação de abertura:** protótipo em `docs/design/v23-animation/launch.html` (artifact 3TBNBgXpsETDCSiFp1ouY4). Detalhes sutis no workflow `wf_033bc874-622`, retomado; o crítico mandou cortar pólen, fio de luz e pétalas vivas, e manter amanhecer quente (areia) e pétala do objetivo. O dono disse que o gosto dele é só sinal: não sobrepor o crítico.
- **Núcleo 2.3 pronto:** `v6/core` (3d6745d, verde) mesclado em `v6/guide-engine` (dc4c6f4, Core tests 36386958543 verde), com 55 guias em `exercise-guides.v1.json`, uma por exercício dos programas. Folhas de revisão em `docs/design/exercise-guides/sheet-grupo-*.png` (no worktree `pt-wt/w6-guide-engine`), enviadas ao dono (T6.8). **Falta:** o dono escolher a estética; depois a onda de telas sobre `v6/guide-engine` (sessão guiada, estética, UI do Como fazer, Cardio, vários planos, abertura) e o IPA.
- **Decisões do dono para a onda de telas:** `docs/design/v23-owner-notes.md` (Cardio "Coração forte e mais condicionamento", carga opcional com sugestão delicada, vários planos com encaixe e consequências, plano Cardio VO2máx 4×4, sem cardio base). **Copiar essas notas para o contrato da onda de telas.**

## 6. Próximos passos

1. O usuário instala o IPA do run 35997614062 por cima do app atual, pelo Impactor, e testa.
2. Corrigir o que aparecer no aparelho (App build em `ci/<nome>` até ficar verde; depois `main`).
3. Versão 2.1 (TASKS.md) e, quando o usuário quiser, M3 (app do Apple Watch).

## 7. Como os agentes trabalharam bem neste projeto

Contratos escritos primeiro pelo arquiteto → implementadores em worktrees separados (um branch cada, escopo de arquivos exclusivo) → integrador único no `main` → revisores somente leitura com lentes distintas → corretor único. Código de app é escrito às cegas (sem Xcode): exigir lista de "verificado/incerto" e revisão estática antes do CI. O limite de uso do plano do usuário já foi atingido duas vezes com muitos agentes ao mesmo tempo; prefira ondas menores.

## 5e. Versão 2.4 entregue (2026-10-05): App build 37277483627 (IPA `PersonalTrainer-for-resigning` até 2026-10-08T07:33Z), Core tests 37277483632, os dois verdes em `ci/v8-final` (955d7ec); `main` com o merge de `v8/integration`

- **Entregue:** atividades fora do app (RF-53, SPEC §7.17 X1–X8: registro, fixas, "Também hoje", Metas com "Fora do app", encaixe e recuperação), as pendências da 2.1 à 2.3 (lista em `docs/V24-CONTRACT.md`) e as 78 guias "Como fazer" que faltavam (133 no catálogo).
- **Revisão da integração:** 11 achados. Corrigidos: A1/B-1 (major: o lembrete C8 agora vê equilíbrio e mobilidade registrados em "Fora do app"), B-2 (major: o Início mostra o nome e o detalhe do cartão da tela Hoje; com um plano só, a sessão só de aeróbico diz "30 min" também na tela Hoje), A2 (arquivo das atividades ilegível é guardado ao lado), A3 (o motivo "faltam lugares" desconta as fixas), A4/B-4 (apagar o registro do C8 desfaz a vez nas Metas; texto da confirmação), A5 ("Atividades fixas" na aba Plano também sem objetivo), B-3 (rodapé das Metas) e B-6 (a confirmação da importação cita as atividades). Rejeitado: B-5 ("Hoje é dia de descanso." com o cartão "Também hoje" embaixo é o desenho aprovado, DESIGN §9 itens 3 e 8; mudar a frase é decisão do dono).
- **No `main` do repositório local** havia duas edições soltas (repositório e teste do Início, já contidas no `v8/integration`); foram guardadas no `git stash` ("stray edits in main before the v2.4 merge") antes do merge, e podem ser descartadas.
- **Feito depois do merge:** a página da Amanda (`docs/install/instalar-magister.html`) aponta para o run 37277483627, diz "versão 2.4", vale até 8 de outubro, troca "Resistência" por "Cardio" e ensina a registrar atividades fora do app (Início → Esta semana → Registrar atividade; Plano → Atividades fixas). Artifact YExae7s4NkzJqLzSQuHrvH republicado (Version 4) e PDF refeito com `build-pdf.ps1` (7 páginas). As folhas dos lotes 4 a 7 foram enviadas ao dono (T6.8).
- **Próximo:** o dono instala o IPA do run 37277483627 pelo Impactor, testa e confere as folhas 4 a 7. Abertos para a próxima versão: o texto fixo do C1 ("dia do programa", "cargas 15% menores") não serve para um plano só de Cardio; `BackupDocument.validate()` não confere as atividades; a frase "Hoje é dia de descanso." com "Também hoje" embaixo (B-5) espera decisão do dono; C11 (SchemaV3), o app do Watch (M3) e o dia D de tiros curtos continuam fora.

### Histórico da 2.4 (2026-10-04)

Pedido do dono: "gere a próxima versão já com tudo que está pendente". O workflow `wf_f96cfe1b-071` cobre: o arquiteto reúne as pendências (item 19 das notas, os achados adiados da 2.3 e os [ ] antigos do TASKS) em `docs/V24-CONTRACT.md`; depois vêm os worktrees `pt-wt/w8-*`, `v8/integration` → `ci/v8-final`, revisão, correção e merge no main. **Ao retomar** (se o limite interromper): `Workflow({scriptPath: <script do run>, resumeFromRunId: "wf_f96cfe1b-071"})`; depois, IPA do run final e a página e o PDF da Amanda (`docs/install/` + `build-pdf.ps1` no scratchpad).

Contrato escrito: `docs/V24-CONTRACT.md` (lista das 31 pendências com a decisão de cada uma, 12 tarefas `v8/*` e o integrador), com o andaime T10.0 no `main` e a SPEC (RF-53, §7.17, decisão 21), o DESIGN 1.5 e o TASKS (seção "Versão 2.4") atualizados.

## 5f. Lançamento na App Store (2.5), em preparo desde 2026-10-05

- **Decisões do dono:** lançar grátis na App Store do Brasil; nome na loja "Magister: Treino com Ciência"; "Dados não coletados"; avisos só o indispensável; pedido de avaliação depois de 1 semana, o menos invasivo possível. Registro: SPEC decisão 22 e §7.18 (L1–L8), owner notes item 20, TASKS milestone M6 (T11.0–T11.10).
- **Plano completo** (respostas verificadas, fases com datas, custos, riscos, o que é do dono e o que é do Claude): artifact privado https://claude.ai/artifact/NMWbKJ3ZDkVi1KUw4DdcxE. Lançamento sugerido em 05/01/2027, com beta no TestFlight em novembro e dezembro.
- **Feito:** T11.0 (documentos) e T11.1 [PROJ] (CI menor), `main` 563d1e7. Em push para `ci/**`, o App build roda os testes e só gera o IPA em run manual, em branch terminado em `-final` ou com `[ipa]` num commit que muda algum arquivo fora da documentação; commit só de documentação não dispara nada (runs 37314805402 sem IPA, 10 min; 37316606216 com IPA, 13 min).
- **Próximo, sem bloqueio do dono:** T11.2 (PrivacyInfo.xcprivacy), T11.3 [PROJ] (project.yml da loja, sem bundle ID), T11.4 (tirar o sideload do app), T11.5 (Sobre e Privacidade), T11.6 (pedido de avaliação).
- **Do dono:** inscrição no Apple Developer Program; busca e pedido de marca no INPI; domínio e e-mail de suporte; fechar o repositório. Antes de fechar, instalar o GitHub CLI e fazer login no terminal dele (`winget install GitHub.cli` e `gh auth login`), porque com o repositório privado os resultados do CI só podem ser lidos com login; o agente usa `gh api` sem ver o token.
- **Pendentes do dono:** subtítulo da loja, bundle ID da loja, classificação de idade, modelo e conteúdo do plano pago (decisão 13 em revisão).

