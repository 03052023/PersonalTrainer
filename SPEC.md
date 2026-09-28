# SPEC — Personal Trainer Automático (iPhone + Apple Watch)

Versão 0.1 · 2026-09-22 · Uso pessoal (um único usuário). Revisão 2.2 · 2026-09-27: simplificação pedida pelo dono (decisão 18; contrato `docs/V22-CONTRACT.md`). Revisão 2.3 · 2026-09-27: formato Equilibrado, objetivo Fôlego (cardio em minutos), carga opcional e "Como fazer" (decisão 19; contrato do núcleo `docs/V23-CORE-CONTRACT.md`).

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

Backend, contas, sync em nuvem/CloudKit, funções sociais, nutrição, prescrição detalhada de cardio: zonas de FC, ritmo, distância, planos de prova. Desde a 2.3, o objetivo Fôlego prescreve só sessões simples em minutos, com a intensidade pelo teste da fala (§7.14, decisão 14 revista); o resto do aeróbico continua no app Exercício do Watch, lido pelo HealthKit. Também ficam fora: vídeos de exercícios, planos pagos, Android, layout de iPad, publicação na App Store, localização para outros idiomas (UI em pt-BR fixo), **qualquer uso de IA/LLM**.

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
| RF-04 | Cada série nova grava a meta de repetições de hoje (`prescribedTargetReps`; 0 = sessão antiga, vale `repMin`). A carga é, nesta ordem: a escolhida tocando no número da ficha; senão, a da série anterior do exercício nesta sessão; senão, a prescrita; em peso do corpo sem carga, 0 (P8). Mudança da 2.2: as repetições não copiam mais as da série anterior, voltam sempre à meta; a carga continua copiando. Mudança da 2.3 (D3): em **qualquer** exercício sem carga escolhida nem prescrita, a série grava 0, que quer dizer "sem carga externa" (P8, RF-46). | M1 · v2.2 · v2.3 |
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
| RF-35 | Hipertrofia com três formatos de divisão: **completo** (todo o corpo equilibrado, padrão ABC), **foco inferior** (glúteos e pernas com mais volume, superior em manutenção) e **foco superior** (peito, ombros, braços e costas com mais volume, inferior em manutenção). Volume do foco no topo da faixa de §7.9; manutenção ≈ 1/3 do volume (Bickel 2011). Na interface (2.2, RF-45) eles são os formatos do objetivo Hipertrofia.<br>Desde a 2.3 (D1, decisão 19), o completo é o **Equilibrado**: 4 dias alternando Superior e Inferior (A Superior, B Inferior, C Superior com outros exercícios, D Inferior com outros exercícios). São 5 exercícios por dia, e cada grupo é trabalhado 2 vezes por semana (§7.9). Os formatos passam a ser **Equilibrado**, **Mais pernas e glúteos** e **Mais tronco e braços**.<br>O antigo **Corpo todo** (3 dias que misturam superior e inferior) fica escondido, como o Empurrar/Inferior/Puxar: só aparece enquanto está ativo.<br>Os dois formatos de foco têm 4 dias porque cada grupo em foco precisa de 2 dias por semana, e os outros 2 dias mantêm o resto do corpo com menos séries. | M2 · v2.2 · v2.3 |
| RF-37 | Diálogo do app (§7.11 C1–C8): feed de mensagens na Home, destaque na abertura, ações aceitar/recusar, registro de decisões. | M4 (nesta versão) |
| RF-38 | Deload automático com opção de desfazer (§7.5, §7.11 C1): sessões marcadas `isDeload`, prescrição reduzida, ignoradas pela progressão. | M4 (nesta versão) |
| RF-39 | Seleção do próximo dia por frequência semanal e recuperação de 48 h (S5–S7), ativável em Ajustes > "Mais opções" > "Escolher o dia pela semana" (padrão: ligado quando o programa tem ≥ 4 dias). | M4 (nesta versão) |
| RF-40 | **Como fazer** (pedido do usuário, 2026-09-24; estilo aprovado na v2 do protótipo, `docs/design/exercise-guides/compare-v2.png`): botão "Como fazer" (símbolo `play.circle`) em cada exercício que tem guia, na sessão (ao lado do nome), na Home (linha da prescrição) e no catálogo. Abre uma folha com:<br>(a) uma ilustração **própria, minimalista e sem realismo**: manequim liso, sem músculos, rosto ou roupa marcada, com o equipamento só sugerido. Ela é desenhada pelo app a partir de números de pose (§7.12) e anima em loop lento entre a posição inicial e a final, com botão Pausar. Para ficar clara (§7.12 E9), só as partes do corpo que se movem ficam em acento forte; uma seta mostra o caminho; cada posição tem uma legenda curta; o título vem com "Trabalha: …";<br>(b) **3 passos curtos e 2 erros comuns** em pt-BR, com palavras próprias.<br>Todos os exercícios usam a mesma figura, a mesma escala, as cores do DESIGN §3 e §12 e o mesmo formato. **Origem e licença:** nenhuma foto, vídeo, GIF ou desenho de terceiros e nenhuma imagem gerada por modelo de imagem. A arte é obra do projeto, gerada em tempo de execução a partir de `Resources/Seed/exercise-guides.v1.json`, então não há atribuição a exibir. **Offline:** tudo vem no app (cerca de 150 KB de dados, nenhuma imagem). **Acessibilidade:** com Reduzir Movimento, as posições ficam paradas lado a lado, com a inicial em fantasma; para o VoiceOver, a ilustração é um único elemento com descrição própria, seguido dos passos e dos erros; os textos seguem o Dynamic Type; figura e implemento têm contraste ≥ 3:1 nos modos claro e escuro. Exercício sem guia (personalizado) não mostra o botão.<br>**Desde a 2.3 (D5):** há guias para os 62 exercícios que o app usa: os 52 dos programas do seed e os 10 aeróbicos. Elas são escritas em lotes que o dono revisa. O motor e a ferramenta de autoria vêm primeiro (`docs/V23-CORE-CONTRACT.md` §2.5–§2.7). A folha entra na onda de telas, dentro de "Informações do exercício" (RF-47). | v2.1 · v2.3 |
| RF-42 | **Modo casa** (pedido do usuário, 2026-09-24): chave "Em casa" no cartão da tela Hoje (desde a 2.2, só ali; saiu de Ajustes).<br>Ligada, cada exercício da sessão planejada é trocado pelo equivalente que dá para fazer em casa sem equipamento específico: peso do corpo ou objetos comuns, como mochila com peso, garrafas de água, cadeira firme, degrau ou toalha (novo equipamento `household`).<br>A escolha é determinística (§7.13 H1–H4): o mesmo padrão de movimento e um grupo primário em comum, ordenados como no RF-34. Sem equivalente, vale o mesmo grupo primário; se nem isso existir, o exercício sai da sessão, com aviso.<br>O programa não muda: desligar a chave volta os exercícios da academia. Cada exercício tem o próprio histórico (P3), então quem nunca fez a versão de casa começa em calibração. O alvo (séries, faixa, RIR, descanso) vem do exercício original. O cartão do dia mostra "Em casa". Na sessão, o botão Trocar oferece só alternativas de casa. | v2.1 |
| RF-43 | **Medida do exercício** (achado de 2026-09-24): cada exercício do catálogo tem uma medida: `reps` (padrão), `seconds` (isometrias, pranchas), `steps` (carregadas) ou, desde a 2.3, `minutes` (aeróbicos, §7.14; D4). Prescrição, registro da série, histórico e resumos mostram a unidade certa ("3 × 20–40 s", "30 passos", "30 min"). A progressão (P4–P6) usa o mesmo número com a mesma lógica. A tonelagem (RF-12) só soma exercícios medidos em repetições: carga × segundos ou carga × passos não é tonelagem. A medida e a marca "dá para fazer em casa" vêm do catálogo do seed pelo `slug`, sem mudar o esquema de dados; exercício personalizado usa `reps` e não entra no modo casa. | v2.1 |
| RF-41 | **RIR interno, invisível ao usuário** (decisão do dono, 2026-09-27, decisão 18; substitui o "RIR explicado" da 2.1). O RIR continua no domínio: `targetRIR` no programa e no snapshot da sessão, `SetResult.rir` nas séries antigas, P2/P4/§7.5 e R2 como estão. Mas a pessoa não vê nem escolhe nada sobre ele: saem o seletor da série, "O que é RIR?", o cartão da primeira sessão, o RIR alvo nas prescrições ("RIR 2", "pare com 2 sobrando", inclusive na leitura do VoiceOver), o RIR das séries no Histórico e o campo "RIR alvo" na edição do programa. Séries novas gravam `rir = nil` (decisão 10: sem o bônus de P4). Única marca indireta: na primeira vez de um exercício com carga (P2), a dica concreta "Escolha uma carga que daria para levantar umas N vezes. Hoje faça M.", com N = meta + RIR alvo do snapshot, sem citar RIR. A explicação `topic.rir` continua só na lista de Referências científicas. | v2.1 · v2.2 |
| RF-44 | **Sessão como ficha de consulta** (pedidos S5, S7, S8 e S9 do dono; decisão 18). A sessão ativa é uma lista rolável com todos os exercícios, na ordem e na paleta do DESIGN §3 (fundo `background`, cartões `surface`, tint `accent`).<br>(a) **Cartão:** número, nome (toque abre RF-47), selo da nota (só com novidade; toque abre o "Por quê?"), a meta de hoje em letra grande ("3 repetições · 62,5 kg", "30 passos · 22,5 kg", "15 segundos"; nunca a faixa), uma bolinha por série, "✓ Feito" e, em letra pequena, "3 séries · descanso 4 min". Nada de RIR. Estados: pendente, atual (o primeiro pendente, com borda `accent`), feito ("✓ 5, 5, 4 · 60 kg") e pulado.<br>(b) **Toques** (tudo pelo `SessionCoordinating`, R4): bolinha vazia = 1 `setLogged` com a meta de hoje e a carga de RF-04, `rir = nil`, `isWarmup = false`, e inicia o descanso do exercício; bolinha cheia = "Corrigir série" (carga, repetições, apagar; `setUpdated` mantém o `rir` já gravado, ou `setDeleted`); "Feito" = um `setLogged` para cada série que falta até `prescribedSets`, sem iniciar descanso; tocar na carga = teclado numérico para a carga de hoje, que vale para as próximas séries do exercício (P10).<br>(c) **Carga opcional** (2.3, D3; substitui a "primeira vez com carga" da 2.2). Bolinhas e "Feito" funcionam sempre, com ou sem carga.<br>Na primeira vez de um exercício com equipamento (P2 sem carga), o cartão mostra "sem carga" no lugar do número e, se couber, a dica opcional de RF-41. Tocar abre o teclado para pôr uma carga. Sem carga escolhida, a série grava 0 ("sem carga externa", P8).<br>A mudança de tela vem na onda de telas da 2.3. Até lá, a ficha da 2.2 ainda pede carga maior que 0.<br>(d) **Aquecimento:** a chave "Aquecimento" sai. No topo da ficha fica a linha fixa "Aqueça com 1 ou 2 séries leves antes dos exercícios com carga. Não precisa marcar." Aquecimentos antigos continuam no Histórico e fora da progressão (P1).<br>(e) **Concluir:** com todo exercício não pulado com as séries prescritas, "Concluir" vai direto ao resumo. Faltando algum, pergunta uma vez "Faltam N exercícios", com os nomes: "Marcar como feitos, como previsto" (o mesmo que "Feito" em cada pendente que tem carga; os de primeira vez sem carga ficam de fora, e a mensagem diz quais), "Encerrar só com o que marquei" (conclui; P7 avalia o que foi feito) e "Voltar ao treino". Sem nenhuma série marcada, as opções são "Marcar como feitos, como previsto", "Sair sem registrar" (abandona) e "Voltar ao treino". "Marcar como feitos, como previsto" só aparece quando algum pendente pode ser marcado; se alguma gravação falhar, a sessão não é concluída e a ficha mostra o erro.<br>(f) **Descanso** preso no topo, sem empurrar a lista, com "+30 s" e "Pular".<br>(g) **Tela acesa** só enquanto a ficha está aberta e o app em primeiro plano (`isIdleTimerDisabled`); o resumo e as outras telas seguem o bloqueio do iPhone.<br>(h) **Resumo** "Sessão concluída" com a flor do objetivo, duração, "Exercícios X de Y", séries, FC quando houver e "A próxima sessão já está pronta: Dia B". | v2.2 |
| RF-45 | **Objetivo = plano** (pedidos S2 e S3). Na interface há um conceito só, o objetivo; cada objetivo tem o seu plano, que é um programa com aquele `goal`. A Hipertrofia tem 3 formatos (RF-35). Regra de escolha, por objetivo e formato: o programa ativo, se tiver aquele objetivo; senão, o do seed; senão, o primeiro com aquele `effectiveGoal`. Um programa ativo de Hipertrofia que não é um dos 3 formatos aparece como formato extra só enquanto estiver ativo. Pode ser uma cópia, o antigo Empurrar/Inferior/Puxar ou, desde a 2.3, o Corpo todo, que aparece com o título "Corpo todo". Os outros extras usam o próprio nome.<br>O plano do Fôlego é o programa do seed "Fôlego" (2.3). O antigo "Resistência muscular" das instalações existentes só vale enquanto estiver ativo.<br>A folha "Seu objetivo" abre do topo da tela Hoje ("Trocar"), da aba **Plano** ("Trocar objetivo") e no primeiro uso ("Qual é o seu objetivo?", um passo só, com o aviso de técnica do Combate, §7.9). Ela mostra a flor e os 5 objetivos na ordem das pétalas (nome, subtítulo, dias, "Por quê?"); no tocado, o formato (só na Hipertrofia) e a prévia do Dia A. O botão diz o que vai acontecer ("Trocar para Hipertrofia"), com a frase "Suas cargas ficam guardadas: cada exercício tem o próprio histórico. A próxima sessão aparece na tela Hoje." Trocar chama `ProgramRepositoring.activate` (S2: o próximo dia segue a última sessão com séries, e um plano que não tem o dia dela recomeça no Dia A, então voltar ao plano da última sessão continua a rotação; P3 é por exercício). O C2 "Experimentar um novo programa" (§7.11) segue a mesma regra: na Hipertrofia, ativa o próximo dos 3 formatos, nunca um programa escondido; nos outros objetivos, abre esta folha. Com sessão em andamento, a troca fica bloqueada.<br>A aba Programa vira **Plano**: o objetivo com "Trocar objetivo", a semana inteira para consultar (dias com os exercícios, o próximo marcado) e, por último, "Ajustar exercícios" (RF-16, RF-33, RF-36) e o catálogo. Saem da interface a lista de programas, Renomear, Duplicar, Apagar, o seletor de objetivo dentro do programa e o diálogo "Aplicar padrões?". Nada é apagado do banco nem do backup. | v2.2 |
| RF-46 | **Peso do corpo sem carga** (pedido S6). Exercício com `equipment = bodyweight` e carga prescrita 0 ou vazia não mostra carga nenhuma (nem "0 kg", nem "—", nem stepper) na tela Hoje, na ficha, na folha de informações e no Histórico; a série grava 0 (P8), sem pedir confirmação. Se a progressão prescrever carga adicional (P4/H4 no topo da faixa), aparece "+ 2,5 kg extra", que a pessoa pode mudar tocando no número. `household` (mochila, garrafas) continua mostrando a carga. O motor não muda: P2 segue devolvendo carga vazia e a tela resolve.<br>**Carga opcional em qualquer exercício** (2.3, D3, pedido do dono: "a carga é só se o cara usar carga"):<br>- Nenhum exercício exige carga para marcar série ou exercício como feito. Sem carga informada, a série grava 0.<br>- Num exercício com equipamento, 0 quer dizer "sem carga externa". A tela mostra "sem carga", que a pessoa toca para pôr uma, nunca "0 kg".<br>- A próxima prescrição continua em 0 e progride por repetições, segundos ou minutos até o topo da faixa, e fica lá (P8 D3).<br>- Quando a pessoa registra uma carga, a progressão parte dela (P3, P10).<br>- O peso do corpo mantém a regra da 2.2: carga extra no topo da faixa. Os aeróbicos nunca ganham carga sozinhos (§7.14). | v2.2 · v2.3 |
| RF-47 | **Informações do exercício** (pedido S9). Folha só de leitura, aberta ao tocar no exercício na tela Hoje e na ficha: "Hoje" em frase ("3 séries de 3 repetições com 62,5 kg. Descanso de 4 min entre as séries."); "Por que esta carga", com os números da última sessão e o "Por quê?" com as referências (RF-32); "Da última vez" (data e séries, lido pelo `SessionPlanning`, sem `@Query`); notas da máquina; e, só na ficha, "Máquina ocupada? Trocar por outro parecido" (antes da 1ª série, RF-34) e "Pular este exercício" (RF-10). Nada de RIR. "Como fazer" (RF-40) entra aqui quando existir. | v2.2 |
| RF-48 | **Fôlego** (2.3, D2, pedido do dono: "deve ser cardiovascular, aumentar o fôlego"). O objetivo `endurance` passa a se chamar **Fôlego**, com o subtítulo "Mais fôlego e disposição" e o símbolo `wind`; o raw value não muda.<br>O plano do seed tem 3 sessões simples por semana, medidas em minutos:<br>- **contínuo moderado**: caminhada rápida, 20–45 min;<br>- **intervalos**: 4 tiros de 2–4 min de corrida forte, com 3 min de recuperação andando;<br>- **longo e leve**: bicicleta, 30–60 min.<br>Cada sessão tem 1 ou 2 complementos leves de força. O catálogo ganha 10 aeróbicos (caminhada rápida, corrida leve, bicicleta ergométrica, remo, elíptico, subir escadas, pular corda, intervalos de corrida e de bicicleta, circuito), que se substituem entre si (RF-34). Os que dispensam aparelho valem em casa (H1).<br>A intensidade é dada pelo teste da fala, nunca pela FC (§7.6). As regras ficam em §7.14 (F1–F5). | v2.3 |
| RF-36 | Programas com qualquer número de dias (A, B, C, D, E… de 1 a 7): adicionar, remover, renomear e reordenar dias na edição de programa; a rotação (S1–S2) já funciona com N dias. Programas do seed podem ter 4 ou 5 dias quando o objetivo pede (ex.: foco inferior/superior, combate com dia de condicionamento), sempre com frequência ≥ 2×/semana por grupo quando possível (Schoenfeld 2016). | M2 |
| RF-32 | Botão "Por quê?" em notas de prescrição, metas e sugestões, mostrando a regra e as referências científicas completas do catálogo `references.v1.json` (§7.9). | M2 (catálogo e notas), cresce a cada milestone |

