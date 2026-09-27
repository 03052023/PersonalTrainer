# SPEC — Personal Trainer Automático (iPhone + Apple Watch)

Versão 0.1 · 2026-09-22 · Uso pessoal (um único usuário). Revisão 2.2 · 2026-09-27: simplificação pedida pelo dono (decisão 18; contrato `docs/V22-CONTRACT.md`).

Este é o documento de **produto e regras de domínio**. A arquitetura técnica está em [ARCHITECTURE.md](ARCHITECTURE.md), o plano de execução em [TASKS.md](TASKS.md) e as regras para agentes de código em [AGENTS.md](AGENTS.md).

---

## 1. Objetivo

Abrir o app na academia e **não precisar pensar**. O app diz:

1. qual treino fazer hoje;
2. quais exercícios, em que ordem;
3. quantas séries, quantas repetições e qual carga em cada uma;
4. quanto descansar.

Depois que cada série é registrada (carga e repetições; um toque grava a meta de hoje), o app recalcula **automaticamente e de forma determinística** a prescrição do próximo treino. Não existe etapa manual de "planejar a próxima semana".

## 2. Princípios de projeto

| # | Princípio | Consequência prática |
|---|-----------|----------------------|
| P-1 | Zero decisões na academia | A tela inicial já é o treino do dia com tudo preenchido. Um toque para iniciar; na sessão, um toque por série (bolinha) ou por exercício ("Feito"). A sessão é uma ficha para consultar (RF-44). |
| P-2 | Tudo determinístico, sem IA | Mesma entrada → mesma prescrição e mesma sugestão. Toda regra é explícita, numerada na SPEC, testada por tabela e auditável na tela ("por que isso apareceu"). Decisão de 2026-09-23: não há LLM em nenhuma fase. |
| P-3 | Offline-first | Todas as funções principais funcionam sem rede. Nenhum backend, nenhuma API paga. |
| P-4 | iPhone é a fonte da verdade | O Apple Watch é um cliente fino que espelha a sessão ativa e envia eventos. Não há dois bancos de dados a reconciliar. |
| P-5 | Dados são sagrados | Cada série é persistida no momento em que é concluída. Exportação completa em JSON a partir do M2. |
| P-6 | Frequência cardíaca é informação, não controle | FC é registrada e exibida, nunca usada para prescrever carga/volume (ver §7.6). |
| P-7 | Simplicidade adequada a app pessoal | Sem contas, sem sync em nuvem, sem localização, sem App Store. Instalação pessoal a validar via compilação hospedada e assinatura local no Windows (T0.0), sem assinatura paga. |

## 3. Escopo

### 3.1 Dentro do escopo — v1 (Milestones M0–M2, iPhone)

- Programa de treino com dias (ex.: A/B/C) e exercícios com faixa de repetições, séries, RIR alvo e descanso.
- Tela inicial mostrando o próximo treino já prescrito (exercícios, séries, reps, cargas).
- Sessão ativa: registrar carga e reps de cada série (desde a 2.2, um toque grava a meta de hoje; o RIR fica interno, RF-41); pular/substituir exercício.
- Timer de descanso com notificação local e haptic.
- Duração da sessão, tonelagem, número de séries.
- Histórico completo de sessões e detalhe por sessão/exercício.
- Motor de progressão automático (dupla progressão, §7.2).
- Seleção automática do próximo treino (rotação, §7.3).
- Painel de frequência semanal por grupo muscular (§7.4).
- HealthKit: gravar `HKWorkout` (treino de força) ao finalizar e ler amostras de FC do intervalo da sessão para exibir média/máxima (se o Watch estava no pulso, mesmo sem app no Watch).
- Catálogo de exercícios editável (nome, grupo muscular, equipamento, incremento de carga, anotações de máquina: banco, assento, pino).
- Edição mínima do programa (trocar exercício, ajustar faixa de reps/séries/RIR/descanso).
- Backup/restauração em JSON via app Arquivos.

### 3.2 Fase Apple Watch — M3

- App companion (não independente) que espelha a sessão ativa.
- Registrar séries pelo relógio (Digital Crown + botões grandes).
- Timer de descanso com haptics no pulso.
- `HKWorkoutSession` no relógio: FC ao vivo, tela sempre ativa, gravação do `HKWorkout` pelo relógio.
- Sincronização confiável via WatchConnectivity, tolerante a iPhone fora de alcance (armário).

### 3.3 Futuro — M4+

- Seleção do próximo treino por frequência semanal e recuperação (≥48 h por grupo).
- Detecção e geração automática de semana de deload.
- Troca automática de programa ao fim do mesociclo, preservando cargas por exercício.
- Revisão periódica com sugestões de programa aceitas ou recusadas pelo usuário (§7.8).
- Saúde aeróbica e recuperação (M5, §7.10): minutos aeróbicos semanais vs. meta, VO2max, HRV, FC de repouso, sono, e sugestões como "use o Watch à noite" e onde encaixar o aeróbico sem prejudicar a musculação.

### 3.4 Fora do escopo (explicitamente)

Backend, contas, sync em nuvem/CloudKit, funções sociais, nutrição, prescrição detalhada de sessões de cardio (o aeróbico é feito com o app Exercício do Watch e lido pelo HealthKit), vídeos de exercícios, planos pagos, Android, layout de iPad, publicação na App Store, localização para outros idiomas (UI em pt-BR fixo), **qualquer uso de IA/LLM**.

## 4. Contexto de uso

- Um usuário, academia comercial (máquinas, barras, halteres, cabos), unidades em kg, interface em português do Brasil.
- Sessões de 45–90 min, 3–5 vezes por semana.
- iPhone com iOS 18+ e Apple Watch com watchOS 11+ (ajustar aos aparelhos reais; ver ARCHITECTURE §2).
- O celular pode ficar no armário durante a fase Watch; o relógio deve funcionar sozinho durante a sessão.

## 5. Fluxos principais

**F1 — Abrir o app.** A tela Hoje exibe no topo o objetivo (flor, nome e "Trocar"), o dia ("Dia B — Inferior", com menu para escolher outro), "5 exercícios · ≈ 55 min" com a chave "Em casa", a lista com a meta de hoje em palavras ("3 séries de 10 · 60 kg") e um botão **Começar**. Se há uma sessão em andamento, o botão vira **Retomar** (v2.2, RF-01).

**F2 — Executar a sessão (v2.2, RF-44).** A sessão é uma ficha com todos os exercícios, cada um com a meta de hoje em letra grande ("10 repetições · 60 kg"), uma bolinha por série e "Feito". Tocar numa bolinha vazia grava 1 série como prevista e inicia o timer de descanso; "Feito" grava as séries que faltam. Ao zerar o descanso, notificação/haptic. Tocar numa bolinha cheia corrige a série (carga, repetições, apagar). A série seguinte volta à meta de repetições; a carga repete a da série anterior.

**F3 — Máquina ocupada.** Na folha "Informações do exercício" (RF-47), o usuário pode **pular** o exercício (fica registrado como pulado) ou **substituir** por outro do catálogo com o mesmo padrão de movimento (RF-34). A substituição vale só para esta sessão.

**F4 — Concluir.** Botão **Concluir**: com tudo marcado, vai direto ao resumo; faltando exercícios, pergunta uma vez (RF-44 e) → resumo "Sessão concluída" (duração, exercícios feitos, séries, FC média/máx se disponível; a tonelagem fica no Histórico) → sessão marcada como concluída → HealthKit recebe o treino (M2) → a tela Hoje já mostra o próximo treino recalculado.

**F5 — Histórico.** Lista de sessões por data; detalhe com cada exercício e cada série; por exercício, evolução de carga (M2).

**F6 — Relógio (M3).** Ao iniciar no iPhone, o relógio mostra a mesma sessão. Ao iniciar no relógio, o iPhone é notificado. Séries registradas em qualquer um aparecem no outro. FC ao vivo no relógio.

## 6. Requisitos funcionais