## 7. Regras de domínio

### 7.1 Conceitos

- **Exercício (catálogo)**: movimento + equipamento. Tem `slug` estável (ex.: `leg-press-45`), grupos musculares primário/secundários, tipo de carga (kg, placas, nível), **incremento mínimo** (`loadIncrement`: 2,5 kg barra/halter; 5 kg máquina de placas; 1 nível), padrão de movimento (RF-34; desde a 2.3, `cardio` = aeróbico, §7.14) e medida (RF-43).
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
| **P2 Sem histórico** | Se `startingLoad` definido → carga = `startingLoad` (0 = sem carga, fica 0; D3), meta = `repMin`, nota `calibrate`. Senão → carga vazia; RIR alvo = T + 1. Na interface: desde a 2.3, marcar sem carga grava 0 em qualquer exercício (RF-44 c, RF-46); a pessoa só digita uma carga se usar carga. |
| **P3 Referência** | Avalia-se a **última sessão concluída ou abandonada** em que o exercício teve ≥ 1 série de trabalho e que **não** foi deload (§7.5). Carga de referência **L** = moda das cargas das séries de trabalho dessa sessão (empate → maior). Se L não é múltiplo de inc (override P10), a base para P4–P6 é arredondar↓(L, inc); a comparação "mesma carga" de P6 usa L bruto. O motor ordena o histórico por data (desempate por id da sessão) e aceita entradas em qualquer ordem. |
| **P4 Sucesso → subir** | Se nº de séries de trabalho ≥ S **e** todas com reps ≥ `repMax` → nova carga = L + inc, meta = `repMin`, nota `increase`. Se além disso min(RIR) ≥ T + 2 → L + 2·inc. **Sem carga (L = 0, D3):** P4 só vale no peso do corpo que não é aeróbico (a carga extra do RF-46). Nos outros casos, vale P5, e a meta fica no topo (`repMax`) até a pessoa pôr carga. |
| **P5 Manter → mais reps** | Se todas as séries com reps ≥ `repMin` mas P4 não vale → carga = L, meta = min(`repMax`, menor reps da última sessão + 1), nota `hold`. |
| **P6 Falha** | Se alguma série de trabalho com reps < `repMin`: primeira ocorrência → carga = L, meta = `repMin`, nota `retry`. Se a sessão anterior a essa (mesmo exercício) também foi falha **na mesma carga L** → nova carga = **min**(arredondar↓(L × 0,9, inc), L − inc), respeitando P8, nota `decrease`. Ou seja: corte de 10 % arredondado para baixo e **pelo menos um incremento** de queda (ex.: L = 60, inc = 2,5 → 52,5; L = 10 → 7,5; L = 5 → 2,5 pelo piso). Com L = 0 não há o que reduzir: a segunda falha também é `retry`, com carga 0 (D3). |
| **P7 Séries incompletas** | Se séries de trabalho < S, não há sucesso (P4). Avalia-se P5/P6 sobre as realizadas. Se 0 séries de trabalho, a sessão é ignorada e usa-se a anterior. |
| **P8 Arredondamento** | Toda carga prescrita é múltiplo de inc. Mínimo = inc; para `equipment = bodyweight` o mínimo é 0 (peso corporal puro) e inc vale para a carga adicional (colete, cinto). Todo exercício do catálogo tem inc > 0. **D3 (2.3):** 0 é "sem carga externa" em qualquer equipamento. Com L = 0, o mínimo também é 0 e toda prescrição fica em 0 (P4 conforme acima; P5, P6, P9 e a semana leve de §7.5 também dão 0) até a pessoa registrar uma carga (P10). |
| **P9 Retorno após pausa** | Se a última sessão em que o exercício teve ≥ 1 série de trabalho (**incluindo** sessões de deload) tem > 21 dias em relação a `now` → carga = arredondar↓(L × 0,9, inc) respeitando P8, meta = `repMin`, nota `returning`. Prevalece sobre P4–P6. L continua vindo da última sessão não-deload (P3). |
| **P10 Override** | O usuário pode alterar carga/reps na hora. Vale o registro real. Nada é corrigido retroativamente. |
| **P11 Determinismo** | Mesma entrada → mesma saída. `now` é parâmetro explícito. Sem aleatoriedade. |
| **P12 FC** | Nenhuma métrica de frequência cardíaca é entrada do motor. Garantido por tipo: a struct de entrada não tem campo de FC. |