| ID | Requisito | Milestone |
|----|-----------|-----------|
| RF-01 | Exibir o próximo treino com todos os exercícios e prescrições sem intervenção do usuário. Desde a 2.2 (tela Hoje enxuta, DESIGN §9): cada linha mostra número, nome e a meta de hoje em palavras ("3 séries de 3 · 62,5 kg"; peso do corpo sem carga, RF-46); o selo da nota só aparece com novidade (Primeira vez, Carga maior, Tentar de novo, Carga menor, Retorno, Semana leve; "Manter" não tem selo) e abre o "Por quê?"; tocar na linha abre "Informações do exercício" (RF-47). Não aparecem RIR, descanso, nome do programa nem o selo repetido do objetivo; o descanso fica na ficha. Do diálogo (§7.11), só a mensagem principal, com "Ver todas (N)"; o painel "Esta semana" (RF-17) fica no Histórico. | M1 · v2.2 |
| RF-02 | Iniciar, retomar e finalizar uma sessão. Só pode existir uma sessão em andamento. | M1 |
| RF-03 | Registrar por série: carga (kg, passo = incremento do exercício), repetições, hora. RIR (0–5) e aquecimento continuam no esquema, nos eventos e no backup, e as séries antigas os mantêm, mas desde a 2.2 a interface não pede nem mostra nenhum dos dois: toda série nova grava `rir = nil` e `isWarmup = false` (decisão 18; RF-41; RF-44). | M1 · v2.2 |
| RF-04 | Cada série nova grava a meta de repetições de hoje (`prescribedTargetReps`; 0 = sessão antiga, vale `repMin`). A carga é, nesta ordem: a escolhida tocando no número da ficha; senão, a da série anterior do exercício nesta sessão; senão, a prescrita; em peso do corpo sem carga, 0 (P8). Mudança da 2.2: as repetições não copiam mais as da série anterior, voltam sempre à meta; a carga continua copiando. | M1 · v2.2 |
| RF-05 | Timer de descanso com duração do exercício, iniciado ao concluir a série, com notificação local ao terminar mesmo com app em segundo plano. | M1 |
| RF-06 | Persistir cada série no momento da conclusão. Matar o app não perde nenhuma série concluída. | M1 |
| RF-07 | Recalcular a prescrição de cada exercício a partir do histórico conforme §7.2 ao finalizar a sessão. | M1 |
| RF-08 | Selecionar o próximo dia do programa conforme §7.3. | M1 |
| RF-09 | Histórico: lista de sessões e detalhe com séries. | M1 |
| RF-10 | Pular exercício na sessão. | M1 |
| RF-11 | Substituir exercício por outro do catálogo (mesmo grupo primário), apenas para a sessão. | M2 |
| RF-12 | Exibir duração da sessão, total de séries de trabalho, exercícios realizados (≥ 1 série de trabalho) e tonelagem (Σ carga × reps das séries de trabalho). Desde a 2.2, o resumo ao concluir ("Sessão concluída") mostra duração, "Exercícios X de Y", séries e FC; a tonelagem fica só no detalhe da sessão no Histórico. | M2 · v2.2 |
| RF-13 | Gravar `HKWorkout` do tipo treino de força ao finalizar, com início/fim reais. Exatamente um `HKWorkout` por sessão. Se já existe no HealthKit um treino de força de outro app (ex.: app Exercício do Watch) sobrepondo ≥ 50 % do intervalo da sessão, **vincular** esse treino em vez de criar outro. | M2 |
| RF-14 | Ler amostras de FC do HealthKit no intervalo da sessão e exibir média e máxima no detalhe. | M2 |
| RF-15 | Editar catálogo de exercícios: nome, grupos musculares, equipamento, incremento, anotações de máquina. | M2 |
| RF-16 | Editar programa: trocar exercício, ajustar séries/faixa/descanso/carga inicial. Desde a 2.2, a edição fica em Plano > "Ajustar exercícios" e o RIR alvo não aparece nem é editável: continua o do objetivo (§7.9), e salvar mantém o valor gravado. | M2 · v2.2 |
| RF-17 | Painel de frequência semanal por grupo muscular (realizado / meta). Desde a 2.2, fica no topo do Histórico ("Esta semana"), não na tela Hoje. | M2 · v2.2 |
| RF-18 | Exportar e importar todos os dados em JSON. | M2 |
| RF-19 | Editar/excluir uma série após registrada; abandonar sessão. | M2 |
| RF-20 | Watch: exibir sessão ativa, exercício e série atuais; registrar série; timer com haptics. | M3 |
| RF-21 | Watch: `HKWorkoutSession` com FC ao vivo; salvar `HKWorkout` pelo relógio; iPhone não duplica. | M3 |
| RF-22 | Sync iPhone↔Watch tolerante a desconexão; nenhum evento perdido; nenhuma série duplicada. | M3 |
| RF-23 | Seleção do próximo treino por frequência/recuperação (§7.3 v2). | M4 |
| RF-24 | Deload automático (§7.5). | M4 |
| RF-25 | Troca automática de programa ao fim do mesociclo. | M4 |
| RF-26 | Revisão periódica (§7.8): relatório determinístico e sugestões com aceitar/recusar na abertura do app. | M4 |
| RF-27 | Minutos aeróbicos da semana por intensidade (moderado/vigoroso), lidos dos treinos do HealthKit, contra a meta (padrão OMS 150 min moderados-equivalentes). | M5 |
| RF-28 | VO2max estimado pelo Watch: último valor, tendência de 90 dias, faixa por idade/sexo; sugestão de caminhada/corrida ao ar livre quando não há estimativa recente. | M5 |
| RF-29 | Recuperação: HRV, FC de repouso e sono (médias 7 vs. 28 dias); sugestão "use o Watch à noite" quando faltam dados noturnos. | M5 |
| RF-30 | Sugestão de encaixe do aeróbico na semana, evitando interferência com treino pesado de pernas (§7.10 A5). | M5 |
| RF-31 | Card "Saúde" na Home e tela de detalhe; tudo só leitura do HealthKit, sem gravar. | M5 |
| RF-33 | Adicionar e remover exercícios de cada dia manualmente (5 é só o padrão; mínimo 1, máximo 10). | M2 |
| RF-34 | Botão "Trocar" em cada exercício (na sessão e na edição): oferece substitutos do catálogo com o **mesmo padrão de movimento** e mesmo grupo primário (ex.: supino reto com barra → supino com halteres → supino na máquina → flexão), ordenados por semelhança; na sessão vale só para aquele treino, na edição fica no programa. A folha de troca mostra **apenas** os substitutos daquele exercício, do mais ao menos parecido (o primeiro com o selo "Mais parecido"), sem o catálogo inteiro. Para trabalhar outro músculo, a pessoa usa "Adicionar exercício" e apaga o antigo (decisão do usuário, 2026-09-24). O histórico de carga de cada exercício é separado (P3); o substituto começa em calibração se nunca foi feito. | M2 |
| RF-35 | Hipertrofia com três formatos de divisão: **completo** (todo o corpo equilibrado, padrão ABC), **foco inferior** (glúteos e pernas com mais volume, superior em manutenção) e **foco superior** (peito, ombros, braços e costas com mais volume, inferior em manutenção). Volume do foco no topo da faixa de §7.9; manutenção ≈ 1/3 do volume (Bickel 2011). Na interface (2.2, RF-45) eles são os formatos do objetivo Hipertrofia: **Corpo todo**, **Mais pernas e glúteos** e **Mais tronco e braços**. | M2 · v2.2 |
| RF-37 | Diálogo do app (§7.11 C1–C8): feed de mensagens na Home, destaque na abertura, ações aceitar/recusar, registro de decisões. | M4 (nesta versão) |
| RF-38 | Deload automático com opção de desfazer (§7.5, §7.11 C1): sessões marcadas `isDeload`, prescrição reduzida, ignoradas pela progressão. | M4 (nesta versão) |
| RF-39 | Seleção do próximo dia por frequência semanal e recuperação de 48 h (S5–S7), ativável em Ajustes > "Mais opções" > "Escolher o dia pela semana" (padrão: ligado quando o programa tem ≥ 4 dias). | M4 (nesta versão) |
| RF-40 | **Como fazer** (pedido do usuário, 2026-09-24; estilo aprovado na v2 do protótipo, `docs/design/exercise-guides/compare-v2.png`): botão "Como fazer" (símbolo `play.circle`) em cada exercício que tem guia, na sessão (ao lado do nome), na Home (linha da prescrição) e no catálogo. Abre uma folha com:<br>(a) uma ilustração **própria, minimalista e sem realismo**: manequim liso, sem músculos, rosto ou roupa marcada, com o equipamento só sugerido. Ela é desenhada pelo app a partir de números de pose (§7.12) e anima em loop lento entre a posição inicial e a final, com botão Pausar. Para ficar clara (§7.12 E9), só as partes do corpo que se movem ficam em acento forte; uma seta mostra o caminho; cada posição tem uma legenda curta; o título vem com "Trabalha: …";<br>(b) **3 passos curtos e 2 erros comuns** em pt-BR, com palavras próprias.<br>Todos os exercícios usam a mesma figura, a mesma escala, as cores do DESIGN §3 e §12 e o mesmo formato. **Origem e licença:** nenhuma foto, vídeo, GIF ou desenho de terceiros e nenhuma imagem gerada por modelo de imagem. A arte é obra do projeto, gerada em tempo de execução a partir de `Resources/Seed/exercise-guides.v1.json`, então não há atribuição a exibir. **Offline:** tudo vem no app (cerca de 150 KB de dados, nenhuma imagem). **Acessibilidade:** com Reduzir Movimento, as posições ficam paradas lado a lado, com a inicial em fantasma; para o VoiceOver, a ilustração é um único elemento com descrição própria, seguido dos passos e dos erros; os textos seguem o Dynamic Type; figura e implemento têm contraste ≥ 3:1 nos modos claro e escuro. Exercício sem guia (personalizado) não mostra o botão. | v2.1 |
| RF-42 | **Modo casa** (pedido do usuário, 2026-09-24): chave "Em casa" no cartão da tela Hoje (desde a 2.2, só ali; saiu de Ajustes).<br>Ligada, cada exercício da sessão planejada é trocado pelo equivalente que dá para fazer em casa sem equipamento específico: peso do corpo ou objetos comuns, como mochila com peso, garrafas de água, cadeira firme, degrau ou toalha (novo equipamento `household`).<br>A escolha é determinística (§7.13 H1–H4): o mesmo padrão de movimento e um grupo primário em comum, ordenados como no RF-34. Sem equivalente, vale o mesmo grupo primário; se nem isso existir, o exercício sai da sessão, com aviso.<br>O programa não muda: desligar a chave volta os exercícios da academia. Cada exercício tem o próprio histórico (P3), então quem nunca fez a versão de casa começa em calibração. O alvo (séries, faixa, RIR, descanso) vem do exercício original. O cartão do dia mostra "Em casa". Na sessão, o botão Trocar oferece só alternativas de casa. | v2.1 |
| RF-43 | **Medida do exercício** (achado de 2026-09-24): cada exercício do catálogo tem uma medida, `reps` (padrão), `seconds` (isometrias, pranchas) ou `steps` (carregadas). Prescrição, registro da série, histórico e resumos mostram a unidade certa ("3 × 20–40 s", "30 passos"). A progressão (P4–P6) usa o mesmo número com a mesma lógica. A tonelagem (RF-12) só soma exercícios medidos em repetições: carga × segundos ou carga × passos não é tonelagem. A medida e a marca "dá para fazer em casa" vêm do catálogo do seed pelo `slug`, sem mudar o esquema de dados; exercício personalizado usa `reps` e não entra no modo casa. | v2.1 |
| RF-41 | **RIR interno, invisível ao usuário** (decisão do dono, 2026-09-27, decisão 18; substitui o "RIR explicado" da 2.1). O RIR continua no domínio: `targetRIR` no programa e no snapshot da sessão, `SetResult.rir` nas séries antigas, P2/P4/§7.5 e R2 como estão. Mas a pessoa não vê nem escolhe nada sobre ele: saem o seletor da série, "O que é RIR?", o cartão da primeira sessão, o RIR alvo nas prescrições ("RIR 2", "pare com 2 sobrando", inclusive na leitura do VoiceOver), o RIR das séries no Histórico e o campo "RIR alvo" na edição do programa. Séries novas gravam `rir = nil` (decisão 10: sem o bônus de P4). Única marca indireta: na primeira vez de um exercício com carga (P2), a dica concreta "Escolha uma carga que daria para levantar umas N vezes. Hoje faça M.", com N = meta + RIR alvo do snapshot, sem citar RIR. A explicação `topic.rir` continua só na lista de Referências científicas. | v2.1 · v2.2 |
| RF-44 | **Sessão como ficha de consulta** (pedidos S5, S7, S8 e S9 do dono; decisão 18). A sessão ativa é uma lista rolável com todos os exercícios, na ordem e na paleta do DESIGN §3 (fundo `background`, cartões `surface`, tint `accent`).<br>(a) **Cartão:** número, nome (toque abre RF-47), selo da nota (só com novidade; toque abre o "Por quê?"), a meta de hoje em letra grande ("3 repetições · 62,5 kg", "30 passos · 22,5 kg", "15 segundos"; nunca a faixa), uma bolinha por série, "✓ Feito" e, em letra pequena, "3 séries · descanso 4 min". Nada de RIR. Estados: pendente, atual (o primeiro pendente, com borda `accent`), feito ("✓ 5, 5, 4 · 60 kg") e pulado.<br>(b) **Toques** (tudo pelo `SessionCoordinating`, R4): bolinha vazia = 1 `setLogged` com a meta de hoje e a carga de RF-04, `rir = nil`, `isWarmup = false`, e inicia o descanso do exercício; bolinha cheia = "Corrigir série" (carga, repetições, apagar; `setUpdated` mantém o `rir` já gravado, ou `setDeleted`); "Feito" = um `setLogged` para cada série que falta até `prescribedSets`, sem iniciar descanso; tocar na carga = teclado numérico para a carga de hoje, que vale para as próximas séries do exercício (P10).<br>(c) **Primeira vez com carga** (P2 sem carga, equipamento diferente de peso do corpo): o cartão pede a carga uma vez pelo teclado, com a dica de RF-41; bolinhas e "Feito" só funcionam com carga maior que 0. Substitui o aviso "Registrar com 0 kg?". Peso do corpo pula este passo (RF-46).<br>(d) **Aquecimento:** a chave "Aquecimento" sai. No topo da ficha fica a linha fixa "Aqueça com 1 ou 2 séries leves antes dos exercícios com carga. Não precisa marcar." Aquecimentos antigos continuam no Histórico e fora da progressão (P1).<br>(e) **Concluir:** com todo exercício não pulado com as séries prescritas, "Concluir" vai direto ao resumo. Faltando algum, pergunta uma vez "Faltam N exercícios", com os nomes: "Marcar como feitos, como previsto" (o mesmo que "Feito" em cada pendente que tem carga; os de primeira vez sem carga ficam de fora), "Encerrar só com o que marquei" (conclui; P7 avalia o que foi feito) e "Voltar ao treino". Sem nenhuma série marcada, as opções são "Marcar como feitos, como previsto", "Sair sem registrar" (abandona) e "Voltar ao treino".<br>(f) **Descanso** preso no topo, sem empurrar a lista, com "+30 s" e "Pular".<br>(g) **Tela acesa** só enquanto a ficha está aberta e o app em primeiro plano (`isIdleTimerDisabled`); o resumo e as outras telas seguem o bloqueio do iPhone.<br>(h) **Resumo** "Sessão concluída" com a flor do objetivo, duração, "Exercícios X de Y", séries, FC quando houver e "A próxima sessão já está pronta: Dia B". | v2.2 |
| RF-45 | **Objetivo = plano** (pedidos S2 e S3). Na interface há um conceito só, o objetivo; cada objetivo tem o seu plano, que é um programa com aquele `goal`. A Hipertrofia tem 3 formatos (RF-35). Regra de escolha, por objetivo e formato: o programa ativo, se tiver aquele objetivo; senão, o do seed; senão, o primeiro com aquele `effectiveGoal`. Um programa ativo de Hipertrofia que não é um dos 3 formatos (cópia, o antigo Empurrar/Inferior/Puxar) aparece como formato extra, com o próprio nome, só enquanto estiver ativo.<br>A folha "Seu objetivo" abre do topo da tela Hoje ("Trocar"), da aba **Plano** ("Trocar objetivo") e no primeiro uso ("Qual é o seu objetivo?", um passo só, com o aviso de técnica do Combate, §7.9). Ela mostra a flor e os 5 objetivos na ordem das pétalas (nome, subtítulo, dias, "Por quê?"); no tocado, o formato (só na Hipertrofia) e a prévia do Dia A. O botão diz o que vai acontecer ("Trocar para Hipertrofia"), com a frase "Suas cargas ficam guardadas: cada exercício tem o próprio histórico. A próxima sessão será o Dia A." Trocar chama `ProgramRepositoring.activate` (S2 recomeça no Dia A; P3 é por exercício). Com sessão em andamento, a troca fica bloqueada.<br>A aba Programa vira **Plano**: o objetivo com "Trocar objetivo", a semana inteira para consultar (dias com os exercícios, o próximo marcado) e, por último, "Ajustar exercícios" (RF-16, RF-33, RF-36) e o catálogo. Saem da interface a lista de programas, Renomear, Duplicar, Apagar, o seletor de objetivo dentro do programa e o diálogo "Aplicar padrões?". Nada é apagado do banco nem do backup. | v2.2 |
| RF-46 | **Peso do corpo sem carga** (pedido S6). Exercício com `equipment = bodyweight` e carga prescrita 0 ou vazia não mostra carga nenhuma (nem "0 kg", nem "—", nem stepper) na tela Hoje, na ficha, na folha de informações e no Histórico; a série grava 0 (P8), sem pedir confirmação. Se a progressão prescrever carga adicional (P4/H4 no topo da faixa), aparece "+ 2,5 kg extra", que a pessoa pode mudar tocando no número. `household` (mochila, garrafas) continua mostrando a carga. O motor não muda: P2 segue devolvendo carga vazia e a tela resolve. | v2.2 |
| RF-47 | **Informações do exercício** (pedido S9). Folha só de leitura, aberta ao tocar no exercício na tela Hoje e na ficha: "Hoje" em frase ("3 séries de 3 repetições com 62,5 kg. Descanso de 4 min entre as séries."); "Por que esta carga", com os números da última sessão e o "Por quê?" com as referências (RF-32); "Da última vez" (data e séries, lido pelo `SessionPlanning`, sem `@Query`); notas da máquina; e, só na ficha, "Máquina ocupada? Trocar por outro parecido" (antes da 1ª série, RF-34) e "Pular este exercício" (RF-10). Nada de RIR. "Como fazer" (RF-40) entra aqui quando existir. | v2.2 |
| RF-36 | Programas com qualquer número de dias (A, B, C, D, E… de 1 a 7): adicionar, remover, renomear e reordenar dias na edição de programa; a rotação (S1–S2) já funciona com N dias. Programas do seed podem ter 4 ou 5 dias quando o objetivo pede (ex.: foco inferior/superior, combate com dia de condicionamento), sempre com frequência ≥ 2×/semana por grupo quando possível (Schoenfeld 2016). | M2 |
| RF-32 | Botão "Por quê?" em notas de prescrição, metas e sugestões, mostrando a regra e as referências científicas completas do catálogo `references.v1.json` (§7.9). | M2 (catálogo e notas), cresce a cada milestone |

## 7. Regras de domínio

### 7.1 Conceitos

- **Exercício (catálogo)**: movimento + equipamento. Tem `slug` estável (ex.: `leg-press-45`), grupos musculares primário/secundários, tipo de carga (kg, placas, nível) e **incremento mínimo** (`loadIncrement`: 2,5 kg barra/halter; 5 kg máquina de placas; 1 nível).
- **Programa**: conjunto ordenado de **Dias** (A, B, C…). Cada Dia tem uma lista ordenada de **Exercícios do Programa** com parâmetros: `sets` (S), `repMin`/`repMax`, `targetRIR` (T), `restSeconds`, `startingLoad` (opcional).
- **Prescrição**: o que o motor manda fazer hoje para um exercício: carga, S, faixa de reps, meta de reps, RIR alvo, descanso e uma **nota** (`calibrate`, `increase`, `hold`, `retry`, `decrease`, `returning`, `deload`).
- **Sessão**: uma execução de um Dia, com status `inProgress`, `completed` ou `abandoned`. Contém **Exercícios da Sessão** (snapshot da prescrição) e **Séries** registradas.
- **RIR** (Reps in Reserve): quantas repetições faltavam para a falha. É a métrica de esforço primária do motor. RPE, quando exibido, é `10 − RIR`. Só RIR é armazenado. Desde a 2.2 ele é interno: a interface não o mostra nem o pede (RF-41), e as séries novas não têm RIR.
- **Histórico é por exercício, não por programa.** Trocar de programa não zera cargas.