Em qualquer medida (repetições, segundos, passos ou minutos; RF-43), P4–P6 usam o número da série com a mesma lógica: nos aeróbicos, P5 soma 1 minuto por sessão até o topo da faixa (§7.14 F3).

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
- Não há grupo "coração": os aeróbicos (padrão `cardio`, §7.14) usam as pernas como grupo primário (`quads` primeiro, e mais `glutes`, `back` ou `calves` conforme o exercício) e contam para elas. É uma convenção, como a do pescoço, que permite a troca entre aeróbicos (RF-34) e o equivalente de casa (H2).
- v1 (M2) só **exibe** realizado/meta. v2 (M4) usa isso na seleção (S5–S7).

### 7.5 Deload (M4)

Gatilhos (qualquer um; se (a) e (b) valem juntos, vale (a)):
- **(a) Muitas reduções:** ≥ 50 % das prescrições atuais do programa (uma por exercício, sem contar `calibrate`) têm nota `decrease`. `retry` e `returning` não contam. Fronteira exata: 2 × reduções ≥ total.
- **(b) Programado:** passaram N semanas (padrão 6, configurável; N ≤ 0 desliga) desde o início do último deload ou, se nunca houve deload, desde a primeira sessão. Conta tempo decorrido (N × 7 dias), pausas incluídas.
- **(c) Manual.**