### 7.2 Motor de progressão v1 — dupla progressão

Aplicado por exercício, independentemente dos demais.

| Regra | Descrição |
|-------|-----------|
| **P1 Séries de trabalho** | Só séries com `isWarmup = false` entram na avaliação. |
| **P2 Sem histórico** | Se `startingLoad` definido → carga = `startingLoad`, meta = `repMin`, nota `calibrate`. Senão → carga vazia; o usuário digita na 1ª série; RIR alvo = T + 1. (Na interface da 2.2: a ficha pede a carga pelo teclado, RF-44 c; em peso do corpo a carga vazia vira 0, RF-46.) |
| **P3 Referência** | Avalia-se a **última sessão concluída ou abandonada** em que o exercício teve ≥ 1 série de trabalho e que **não** foi deload (§7.5). Carga de referência **L** = moda das cargas das séries de trabalho dessa sessão (empate → maior). Se L não é múltiplo de inc (override P10), a base para P4–P6 é arredondar↓(L, inc); a comparação "mesma carga" de P6 usa L bruto. O motor ordena o histórico por data (desempate por id da sessão) e aceita entradas em qualquer ordem. |
| **P4 Sucesso → subir** | Se nº de séries de trabalho ≥ S **e** todas com reps ≥ `repMax` → nova carga = L + inc, meta = `repMin`, nota `increase`. Se além disso min(RIR) ≥ T + 2 → L + 2·inc. |
| **P5 Manter → mais reps** | Se todas as séries com reps ≥ `repMin` mas P4 não vale → carga = L, meta = min(`repMax`, menor reps da última sessão + 1), nota `hold`. |
| **P6 Falha** | Se alguma série de trabalho com reps < `repMin`: primeira ocorrência → carga = L, meta = `repMin`, nota `retry`. Se a sessão anterior a essa (mesmo exercício) também foi falha **na mesma carga L** → nova carga = **min**(arredondar↓(L × 0,9, inc), L − inc), respeitando P8, nota `decrease`. Ou seja: corte de 10 % arredondado para baixo e **pelo menos um incremento** de queda (ex.: L = 60, inc = 2,5 → 52,5; L = 10 → 7,5; L = 5 → 2,5 pelo piso). |
| **P7 Séries incompletas** | Se séries de trabalho < S, não há sucesso (P4). Avalia-se P5/P6 sobre as realizadas. Se 0 séries de trabalho, a sessão é ignorada e usa-se a anterior. |
| **P8 Arredondamento** | Toda carga prescrita é múltiplo de inc. Mínimo = inc; para `equipment = bodyweight` o mínimo é 0 (peso corporal puro) e inc vale para a carga adicional (colete, cinto). Todo exercício do catálogo tem inc > 0. |
| **P9 Retorno após pausa** | Se a última sessão em que o exercício teve ≥ 1 série de trabalho (**incluindo** sessões de deload) tem > 21 dias em relação a `now` → carga = arredondar↓(L × 0,9, inc) respeitando P8, meta = `repMin`, nota `returning`. Prevalece sobre P4–P6. L continua vindo da última sessão não-deload (P3). |
| **P10 Override** | O usuário pode alterar carga/reps na hora. Vale o registro real. Nada é corrigido retroativamente. |
| **P11 Determinismo** | Mesma entrada → mesma saída. `now` é parâmetro explícito. Sem aleatoriedade. |
| **P12 FC** | Nenhuma métrica de frequência cardíaca é entrada do motor. Garantido por tipo: a struct de entrada não tem campo de FC. |

Parâmetros padrão: S = 3, faixa 8–12, T = 2, descanso 120 s. Séries retas (mesma carga em todas as séries de trabalho). Autorregulação intra-sessão automática **não** existe em v1; o usuário ajusta a carga da próxima série manualmente se quiser.

### 7.3 Seleção do próximo treino

**v1 — rotação (M1)**

| Regra | Descrição |
|-------|-----------|
| **S1** | O programa ativo tem dias ordenados D1…Dn. |
| **S2** | Próximo = dia seguinte (na ordem de `order`) ao da última sessão `completed` ou `abandoned` com ≥ 1 série de trabalho. Se não há nenhuma, ou se o dia dessa sessão não existe mais no programa (programa editado) → D1. Após Dn → D1. `order` é único dentro do programa (invariante validado no seed). Empates de data são desfeitos pelo id da sessão (P11). Um dia ainda sem exercícios (recém-acrescentado, abaixo do mínimo de RF-33) fica fora da escolha automática até ganhar um; escolhido à mão (S4), abre, mas não inicia sessão. |
| **S3** | Se existe sessão `inProgress`, o "próximo treino" é retomá-la. Essa regra é do planejador, não do seletor: o seletor ignora sessões `inProgress`. |
| **S4** | O usuário pode escolher outro dia manualmente; a rotação segue a partir do dia escolhido (a sessão registrada nesse dia passa a ser a referência de S2). |

**v2 — frequência e recuperação (M4)**

| Regra | Descrição |
|-------|-----------|
| **S5** | Para cada dia candidato, pontuar = nº de grupos primários do dia que estão abaixo da meta semanal (§7.4). |
| **S6** | Excluir candidatos com algum grupo primário trabalhado (como primário) há < 48 h. Se todos forem excluídos, ignorar S6. |
| **S7** | Escolher maior pontuação; empate → ordem da rotação (S2). |

### 7.4 Frequência semanal por grupo muscular

- Grupos: peito, costas, ombros, bíceps, tríceps, quadríceps, posteriores, glúteos, panturrilhas, core.
- Semana começa na segunda-feira (configurável).
- Um grupo conta **1** em uma sessão concluída se houve ≥ 1 exercício com esse grupo como **primário** e ≥ 1 série de trabalho registrada **nesse exercício**. Secundário não conta (v1). (Na implementação, `SessionSummary.primaryMusclesTrained` já é construído com essa regra; o relatório semanal conta cada sessão uma vez.)
- A semana é o intervalo semiaberto [segunda 00:00, próxima segunda 00:00) no fuso do usuário; uma sessão pertence à semana de `startedAt`.
- Meta padrão: 2×/semana por grupo; configurável por grupo.
- Não há grupo "pescoço": exercícios de pescoço (objetivo Combate) usam costas (trapézio) como grupo primário e contam para costas.
- v1 (M2) só **exibe** realizado/meta. v2 (M4) usa isso na seleção (S5–S7).

### 7.5 Deload (M4)

Gatilhos (qualquer um; se (a) e (b) valem juntos, vale (a)):
- **(a) Muitas reduções:** ≥ 50 % das prescrições atuais do programa (uma por exercício, sem contar `calibrate`) têm nota `decrease`. `retry` e `returning` não contam. Fronteira exata: 2 × reduções ≥ total.
- **(b) Programado:** passaram N semanas (padrão 6, configurável; N ≤ 0 desliga) desde o início do último deload ou, se nunca houve deload, desde a primeira sessão. Conta tempo decorrido (N × 7 dias), pausas incluídas.
- **(c) Manual.**