**Rearme (decisão de 2026-09-23):** depois de um deload, (a) só considera reduções vindas de sessões **posteriores ao fim do último deload**. Sem isso, as mesmas notas `decrease` de antes do deload disparariam outro deload logo em seguida, porque as sessões de deload não mudam a prescrição normal (P3). Quem aplica essa filtragem é o planejador, antes de chamar a política.

Conteúdo: durante 1 semana (uma passagem completa da rotação), cada exercício recebe séries = ⌈S × 0,6⌉ (mínimo 1), carga = arredondar↓(C × 0,85, inc) com o mínimo de P8 (0 quando C = 0, D3), em que C é a carga da prescrição normal daquele dia, RIR alvo = 4, nota `deload`. Nos aeróbicos de 1 série, a semana leve ainda não reduz os minutos (pendência da onda de telas da 2.3). Usar C em vez de L dá o mesmo resultado em `hold`/`retry`, uma carga um pouco menor em `decrease`/`returning` e até 0,85 × inc a mais em `increase`, uma diferença irrelevante numa semana leve. Sessões de deload **não** contam como falha nem sucesso para P4–P6; após o deload a prescrição volta ao estado anterior.

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
| **R8 Aeróbicos** (2.3) | Os exercícios aeróbicos (padrão `cardio`, §7.14) não entram em R1 (1RM de minutos não é força), em R3 (séries por grupo) nem nas sugestões de R5 por exercício (faixa vizinha e troca). Continuam contando em R2 (notas) e em R4 (aderência). O motivo da troca de plano (R5) fala em "este plano": "Você treina com este plano há N semanas; depois de M semanas, mudar de plano renova o estímulo, e as cargas de cada exercício são mantidas." |