**Rearme (decisão de 2026-09-23):** depois de um deload, (a) só considera reduções vindas de sessões **posteriores ao fim do último deload**. Sem isso, as mesmas notas `decrease` de antes do deload disparariam outro deload logo em seguida, porque as sessões de deload não mudam a prescrição normal (P3). Quem aplica essa filtragem é o planejador, antes de chamar a política.

Conteúdo: durante 1 semana (uma passagem completa da rotação), cada exercício recebe séries = ⌈S × 0,6⌉ (mínimo 1), carga = arredondar↓(C × 0,85, inc) com o mínimo de P8, em que C é a carga da prescrição normal daquele dia, RIR alvo = 4, nota `deload`. Usar C em vez de L dá o mesmo resultado em `hold`/`retry`, uma carga um pouco menor em `decrease`/`returning` e até 0,85 × inc a mais em `increase`, uma diferença irrelevante numa semana leve. Sessões de deload **não** contam como falha nem sucesso para P4–P6; após o deload a prescrição volta ao estado anterior.

Duração: o deload termina quando cada dia do programa teve uma sessão `completed` com `isDeload` e ≥ 1 série de trabalho iniciada depois do início do deload. Sessão abandonada move a rotação (S2), mas não conclui a passagem. Um deload interrompido por uma pausa longa continua ativo na volta e se soma a P9.

### 7.6 Política de frequência cardíaca

FC **é usada para**: exibir ao vivo no relógio (M3); resumo da sessão (média/máx); tendências de recuperação na revisão periódica (§7.8 R6) e no painel de saúde (§7.10); intensidade do treino **aeróbico** (§7.10, uso correto da FC); opcionalmente, dica no timer ("FC abaixo de X bpm"), desligada por padrão (M3).

**Fonte da FC antes do app do Watch existir (M2):** o usuário inicia um treino "Musculação tradicional" no app Exercício nativo do Apple Watch; o relógio grava FC contínua no HealthKit e o app do iPhone lê essas amostras no intervalo da sessão (RF-14) e vincula o `HKWorkout` já existente (RF-13). Isso entrega FC por sessão sem depender da instalação do app companion.

FC **nunca é usada para**: prescrever carga, séries ou repetições; decidir deload; alterar seleção de treino.

Motivo: em musculação, FC reflete descanso, cafeína, temperatura e estresse muito mais do que prontidão muscular. Usá-la para carga produziria prescrições erráticas e não determinísticas na prática.

### 7.8 Revisão periódica e sugestões de programa (M4)

Segundo nível de recalibração, além do ajuste por sessão (§7.2): a cada `reviewIntervalWeeks` (padrão 4) ou por gatilho de deload (§7.5), o app calcula um **relatório de revisão** e, na próxima abertura, apresenta **sugestões** que o usuário aceita ou recusa. Recusar mantém tudo como está. Nada muda sozinho.

| Regra | Descrição |
|-------|-----------|
| **R1 Desempenho** | Por exercício, 1RM estimado por sessão = carga × (1 + reps/30) (Epley) sobre a melhor série de trabalho. Estagnação = sem aumento do melhor 1RM estimado em 3 sessões consecutivas do exercício. |
| **R2 Fadiga** | Sinais: proporção de séries de trabalho com RIR 0 nas últimas 2 semanas > 30 %; ≥ 50 % dos exercícios com nota `decrease` ou `retry` (§7.5 a). |
| **R3 Volume** | Séries de trabalho por grupo primário por semana (média das 4 últimas semanas completas), comparadas à faixa alvo do objetivo do programa (§7.9). Abaixo do mínimo (estritamente) → sugerir +1 série em exercícios do grupo, no máximo 2 exercícios por grupo por revisão e nunca acima de 10 séries por exercício. Acima do teto com fadiga (R2) → sugerir −1 série, com o mesmo limite e nunca abaixo de 1. Se o programa é mais novo que a janela de 4 semanas, R3 e R4 não julgam (só exibem o volume). |
| **R4 Aderência** | Sessões concluídas (≥ 1 série de trabalho) nas 4 semanas ÷ (4 × dias do programa), limitado a 1; se < 70 %, sugerir programa com menos dias antes de sugerir mais volume (suprime o "+1 série" de R3). Programa de 1 dia não recebe sugestão de menos dias. |
| **R5 Sugestões** | Deload (R2 verdadeiro, ou R1 em ≥ 50 % dos exercícios; não é sugerido com um deload em andamento); mudar a faixa de repetições para a vizinha (2 abaixo; se o mínimo ficaria abaixo de 3, 2 acima) quando o exercício está estagnado (R1) há ≥ 3 sessões, e trocar o exercício por um substituto (RF-34) quando está estagnado há ≥ 6 sessões; ajuste de volume (R3); mudança de frequência (R4); troca de programa ao fim do mesociclo (§7.11 C2, sempre opcional). Cada sugestão traz o motivo em uma frase e os números que a geraram. As contagens por sessões substituem a versão anterior "por 2 revisões seguidas", que exigiria guardar revisões passadas. |
| **R6 Sinais secundários do HealthKit** | Tendência de HRV e de FC de repouso (média de 7 dias vs. 28 dias) e horas de sono, quando disponíveis. Só **modulam** sugestões já geradas por R1–R4: HRV em queda ≥ 10 % reforça deload; HRV estável ou em alta enfraquece (a sugestão vira "opcional"). Nunca geram sugestão sozinhos, nunca alteram carga de série (P12). |
| **R7 Determinismo** | Mesmo histórico → mesmo relatório. Cada sugestão exibe a regra (R1–R6) e os números que a geraram; não há geração de texto por IA. |

Base: autorregulação por RIR/RPE (Zourdos 2016; Helms 2016); dose-resposta de volume (Schoenfeld 2017). Frequência: com o volume semanal igualado, treinar um grupo 1× ou 2×/semana dá resultados parecidos (Schoenfeld 2019); 2×/semana é um jeito prático de distribuir o volume sem sessões longas (Schoenfeld 2016; Grgic 2018). HRV: evidência limitada e inconsistente como guia de treino, majoritariamente em endurance (Bellenger 2016), por isso só modula (R6).

### 7.9 Objetivo do programa (M2)

Cada programa tem um `goal`: `hypertrophy` (padrão), `strength`, `endurance`, `longevity` ou `combat`. **Na interface, objetivo = plano** (RF-45, desde a 2.2): a pessoa escolhe o objetivo, e o plano é o programa daquele objetivo; a Hipertrofia tem 3 formatos (RF-35). O `goal` de um programa não se troca mais pela tela. Todo programa gerado por padrão tem **5 exercícios por dia** (decisão do usuário, 2026-09-23); o usuário pode adicionar ou remover na edição. O objetivo define os padrões usados pelo seed, pela edição de programa e pela revisão (§7.8):

| Objetivo | Faixa de reps (compostos / isolados) | RIR alvo | Volume alvo por grupo/semana (séries de trabalho) | Descanso (compostos / isolados) | Séries por exercício |
|----------|---------------|----------|---------------------------------------------------|----------|----------|
| Hipertrofia | 6–12 / 8–15 | 2 | 10–20 | 150 / 90 s | 3 (4 nos compostos do programa Completo) |
| Força | 3–6 / 6–10 | 2 | 6–12 | 240 / 150 s | 4 |
| Resistência muscular | 12–20 / 15–20 | 3 | 8–16 | 75 / 60 s | 3 |
| Longevidade | 8–12 / 10–15 | 3 | 6–12 | 120 / 90 s | 2 |
| Combate | 3–6 / 6–10 | 2 | 6–12 | 180 / 90 s | 3 |

Os valores são os de `GoalDefaults` (TrainerCore). Compostos são os padrões de movimento empurrar, puxar, agachar, avançar, dobradiça de quadril, elevação de quadril, carregar e explosivo; os demais são isolados. Nos isolados de Força e Combate, 3–6 repetições seriam arriscadas para articulações pequenas (por exemplo, elevação lateral), por isso usam 6–10. Carregadas e pescoço mantêm faixa e descanso próprios ao trocar de objetivo, e só o RIR muda.

**Programa Completo de hipertrofia = corpo todo** (decisão do usuário, 2026-09-23, substitui o A/B/C empurrar/inferior/puxar da decisão 8). Com 5 exercícios por dia e 3 dias, cada dia mistura superior e inferior, de modo que cada grande grupo é treinado 2×/semana, e os compostos têm 4 séries. Assim o volume semanal chega perto do mínimo de 10 séries sem sessões mais longas. Onde ainda ficar abaixo, a revisão (R3) sugere mais séries. Os formatos foco inferior e foco superior (RF-35) seguem a mesma lógica, com mais exercícios do grupo em foco.

**Longevidade** = saúde geral e envelhecimento com autonomia. Além da musculação acima, ativa metas semanais com base científica sólida, acompanhadas no painel de saúde (§7.10):