Base: autorregulação por RIR/RPE (Zourdos 2016; Helms 2016); dose-resposta de volume (Schoenfeld 2017). Frequência: com o volume semanal igualado, treinar um grupo 1× ou 2×/semana dá resultados parecidos (Schoenfeld 2019); 2×/semana é um jeito prático de distribuir o volume sem sessões longas (Schoenfeld 2016; Grgic 2018). HRV: evidência limitada e inconsistente como guia de treino, majoritariamente em endurance (Bellenger 2016), por isso só modula (R6).

### 7.9 Objetivo do programa (M2)

Cada programa tem um `goal`: `hypertrophy` (padrão), `strength`, `endurance` (na tela, **Fôlego** desde a 2.3; RF-48), `longevity` ou `combat`. **Na interface, objetivo = plano** (RF-45, desde a 2.2): a pessoa escolhe o objetivo, e o plano é o programa daquele objetivo; a Hipertrofia tem 3 formatos (RF-35). O `goal` de um programa não se troca mais pela tela. Todo programa gerado por padrão tem **5 exercícios por dia** (decisão do usuário, 2026-09-23); o usuário pode adicionar ou remover na edição. A exceção é o Fôlego: 1 aeróbico e 1 ou 2 complementos por dia (§7.14). O objetivo define os padrões usados pelo seed, pela edição de programa e pela revisão (§7.8):

| Objetivo | Faixa de reps (compostos / isolados) | RIR alvo | Volume alvo por grupo/semana (séries de trabalho) | Descanso (compostos / isolados) | Séries por exercício |
|----------|---------------|----------|---------------------------------------------------|----------|----------|
| Hipertrofia | 6–12 / 8–15 | 2 | 10–20 | 150 / 90 s | 3 (4 nos compostos principais do Equilibrado e do Corpo todo) |
| Força | 3–6 / 6–10 | 2 | 6–12 | 240 / 150 s | 4 |
| Fôlego: complementos de força (os aeróbicos seguem §7.14) | 12–20 / 15–20 | 3 | 4–12 | 60 / 60 s | 2 |
| Longevidade | 8–12 / 10–15 | 3 | 6–12 | 120 / 90 s | 2 |
| Combate | 3–6 / 6–10 | 2 | 6–12 | 180 / 90 s | 3 |

Os valores são os de `GoalDefaults` (TrainerCore). Compostos são os padrões de movimento empurrar, puxar, agachar, avançar, dobradiça de quadril, elevação de quadril, carregar e explosivo; os demais são isolados. Nos isolados de Força e Combate, 3–6 repetições seriam arriscadas para articulações pequenas (por exemplo, elevação lateral), por isso usam 6–10. Carregadas e pescoço mantêm faixa e descanso próprios ao trocar de objetivo, e só o RIR muda.

**Programa completo de hipertrofia = Equilibrado** (2.3, D1, decisão 19; substitui o Corpo todo como padrão). São 4 dias, alternando Superior e Inferior, com 5 exercícios por dia:
- Dia A — Superior: peito, costas, ombros, bíceps e tríceps;
- Dia B — Inferior: quadríceps, posteriores, glúteos, panturrilhas e abdômen;
- Dia C e Dia D: os mesmos grupos, com outros exercícios.

Cada um dos 10 grupos é o grupo principal de 2 exercícios por semana, então é treinado 2×/semana (Schoenfeld 2016). Os compostos principais têm 4 séries e os outros 3, com descansos de 150/90 s. O volume semanal fica perto do mínimo de 10 séries por grupo sem sessões longas; onde ficar abaixo, a revisão (R3) sugere mais séries. Com 4 dias, a escolha do dia pela semana (RF-39) liga no automático.

O **Corpo todo** (decisão do usuário de 2026-09-23: 3 dias misturando superior e inferior, com 4 séries nos compostos) continua no seed, escondido. Os formatos foco inferior e foco superior (RF-35) seguem a lógica de 2×/semana no grupo em foco.

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

Só leitura do HealthKit; o aeróbico é feito com o app Exercício do Apple Watch (ou qualquer app que grave no Saúde). Nada aqui altera a prescrição de musculação (P12). Desde a 2.3, as sessões do Fôlego (§7.14) também são aeróbico. Até a tarefa de HealthKit do Fôlego (onda de telas), porém, elas vão para o Saúde como treino de força (RF-13) e não entram nos minutos da A1; quem grava a caminhada ou a corrida no relógio vê esses minutos contados.

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

Desde a 2.3:
- O formato do arquivo, o vocabulário de cenas e acessórios, o cálculo normativo e a ferramenta de autoria estão congelados em `docs/V23-CORE-CONTRACT.md` §2.5–§2.7.
- O arquivo do bundle é gerado pela junção dos lotes (`batch-N.json`), que o dono revisa pelas folhas.

| Regra | Descrição |
|-------|-----------|
| **E1 Ligação por slug** | Cada guia aponta um `slug` do catálogo do seed, com no máximo uma guia por `slug`. Exercício sem guia (personalizado ou ainda não desenhado) não mostra "Como fazer". Na sessão vale o exercício realizado: se foi trocado (RF-34), aparece a guia do substituto. |
| **E2 Conteúdo fixo** | 2 ou 3 quadros no movimento em loop; em `motion: "static"`, de 1 a 3 (1 só numa isometria). Os rótulos são "Início", "Meio", "Fim" ou, no quadro único, "Posição". Cada quadro tem legenda de 1 a 28 caracteres ("Barra toca o peito").<br>Exatamente 3 passos e 2 erros comuns ("o erro: o que fazer"), cada um com até 120 caracteres, em pt-BR e no tom do DESIGN §6. A descrição acessível tem de 1 a 240 caracteres.<br>O "Trabalha: …" vem dos grupos primários do catálogo. O campo `works` o substitui e é obrigatório nos aeróbicos ("coração e pulmões, com as pernas") e no pescoço, onde o grupo primário é convenção (§7.4).<br>Os textos usam palavras próprias: nada copiado de sites, livros ou apps. |
| **E3 Uma figura só** | Todas as guias usam o mesmo manequim e a mesma escala. Comprimentos em fração da estatura H, segundo Drillis e Contini (1966), reproduzidos em Winter, *Biomechanics and Motor Control of Human Movement*: ombro 0,818 H; quadril 0,530 H; joelho 0,285 H; tornozelo 0,039 H; braço 0,186 H; antebraço 0,146 H; mão 0,108 H. |
| **E4 Pose determinística** | A pose é função pura do tempo t dentro do ciclo. Cada ângulo é interpolado pelo menor arco, com `easeInOut`, e no início de cada fase a pose é exatamente a do quadro. Mesma guia e mesmo t → mesmas coordenadas. |
| **E5 Ponto fixo** | A articulação âncora (por exemplo, tornozelo no agachamento, quadril no supino) não se move em nenhum t (tolerância 0,001 H). Desde a 2.3, a âncora pode ser qualquer ponto do esqueleto: a mão na barra fixa, o joelho do lado de lá em quatro apoios, a ponta do pé na flexão. Âncora num ponto do braço exige braços por ângulos. Exceção declarada: `anchor: "none"` nos saltos, com a posição do quadril dada em cada quadro. |
| **E6 Mão no implemento** | Se o braço tem alvo ao alcance, a mão chega a ele (tolerância 0,005 H), com o cotovelo do lado indicado; um modo "antebraço travado" mantém o antebraço num ângulo fixo (por exemplo, vertical sob a barra no supino), e nele o braço nunca estica além do próprio comprimento (0,005 H). Fora do alcance, o braço estende na direção do alvo. O cálculo nunca produz NaN. |
| **E7 Ritmo calmo** | Ciclo = pausa no início + ida + pausa no fim + volta; padrão de 0,4 s, 1,5 s, 0,4 s e 1,5 s, com cada fase de movimento entre 0,8 s e 3 s e cada pausa entre 0,2 s e 1 s. Guias `motion: "static"` (rotação no plano horizontal, isometrias, pedalada que não lê bem em 2D) não animam, não desenham o fantasma e mostram setas. A animação para com Pausar, com Reduzir Movimento e quando a folha fecha. |
| **E8 Falha tratável** | Arquivo de guias ausente ou reprovado na validação (E1–E7, E9, E10) → registro no log e nenhum botão "Como fazer"; a sessão nunca é interrompida. Os testes garantem que o arquivo do bundle passa. |
| **E9 Clareza** (pedido do dono) | Os segmentos cujo ângulo muda entre os quadros ficam em acento forte (contraste ≥ 3:1), e o resto do corpo em acento suave; um campo opcional `moving` força outra escolha. Os membros do lado de lá ficam mais claros que os do lado de cá. Uma seta sólida acompanha o caminho do ponto principal (barra, mãos, puxador ou quadril) no quadro inicial; no final, a posição inicial aparece em fantasma, só das partes que mudaram. O título mostra "Trabalha: …" com os grupos primários do catálogo (ou `works`, E2). Num `static` de 1 quadro, `moving` é obrigatório. |
| **E10 Articulações possíveis** (2.3) | Na vista lateral, em todo instante e nos dois lados, cada articulação da perna, do quadril e do pescoço fica numa faixa que o corpo alcança. O ângulo relativo é normalizado para (−180°, 180°]:<br>- joelho (`shin − thigh`): de −165° a 5°;<br>- tornozelo (`foot − shin`): de 0° a 140°;<br>- pescoço (`neck − trunk`): de −60° a 60°;<br>- quadril (`thigh − trunk`): de 150° a 180° ou de −180° a −25°.<br>O cotovelo fica de fora: o braço sai do plano do desenho com frequência (a barra nas costas do agachamento), e o ângulo projetado engana. Ele é conferido na folha.<br>É uma trava contra pose quebrada, não uma medida clínica. Se uma pose real ficar de fora, a faixa muda aqui, com o motivo. As 4 guias do protótipo passam (conferido em 2026-09-27). |

### 7.13 Modo casa (v2.1)