| Componente | Meta padrão | Base |
|------------|-------------|------|
| Força | 2–3 sessões/semana, todos os grandes grupos | OMS 2020 (≥ 2 dias/semana); menor mortalidade com 30–60 min/semana de força (Momma 2022) |
| Aeróbico | 150–300 min moderados-equivalentes, com ≥ 1 sessão vigorosa quando possível | OMS 2020; VO2max é forte preditor de mortalidade (Mandsager 2018) |
| Equilíbrio | 2–3×/semana, em rotinas curtas (apoio unipodal, caminhada em linha) | OMS 2020 para ≥ 65 anos; reduz quedas (Sherrington 2019, Cochrane) |
| Mobilidade/flexibilidade | 2–3×/semana, 5–10 min | ACSM: melhora amplitude de movimento; efeito fraco em prevenção de lesão, por isso sugestão leve |
| Passos | ≥ 7.000/dia | Menor mortalidade até ~7.000–10.000 passos (Paluch 2022) |
| Sono | 7–9 h | Consenso AASM/SRS |

**Combate** = preparo físico para autodefesa e luta: força máxima, potência, resistência a esforços curtos e intensos, pegada e tronco resistentes. O app prepara o corpo; não ensina técnica de luta (isso exige aula presencial) e mostra esse aviso uma vez.