| Regra | Descrição |
|-------|-----------|
| **H1 Quem é de casa** | Um exercício é "de casa" quando o catálogo do seed o marca `atHome: true`.<br>- **Peso do corpo sem aparelho:** flexão, agachamento, prancha, ponte. Também vale quando um objeto só **apoia** o corpo: cadeira, degrau, toalha no chão. Esses exercícios são `bodyweight` e podem ter carga 0 (P8).<br>- **Objeto que é a carga:** mochila com peso, garrafas, sacolas. Esses exercícios são `household` e pedem carga adicional (≥ 2,5 kg).<br>- **Não é de casa:** peso do corpo que exige aparelho (barra fixa, paralelas, banco 45°, caixa de salto, flexão nórdica com os pés presos) e exercício personalizado.<br>- **Aeróbicos (2.3):** são de casa os que se fazem em casa ou na rua sem aparelho: caminhada rápida, corrida leve, subir escadas, intervalos de corrida e circuito com peso do corpo. Bicicleta, remo, elíptico, intervalos na bicicleta e pular corda, que precisa da corda, não são. |
| **H2 Equivalente** | Para cada exercício do plano: se ele já é de casa, fica. Senão, o equivalente é o melhor candidato de casa com o mesmo padrão de movimento e ao menos um grupo primário em comum, na ordem do RF-34 (pontuação, afinidade de equipamento, nome, id). Sem candidato: o melhor de casa com ao menos um grupo primário em comum. Em cada um desses dois passos, os candidatos com a mesma medida do original (RF-43) vêm antes dos outros, cada parte na ordem do RF-34: como o alvo vem do original (H4), um "3 × 8–12" não pode virar "3 × 8–12 s" (ex.: pallof press → dead bug, e não prancha lateral; achado da revisão da v2.1, 2026-09-24). Exercícios de pescoço e os que não são de pescoço nunca se equivalem por grupo: o "costas" do pescoço é só convenção de contagem (§7.4). Pelo mesmo motivo, desde a 2.3, aeróbicos e não aeróbicos nunca se equivalem por grupo (as pernas do aeróbico também são convenção, §7.4). Sem nenhum: o exercício sai da sessão com o aviso "sem opção em casa para X". Na folha Trocar em modo casa valem só candidatos de casa pela regra do RF-34. |
| **H3 Sem repetição** | Dois exercícios do mesmo dia não viram o mesmo exercício de casa: o segundo recebe o próximo candidato da lista. |
| **H4 Alvo e histórico** | O alvo (séries, faixa, RIR, descanso) vem do exercício original. A carga e a nota vêm do histórico do exercício de casa (P1–P12); sem histórico, `calibrate`. Peso do corpo com carga 0 segue P8 (a progressão sobe repetições e, no topo da faixa, sugere carga adicional, por exemplo uma mochila; a ficha mostra "+ 2,5 kg extra", RF-46). |

### 7.14 Fôlego: cardio simples em minutos (v2.3)

Pedido do dono (2026-09-27, D2): o objetivo `endurance` deixa de ser resistência muscular localizada e passa a ser **cardiovascular**, "aumentar o fôlego". Ele prescreve poucas sessões simples, medidas em minutos, com a intensidade sentida pelo teste da fala. Não há zonas, ritmo nem FC.

| Regra | Descrição |
|-------|-----------|
| **F1 Aeróbico e minutos** | Um exercício é aeróbico quando o catálogo o marca com o padrão `cardio`. Ele mede em `minutes` (RF-43): o número da série é o de minutos inteiros. A prescrição mostra "30 min" ou, com mais de uma série, "4 × 3 min". O descanso entre séries é a recuperação leve (andar ou pedalar devagar). |
| **F2 Três sessões** | O plano do seed tem 3 dias:<br>- **contínuo moderado**: 20–45 min;<br>- **intervalos**: 4 × 2–4 min forte, com 3 min de recuperação;<br>- **longo e leve**: 30–60 min.<br>Cada dia tem 1 ou 2 complementos de força-resistência (§7.9, 2 séries de 12–20).<br>A intensidade vem do teste da fala: no moderado, dá para conversar, mas não para cantar; no forte, só dá para dizer poucas palavras; no leve, a conversa é fácil. Os textos (passos do "Como fazer" e informações do exercício) dizem isso em palavras, nunca em FC ou números de ritmo (§7.6, P12). |
| **F3 Progressão por minutos** | P4–P6 sobre os minutos (§7.2), sem regra nova:<br>- P5 soma 1 minuto por sessão até o topo da faixa;<br>- sem carga (o normal no aeróbico), a sessão fica no topo (P8 D3), porque aeróbico nunca ganha carga sozinho;<br>- o nível da máquina (bicicleta, remo, elíptico: `level`, incremento 1) é opcional. Se a pessoa registrar um nível, P4 sobe 1 nível no topo da faixa e os minutos recomeçam no mínimo;<br>- P6 (menos minutos que o mínimo) repete a meta, e P9 (pausa de mais de 21 dias) recomeça no mínimo.<br>No topo das faixas, a semana soma cerca de 45 + 2 × 16 + 60 ≈ 137 min moderados-equivalentes, mais as recuperações, perto dos 150 da OMS (A2). |
| **F4 Fora das contas de força** | Aeróbicos não entram:<br>- na tonelagem (RF-12, RF-43);<br>- no 1RM estimado nem nos marcos (R1, C6);<br>- no volume por grupo (R3) nem nas sugestões de R5 por exercício (R8).<br>Contam na aderência (R4) e, pela convenção das pernas (§7.4), no painel "Esta semana" e na escolha do dia pela semana (S5–S7). Substituem-se entre si (RF-34) e têm equivalentes de casa (H1, H2). |
| **F5 Saúde** | Até a tarefa de HealthKit do Fôlego, a sessão vai para o Saúde como treino de força (RF-13) e não entra nos minutos aeróbicos (A1). Na semana leve (§7.5), os aeróbicos de 1 série ainda não encurtam. Os dois ajustes ficam para a onda de telas da 2.3. |