| Componente | Padrão | Base |
|------------|--------|------|
| Força máxima | Compostos (agachamento, levantamento terra, supino, remada, barra) 3–6 reps, RIR 2–3, 2–3×/semana | Força máxima sustenta potência e desempenho atlético (Suchomel 2016) |
| Potência | 1–2 exercícios explosivos por treino (arremesso de medicine ball, salto, kettlebell swing), 3–5 séries de 3–5 reps, descanso completo | Treino misto força + potência maximiza potência (Cormie 2011) |
| Resistência anaeróbica | 1–2×/semana, intervalos de 20–60 s intensos com pausa curta, imitando rounds | Demandas de esportes de combate são intermitentes e de alta intensidade (James 2016; HIIT: Buchheit & Laursen 2013) |
| Pegada e tronco | Carregadas (farmer's walk), barra isométrica, anti-rotação (pallof) | Pegada e tronco são determinantes em luta agarrada (James 2016) |
| Pescoço | Isometria leve 2×/semana | Sugestão leve: evidência limitada, plausível para absorver impactos |

**Referências obrigatórias (requisito transversal, RF-32).** Toda regra, meta ou sugestão do app tem um identificador de referência. Um botão "Por quê?" em cada sugestão, meta e nota de prescrição abre a explicação curta, a regra da SPEC e as referências completas (autores, ano, título, revista, DOI). A lista vive num catálogo versionado no app (`references.v1.json`), igual ao seed. Critério de inclusão: preferir diretrizes (OMS, ACSM) e meta-análises/revisões sistemáticas; estudo isolado só quando não há síntese, sinalizado como "evidência limitada". Nenhuma regra entra na SPEC sem referência.

Equilíbrio e mobilidade aparecem como blocos opcionais de 5–10 min no fim do treino ou em dias livres; o app só registra "feito/não feito". Passos, aeróbico, VO2max e sono vêm do HealthKit. Nada disso altera a prescrição de carga (P12).

Progresso por objetivo é medido por desempenho (1RM estimado, volume) e aderência; composição corporal só entra por registro manual ou peso corporal do HealthKit, como contexto.

### 7.10 Saúde aeróbica e recuperação (M5)

Só leitura do HealthKit; o aeróbico é feito com o app Exercício do Apple Watch (ou qualquer app que grave no Saúde). Nada aqui altera a prescrição de musculação (P12).

| Regra | Descrição |
|-------|-----------|
| **A1 Minutos por intensidade** | Treinos aeróbicos da semana (caminhada, corrida, ciclismo, natação, remo, elíptico, trilha, escada, HIIT, dança) classificados minuto a minuto pela FC: moderado = 64–76 % da FCmáx (ou 40–59 % da FC de reserva quando há FC de repouso), vigoroso ≥ 77 % FCmáx (ACSM). FCmáx = 208 − 0,7 × idade (Tanaka) salvo valor informado. Sem amostras de FC, usa o tipo do treino (caminhada = moderado; corrida/HIIT = vigoroso). |
| **A2 Meta semanal** | Padrão OMS 2020: 150 min moderados-equivalentes (1 min vigoroso = 2 moderados); teto informativo 300. Configurável. Semana igual à de §7.4. |
| **A3 VO2max** | Lê `vo2Max` do HealthKit, janela de leitura de 180 dias (estimado pelo relógio em caminhada/corrida/trilha ao ar livre). Mostra último valor, tendência de 90 dias (último − média das estimativas entre 80 e 100 dias atrás) e faixa por idade e sexo pelos percentis do registro FRIEND (Kaminsky 2015, teste em esteira, 20–79 anos): < P10 muito baixo, P10 baixo, P25 regular, P50 bom, P75 excelente, ≥ P95 superior. Fora de 20–79 anos, sem sexo ou com sexo "outro": mostra o valor, sem faixa (não extrapola). Sem estimativa há 60 dias **e com ao menos uma estimativa na janela de 180 dias** → sugestão "Faça 20 min de caminhada rápida ou corrida ao ar livre com o seu relógio para atualizar o VO2max". Sem nenhuma estimativa na janela de 180 dias, o relógio do usuário provavelmente não envia VO2max ao Saúde e a sugestão nunca aparece (onda 2.1 A2). |
| **A4 Recuperação** | HRV (SDNN), FC de repouso e sono: média dos últimos 7 dias vs. 28 dias. Sem dado noturno em ≥ 5 dos últimos 7 dias → sugestão "Use o relógio para dormir; ele mede HRV, FC de repouso e sono, que o app usa na revisão periódica" (conta sono de qualquer fonte, não só do Apple Watch). Quedas de HRV ≥ 10 % ou alta de FC de repouso ≥ 5 bpm são exibidas como alerta amarelo e alimentam §7.8 R6. |
| **A5 Encaixe sem interferência** | Ao sugerir aeróbico para completar a meta: preferir dias sem treino de inferior; se no mesmo dia, sugerir ≥ 6 h de intervalo e modalidade de baixo impacto (bicicleta, caminhada) em vez de corrida; nunca sugerir vigoroso nas 24 h antes de um dia de inferior. Base: a meta-análise mais recente (Schumann 2022) não encontrou prejuízo do treino concorrente na hipertrofia nem na força máxima, só na força explosiva, sobretudo com as sessões no mesmo dia. A anterior (Wilson 2012) apontava interferência maior com corrida e volume alto. As regras acima são cautela prática com custo baixo. |
| **A6 Determinismo** | Regras fixas e testadas; sugestões trazem o motivo e os números. |

### 7.11 Diálogo do app com o usuário (M4, entregue com M2 e M5)

O app conversa com o usuário por **mensagens** curtas, geradas por regras determinísticas, exibidas na abertura (se houver algo novo e importante) e numa seção da Home. Cada mensagem tem título, uma frase de motivo com os números, botão "Por quê?" (referências) e ações. Nada muda sem o usuário ver; ações que alteram o programa pedem confirmação.

| Regra | Mensagem | Ações | Cadência |
|-------|----------|-------|----------|
| **C1 Deload** | Gatilhos de §7.5 (≥ 50 % dos exercícios com `decrease`, ou N semanas desde o último deload, padrão 6) → "Semana mais leve programada" com o motivo. O deload é **aplicado automaticamente** na próxima passagem da rotação, com opção de desfazer. Rearme conforme §7.5. | "Ok" / "Seguir normal" | Quando dispara |
| **C2 Revisão periódica** | Sugestões de §7.8 (R1–R6): mais/menos séries por grupo, trocar exercício ou faixa de reps após estagnação, reduzir dias se a aderência cair, trocar de programa após o mesociclo (padrão 8 semanas, preservando cargas). | "Aplicar" / "Agora não" / "Não sugerir mais isto" | A cada 4 semanas ou gatilho |
| **C3 Saúde** | Sugestões de §7.10 (usar o Watch à noite, caminhada/corrida de 20 min ao ar livre para o VO2máx, completar minutos de aeróbico evitando a véspera de pernas, sono baixo, recuperação em queda, passos). | "Entendi" / "Lembrar amanhã" | Diária, no máximo 1 por tipo a cada 3 dias |
| **C4 Validade da instalação** | Lê a data de expiração do perfil de assinatura embutido no app; 2 dias antes: "O app expira em 2 dias; renove pelo Impactor" + notificação local na véspera. | "Como renovar" | Diária nos últimos 2 dias |
| **C5 Retomada** | ≥ 6 dias sem sessão → "Bom te ver de volta" com o próximo dia e, se ≥ 21 dias, aviso de que as cargas vêm reduzidas (P9). | "Começar" | Ao abrir |
| **C6 Marco pessoal** | Novo melhor 1RM estimado de um exercício (Epley), em tom de progresso, sem linguagem de academia. | "Ver evolução" | Por sessão |
| **C7 Backup** | Último backup há ≥ 14 dias (ou nunca, com ≥ 5 sessões) → lembrete. | "Fazer backup" / "Depois" | Semanal |
| **C8 Longevidade** | Com objetivo Longevidade: lembrete leve de equilíbrio e mobilidade (5–10 min) se não marcados na semana; registra "feito". | "Feito" / "Pular" | Semanal |

Mensagens dispensadas respeitam a cadência (não voltam antes); "Não sugerir mais isto" silencia a regra para aquele item. Decisões ficam registradas localmente (log JSON) para auditoria e para não repetir.

### 7.12 Como fazer: guias de execução (v2.1)

Cada guia descreve em dados um exercício do catálogo: a vista (lateral ou frontal), 2 ou 3 quadros de pose em ângulos por segmento do corpo, a articulação que fica parada, o equipamento, o ritmo, as legendas dos quadros, a descrição acessível, 3 passos e 2 erros comuns. O app desenha e anima a figura a partir desses números. A matemática (interpolação, posição das articulações, mão no implemento, partes que se movem) fica em `TrainerCore/Guide`, pura e testada por tabela; a tela só pinta o resultado. O protótipo de referência é `docs/design/exercise-guides/render-exercise-guides.ps1`, com `exercise-guides.sample.json`.

| Regra | Descrição |
|-------|-----------|
| **E1 Ligação por slug** | Cada guia aponta um `slug` do catálogo do seed, com no máximo uma guia por `slug`. Exercício sem guia (personalizado ou ainda não desenhado) não mostra "Como fazer". Na sessão vale o exercício realizado: se foi trocado (RF-34), aparece a guia do substituto. |
| **E2 Conteúdo fixo** | 2 ou 3 quadros, cada um com legenda de até cerca de 28 caracteres ("Barra toca o peito"); exatamente 3 passos e 2 erros comuns, cada um com até 120 caracteres, em pt-BR e no tom do DESIGN §6; descrição acessível não vazia. Os textos usam palavras próprias: nada copiado de sites, livros ou apps. |
| **E3 Uma figura só** | Todas as guias usam o mesmo manequim e a mesma escala. Comprimentos em fração da estatura H, segundo Drillis e Contini (1966), reproduzidos em Winter, *Biomechanics and Motor Control of Human Movement*: ombro 0,818 H; quadril 0,530 H; joelho 0,285 H; tornozelo 0,039 H; braço 0,186 H; antebraço 0,146 H; mão 0,108 H. |
| **E4 Pose determinística** | A pose é função pura do tempo t dentro do ciclo. Cada ângulo é interpolado pelo menor arco, com `easeInOut`, e no início de cada fase a pose é exatamente a do quadro. Mesma guia e mesmo t → mesmas coordenadas. |
| **E5 Ponto fixo** | A articulação âncora (por exemplo, tornozelo no agachamento, quadril no supino) não se move em nenhum t (tolerância 0,001 H). Exceção declarada: `anchor: "none"` nos saltos. |
| **E6 Mão no implemento** | Se o braço tem alvo ao alcance, a mão chega a ele (tolerância 0,005 H), com o cotovelo do lado indicado; um modo "antebraço travado" mantém o antebraço num ângulo fixo (por exemplo, vertical sob a barra no supino). Fora do alcance, o braço estende na direção do alvo. O cálculo nunca produz NaN. |
| **E7 Ritmo calmo** | Ciclo = pausa no início + ida + pausa no fim + volta; padrão de 0,4 s, 1,5 s, 0,4 s e 1,5 s, com cada fase de movimento entre 0,8 s e 3 s. Guias `motion: "static"` (rotação no plano horizontal, isometrias) não animam e mostram setas. A animação para com Pausar, com Reduzir Movimento e quando a folha fecha. |
| **E8 Falha tratável** | Arquivo de guias ausente ou reprovado na validação (E1–E7, E9) → registro no log e nenhum botão "Como fazer"; a sessão nunca é interrompida. Os testes garantem que o arquivo do bundle passa. |
| **E9 Clareza** (pedido do dono) | Os segmentos cujo ângulo muda entre os quadros ficam em acento forte (contraste ≥ 3:1), e o resto do corpo em acento suave; um campo opcional `moving` força outra escolha. Os membros do lado de lá ficam mais claros que os do lado de cá. Uma seta sólida acompanha o caminho do ponto principal (barra, mãos, puxador ou quadril) no quadro inicial; no final, a posição inicial aparece em fantasma, só das partes que mudaram. O título mostra "Trabalha: …" com os grupos primários do catálogo. |

### 7.13 Modo casa (v2.1)

| Regra | Descrição |
|-------|-----------|
| **H1 Quem é de casa** | Um exercício é "de casa" quando o catálogo do seed o marca `atHome: true`.<br>- **Peso do corpo sem aparelho:** flexão, agachamento, prancha, ponte. Também vale quando um objeto só **apoia** o corpo: cadeira, degrau, toalha no chão. Esses exercícios são `bodyweight` e podem ter carga 0 (P8).<br>- **Objeto que é a carga:** mochila com peso, garrafas, sacolas. Esses exercícios são `household` e pedem carga adicional (≥ 2,5 kg).<br>- **Não é de casa:** peso do corpo que exige aparelho (barra fixa, paralelas, banco 45°, caixa de salto, flexão nórdica com os pés presos) e exercício personalizado. |
| **H2 Equivalente** | Para cada exercício do plano: se ele já é de casa, fica. Senão, o equivalente é o melhor candidato de casa com o mesmo padrão de movimento e ao menos um grupo primário em comum, na ordem do RF-34 (pontuação, afinidade de equipamento, nome, id). Sem candidato: o melhor de casa com ao menos um grupo primário em comum. Em cada um desses dois passos, os candidatos com a mesma medida do original (RF-43) vêm antes dos outros, cada parte na ordem do RF-34: como o alvo vem do original (H4), um "3 × 8–12" não pode virar "3 × 8–12 s" (ex.: pallof press → dead bug, e não prancha lateral; achado da revisão da v2.1, 2026-09-24). Exercícios de pescoço e os que não são de pescoço nunca se equivalem por grupo: o "costas" do pescoço é só convenção de contagem (§7.4). Sem nenhum: o exercício sai da sessão com o aviso "sem opção em casa para X". Na folha Trocar em modo casa valem só candidatos de casa pela regra do RF-34. |
| **H3 Sem repetição** | Dois exercícios do mesmo dia não viram o mesmo exercício de casa: o segundo recebe o próximo candidato da lista. |
| **H4 Alvo e histórico** | O alvo (séries, faixa, RIR, descanso) vem do exercício original. A carga e a nota vêm do histórico do exercício de casa (P1–P12); sem histórico, `calibrate`. Peso do corpo com carga 0 segue P8 (a progressão sobe repetições e, no topo da faixa, sugere carga adicional, por exemplo uma mochila; a ficha mostra "+ 2,5 kg extra", RF-46). |

### 7.7 Determinismo

Motor de prescrição (§7.2, §7.3), políticas de programa (§7.5, §7.8) e saúde (§7.10) são código puro em Swift, testados por casos de tabela, sem aleatoriedade e sem IA. O usuário sempre vê a regra e os números por trás de qualquer número ou sugestão.

## 8. Requisitos não funcionais

| ID | Requisito |
|----|-----------|
| RNF-01 | Todas as funções de M1–M4 funcionam sem rede. |
| RNF-02 | Resposta a toque na sessão ativa < 100 ms; cada toque que grava (bolinha, "Feito", "Marcar como feitos") persiste antes de retornar. |
| RNF-03 | Matar o app ou o relógio ficar sem bateria não perde nenhuma série já concluída. |
| RNF-04 | Backup completo em JSON legível, importável em instalação limpa. |
| RNF-05 | Dados só no aparelho e no HealthKit. Nenhuma telemetria. |
| RNF-06 | Dynamic Type e botões ≥ 44 pt na sessão ativa (mãos suadas, luvas). |
| RNF-07 | Watch: sessão de 90 min com FC ao vivo sem esgotar bateria (uso padrão de `HKWorkoutSession`). |
| RNF-08 | Motor de treino com cobertura de testes de tabela para todas as regras P1–P12 e S1–S7. |

## 9. MVP mínimo utilizável na academia = Milestone M1

iPhone apenas. Programa inicial vindo de um JSON no bundle (sem tela de edição). Tela inicial com o próximo treino prescrito → iniciar → registrar séries com timer de descanso → finalizar → próximo treino já recalculado → histórico simples.

Sem HealthKit, sem Watch, sem edição de programa, sem exportação. Isso já elimina a necessidade de pensar na academia, que é o objetivo central. Critérios de aceitação objetivos em [TASKS.md](TASKS.md).

## 10. Fases

Ver [TASKS.md](TASKS.md): M0 esqueleto → M1 MVP iPhone → **versão 2 = M2 (objetivos, edição, backup, HealthKit) + M4 (deload, frequência, revisão periódica, diálogo) + M5 (saúde aeróbica e recuperação) + identidade visual** → M3 app do Apple Watch (adiado por decisão do usuário em 2026-09-23).

## 11. Decisões já tomadas

1. Só RIR é armazenado; RPE é exibido como conversão.
2. Séries retas em v1; sem pirâmide, sem drop set.
3. Histórico e progressão indexados por exercício do catálogo (`slug`), não por programa.
4. iPhone é a fonte da verdade; Watch sem SwiftData (snapshot Codable em arquivo).
5. Exatamente um `HKWorkout` por sessão; quem roda a `HKWorkoutSession` grava (M2: iPhone via `HKWorkoutBuilder`; M3: Watch).
6. UI em pt-BR com strings fixas no código; sem localização.
7. Sem CloudKit. Backup manual em JSON.
8. Programa inicial padrão: 3 dias, ajustável no JSON semente. Até a M1 era A empurrar / B inferior / C puxar; desde 2026-09-23 o Completo de hipertrofia é **corpo todo** (cada grupo 2×/semana, §7.9).
9. Peso corporal: `loadIncrement` = 2,5 kg (carga adicional), carga 0 permitida só para `bodyweight`. Todo exercício do catálogo tem `loadIncrement` > 0 (validado no seed).
10. Só RIR entra na avaliação; séries com RIR ausente não recebem o bônus de P4.
11. O app do Watch é **opcional** por desenho: tudo em M1–M2 funciona só com o iPhone, e a FC vem do app Exercício nativo do relógio via HealthKit até o companion existir (ver §7.6 e §13).
12. Sem Mac: o projeto Xcode é gerado por XcodeGen no GitHub Actions; o motor é testado localmente no Windows (ARCHITECTURE ADR 008/009).
13. **Sem IA no app gratuito** (2026-09-23). Revisão periódica e saúde são regras determinísticas (§7.8, §7.10). Ideia futura do usuário, fora do escopo atual: uma camada paga opcional com IA para personalização extra. Se for adiante, exige ADR própria e continua sem tocar no motor determinístico (a IA só proporia ajustes que o usuário aceita).
15. **Identidade visual desvinculada da cultura de academia** (pedido do usuário, 2026-09-23): nada de halteres, preto/neon, músculos ou linguagem agressiva. Paleta terrosa (bege, areia, marrom), ícone com símbolo de pétalas ligado aos objetivos, e os **objetivos como elemento central** da interface. Guia em `DESIGN.md`; aplicado numa passada de design logo após a integração do M2.
14. Aeróbico é registrado pelo app Exercício do Watch e apenas lido pelo app; o app não prescreve sessões de cardio, só meta semanal e sugestões de encaixe.
16. **Nome e ícone** (decisão do usuário, 2026-09-23): o app se chama **Magister** (latim para "mestre, quem ensina e guia"; uma palavra só) nos dois targets. Os bundle IDs não mudam. O ícone tem cinco pétalas creme separadas, uma por objetivo, e miolo areia (a pessoa) sobre azul-marinho, com aparências escura e tingida. Significado, geometria e contrastes em `DESIGN.md` §0 e §2.
17. **Como fazer com ilustração própria** (pedido do usuário e pesquisa de 2026-09-24; estilo aprovado na v2 do protótipo): as guias usam só arte gerada pelo app a partir de dados do projeto. Poses e textos são rascunhados pelo agente e revisados pelo dono em lotes; não é IA no app nem imagem gerada por modelo. Os bancos gratuitos foram descartados por motivos diferentes:
    - fotos raspadas de sites comerciais (free-exercise-db, exercises.json);
    - fotos de usuários com licença não confiável (wger);
    - mídia paga ou com redistribuição proibida (ExerciseDB/Gym Visual, MuscleWiki, Darebee);
    - imagens geradas por IA (RepDB);
    - o Everkinetic (CC BY-SA) é legítimo, mas cobre cerca de 57 % do catálogo, mostra um corpo musculoso e exige atribuição e ShareAlike.

    Para exercícios difíceis de desenhar, a reserva é o mesmo manequim parado com setas. Detalhes em `docs/design/exercise-guides/PROPOSAL.md`.
18. **Simplificação da 2.2** (respostas do dono em 2026-09-27, depois de usar a 2.1 no aparelho; pedidos S1–S10 do TASKS; proposta em `docs/design/v22/proposal.json` e telas em `docs/design/v22/mockup.html`; contrato `docs/V22-CONTRACT.md`):
    - **Flor e ícone:** candidato "6 · Brisa" (`docs/design/icon-v22/render-icon-v22.ps1`): as cinco pétalas continuam creme, separadas e em gota, agora com um giro leve e pequenas diferenças entre elas, como uma flor mexida pelo vento. Vale para o ícone (padrão, escuro e tingido) e para a flor dentro do app (DESIGN §2 e §4).
    - **RIR interno e invisível:** o sistema continua lidando com o RIR, mas a pessoa não vê nem escolhe nada (RF-41). O registro por toque grava a meta de hoje, `rir = nil` e `isWarmup = false` (RF-03, RF-04, RF-44). Consequências aceitas: o bônus de 2 incrementos do P4 deixa de acontecer com dados novos (decisão 10; a questão da §12 sobre o "grande salto" fica sem efeito), e a metade "RIR 0 acima de 30 %" do R2 fica muda; continuam o sinal por prescrições e a semana leve programada. Nada é inventado: o app não grava RIR que ninguém mediu.
    - **Combate:** o nome continua "Combate" e o subtítulo passa a ser **"Potência e resistência"** (DESIGN §4). O antigo "Saber se defender" prometia técnica que o app não ensina (§7.9).
    - **Proposta aprovada inteira:** objetivo = plano, com a Hipertrofia em 3 formatos (RF-45); topo da tela Hoje troca de objetivo; tela Hoje enxuta (RF-01); sessão como ficha de consulta com "Feito" por exercício e bolinhas por série (RF-44); ao concluir com exercícios não marcados, oferecer "Marcar como feitos, como previsto" (RF-44 e); tela acesa só com a ficha aberta (RF-44 g); peso do corpo sem carga, mantendo a regra atual de carga extra no topo da faixa (RF-46; P4/H4 sem mudança); a chave Aquecimento sai, trocada por uma dica fixa (RF-44 d); "Treinar em casa" só na tela Hoje (RF-42); tonelagem só no Histórico (RF-12).
    - **Sem mudança no motor nem nos dados:** TrainerCore (P1–P12, S1–S7, §7.5, H1–H4, Review, Coach), SchemaV2, eventos de sessão, sync e backup ficam como estão; não há SchemaV3 nesta versão.

## 12. Questões abertas (não bloqueiam M0–M1)

- Exercícios unilaterais: registrar um lado ou os dois? (Proposta M2: uma série = os dois lados; reps do lado mais fraco.)
- Regra de "grande salto" (P4, +2·inc) pode ser agressiva em máquinas de 5 kg; revisar após 4 semanas de uso real. (Desde a 2.2 as séries novas não têm RIR, então o salto não acontece com dados novos; decisão 18.)
- Peso do corpo no topo da faixa (RF-46): hoje recebe carga extra (P4/H4). Se incomodar, sobretudo em explosivos e no Combate em casa, a alternativa "nunca pôr carga e sugerir uma variação mais difícil" é regra nova do motor, em tarefa própria com SPEC e teste de tabela.
- Precisão de 1 s nas datas dos eventos de sync (ISO 8601 sem fração); só importa para "último que escreve vence" em `setUpdated` (M3).

## 13. Restrição de execução confirmada — 2026-09-22

O usuário dispõe apenas de Windows e requer custo zero, HealthKit e companion nativo no Watch.
Não migrar para PWA nem remover integrações para contornar essa restrição. T0.0 valida primeiro
compilação macOS hospedada, instalação com conta gratuita e renovação de sete dias. A capacidade
listada pela Apple não garante compatibilidade do instalador. O teste é de leitura e instalação;
FC ao vivo, gravação e sincronização continuam nos milestones próprios.

Fatos verificados em 2026-09-22 (fontes em [WINDOWS_SETUP.md](WINDOWS_SETUP.md)):

- HealthKit **está** disponível para a conta Apple gratuita em iOS e watchOS. O risco não é a Apple, é a ferramenta de sideload: AltStore, SideStore e iLoader (upstream) não pedem a capability HealthKit e removem o entitlement na assinatura. Só um fork comunitário recente (Rzbck/iLoader) e, para iPhone apenas, o Impactor têm código que preserva o entitlement. Nada disso foi validado nos aparelhos do usuário.
- Instalar o companion no Watch a partir do Windows depende exclusivamente desse fork, sem aceite upstream e sem renovação automática; o Developer Mode do relógio pode exigir pareamento com Xcode. Consequência de produto: **o app do Watch é opcional** (decisão 11) e M3 só começa depois de V3–V5 aprovados.
- Builds Apple no GitHub Actions são gratuitos e ilimitados em repositório público; em privado, a franquia estimada é de ~200 min macOS/mês.