Base:
- **Garber 2011 (ACSM):** 150 min moderados por semana e progressão gradual da duração;
- **Bull 2020 (OMS):** 150–300 min moderados ou 75–150 vigorosos, e força 2 ou mais dias por semana;
- **Milanović 2015**, meta-análise, Sports Medicine 45(10), `10.1007/s40279-015-0365-0`: intervalos e treino contínuo melhoram o VO2máx, e os intervalos um pouco mais;
- **Helgerud 2007:** 4 × 4 min forte melhoram o VO2máx mais que o moderado;
- **Foster 2008:** o teste da fala acompanha a intensidade do exercício.

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
8. Programa inicial padrão, ajustável no JSON semente.
   - Até a M1: 3 dias, A empurrar / B inferior / C puxar.
   - De 2026-09-23 até a 2.2: o Completo de hipertrofia era o **corpo todo**, em 3 dias.
   - Desde a 2.3: o padrão é o **Equilibrado**, com 4 dias alternando superior e inferior e cada grupo 2×/semana (§7.9, decisão 19). O corpo todo fica escondido.
9. Peso corporal: `loadIncrement` = 2,5 kg (carga adicional), carga 0 permitida só para `bodyweight`. Todo exercício do catálogo tem `loadIncrement` > 0 (validado no seed).
10. Só RIR entra na avaliação; séries com RIR ausente não recebem o bônus de P4.
11. O app do Watch é **opcional** por desenho: tudo em M1–M2 funciona só com o iPhone, e a FC vem do app Exercício nativo do relógio via HealthKit até o companion existir (ver §7.6 e §13).
12. Sem Mac: o projeto Xcode é gerado por XcodeGen no GitHub Actions; o motor é testado localmente no Windows (ARCHITECTURE ADR 008/009).
13. **Sem IA no app gratuito** (2026-09-23). Revisão periódica e saúde são regras determinísticas (§7.8, §7.10). Ideia futura do usuário, fora do escopo atual: uma camada paga opcional com IA para personalização extra. Se for adiante, exige ADR própria e continua sem tocar no motor determinístico (a IA só proporia ajustes que o usuário aceita).
15. **Identidade visual desvinculada da cultura de academia** (pedido do usuário, 2026-09-23): nada de halteres, preto/neon, músculos ou linguagem agressiva. Paleta terrosa (bege, areia, marrom), ícone com símbolo de pétalas ligado aos objetivos, e os **objetivos como elemento central** da interface. Guia em `DESIGN.md`; aplicado numa passada de design logo após a integração do M2.
14. Aeróbico (revista na 2.3, decisão 19):
    - Até a 2.2, o aeróbico era registrado pelo app Exercício do Watch e só lido pelo app, que não prescrevia cardio (só meta semanal e sugestões de encaixe).
    - Desde a 2.3, o objetivo **Fôlego** prescreve cardio simples: 3 sessões por semana medidas em minutos, com a intensidade pelo teste da fala e a progressão de P4–P6 sobre os minutos (§7.14, RF-48). Fora do Fôlego, continua valendo a regra antiga.
    - Continuam fora do app: zonas de FC, ritmo, distância e planos de prova. A FC nunca prescreve nada (§7.6).
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
19. **Versão 2.3** (pedidos do dono em 2026-09-27, depois de usar a 2.2; contrato do núcleo `docs/V23-CORE-CONTRACT.md`):
    - **D1 Hipertrofia equilibrada:** "o correto seria equilibrado, … com as divisões por dia habituais". O Equilibrado vira o padrão: 4 dias Superior/Inferior, 5 exercícios, cada grupo 2×/semana (RF-35, §7.9). O Corpo todo fica escondido, como o Empurrar/Inferior/Puxar. Os formatos passam a ser Equilibrado, Mais pernas e glúteos e Mais tronco e braços.
    - **D2 Fôlego:** "o programa de resistência muscular deve mudar, deve ser cardiovascular, aumentar o fôlego". O objetivo `endurance` (raw value igual) vira Fôlego, cardio simples em minutos (RF-48, §7.14). A decisão 14 foi revista. O antigo programa "Resistência muscular" sai do seed; quem já o tem, mantém.
    - **D3 Carga opcional:** "não obrigar colocar carga para poder marcar as séries e o exercício feito; a carga é só se o cara usar carga". Em qualquer exercício, 0 = sem carga externa. A prescrição fica em 0 e progride por repetições, segundos ou minutos até a pessoa pôr carga (P2, P4, P6, P8, P9, §7.5, RF-04, RF-44 c, RF-46). O peso do corpo mantém a carga extra no topo da faixa (decisão 18).
    - **D4 Medida `minutes`** (RF-43).
    - **D5 "Como fazer" já:** guias para os 62 exercícios que o app usa, desenhadas por agentes em lotes e revisadas pelo dono (decisão 17). O formato ganhou âncora em qualquer ponto, `static` de 1 quadro, braço do lado de lá por ângulos, escorço das pernas, `works` e a trava E10 (§7.12).
    - Também pedidos, com contrato próprio depois da pesquisa de estética: sessão ainda mais simples depois de "Começar", estética "budista, porém estoica" e uma animação de abertura leve.
    - Referências conferidas no Crossref em 2026-09-27. A meta-análise de Milanović é de 2015 (Sports Medicine 45(10)), e não de 2016, como constava no pedido.

## 12. Questões abertas (não bloqueiam M0–M1)

- Exercícios unilaterais: registrar um lado ou os dois? (Proposta M2: uma série = os dois lados; reps do lado mais fraco.)
- Regra de "grande salto" (P4, +2·inc) pode ser agressiva em máquinas de 5 kg; revisar após 4 semanas de uso real. (Desde a 2.2 as séries novas não têm RIR, então o salto não acontece com dados novos; decisão 18.)
- Peso do corpo no topo da faixa (RF-46): hoje recebe carga extra (P4/H4). Se incomodar, sobretudo em explosivos e no Combate em casa, a alternativa "nunca pôr carga e sugerir uma variação mais difícil" é regra nova do motor, em tarefa própria com SPEC e teste de tabela. Desde a 2.3 (D3), qualquer outro exercício sem carga fica em 0 no topo da faixa. Se o dono quiser o mesmo no peso do corpo, basta tirar a exceção do P4.
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
