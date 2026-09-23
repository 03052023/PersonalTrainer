# SPEC — Personal Trainer Automático (iPhone + Apple Watch)

Versão 0.1 · 2026-09-22 · Uso pessoal (um único usuário).

Este é o documento de **produto e regras de domínio**. A arquitetura técnica está em [ARCHITECTURE.md](ARCHITECTURE.md), o plano de execução em [TASKS.md](TASKS.md) e as regras para agentes de código em [AGENTS.md](AGENTS.md).

---

## 1. Objetivo

Abrir o app na academia e **não precisar pensar**. O app diz:

1. qual treino fazer hoje;
2. quais exercícios, em que ordem;
3. quantas séries, quantas repetições e qual carga em cada uma;
4. quanto descansar.

Depois que cada série é registrada (carga, repetições, RIR), o app recalcula **automaticamente e de forma determinística** a prescrição do próximo treino. Não existe etapa manual de "planejar a próxima semana".

## 2. Princípios de projeto

| # | Princípio | Consequência prática |
|---|-----------|----------------------|
| P-1 | Zero decisões na academia | A tela inicial já é o treino do dia com tudo preenchido. Um toque para iniciar, um toque por série. |
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
- Sessão ativa: registrar carga, reps e RIR de cada série; valores pré-preenchidos; pular/substituir exercício.
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

**F1 — Abrir o app.** A tela inicial exibe "Próximo treino: Dia B — Inferior", a lista de exercícios com "3 × 8–12 · 60 kg · RIR 2 · 2 min" e um botão **Iniciar**. Se há uma sessão em andamento, o botão vira **Retomar**.

**F2 — Executar uma série.** Na tela do exercício, a série atual aparece pré-preenchida com carga, reps alvo e RIR alvo. O usuário ajusta se necessário (steppers grandes) e toca **Concluir série**. A série é gravada imediatamente e o timer de descanso inicia. Ao zerar, notificação/haptic. A próxima série vem pré-preenchida com os valores da série anterior.

**F3 — Máquina ocupada.** O usuário pode **pular** o exercício (fica registrado como pulado) ou **substituir** por outro do catálogo do mesmo grupo muscular (M2). A substituição vale só para esta sessão.

**F4 — Finalizar.** Botão **Finalizar treino** → resumo (duração, séries, tonelagem, FC média/máx se disponível) → sessão marcada como concluída → HealthKit recebe o treino (M2) → a tela inicial já mostra o próximo treino recalculado.

**F5 — Histórico.** Lista de sessões por data; detalhe com cada exercício e cada série; por exercício, evolução de carga (M2).

**F6 — Relógio (M3).** Ao iniciar no iPhone, o relógio mostra a mesma sessão. Ao iniciar no relógio, o iPhone é notificado. Séries registradas em qualquer um aparecem no outro. FC ao vivo no relógio.

## 6. Requisitos funcionais

| ID | Requisito | Milestone |
|----|-----------|-----------|
| RF-01 | Exibir o próximo treino com todos os exercícios e prescrições (séries, reps, carga, RIR, descanso) sem intervenção do usuário. | M1 |
| RF-02 | Iniciar, retomar e finalizar uma sessão. Só pode existir uma sessão em andamento. | M1 |
| RF-03 | Registrar por série: carga (kg, passo = incremento do exercício), repetições, RIR (0–5), aquecimento sim/não, hora. | M1 |
| RF-04 | Pré-preencher cada série com a prescrição; a partir da 2ª série, com os valores reais da série anterior. | M1 |
| RF-05 | Timer de descanso com duração do exercício, iniciado ao concluir a série, com notificação local ao terminar mesmo com app em segundo plano. | M1 |
| RF-06 | Persistir cada série no momento da conclusão. Matar o app não perde nenhuma série concluída. | M1 |
| RF-07 | Recalcular a prescrição de cada exercício a partir do histórico conforme §7.2 ao finalizar a sessão. | M1 |
| RF-08 | Selecionar o próximo dia do programa conforme §7.3. | M1 |
| RF-09 | Histórico: lista de sessões e detalhe com séries. | M1 |
| RF-10 | Pular exercício na sessão. | M1 |
| RF-11 | Substituir exercício por outro do catálogo (mesmo grupo primário), apenas para a sessão. | M2 |
| RF-12 | Exibir duração da sessão, total de séries de trabalho, exercícios realizados (≥ 1 série de trabalho) e tonelagem (Σ carga × reps das séries de trabalho). | M2 |
| RF-13 | Gravar `HKWorkout` do tipo treino de força ao finalizar, com início/fim reais. Exatamente um `HKWorkout` por sessão. Se já existe no HealthKit um treino de força de outro app (ex.: app Exercício do Watch) sobrepondo ≥ 50 % do intervalo da sessão, **vincular** esse treino em vez de criar outro. | M2 |
| RF-14 | Ler amostras de FC do HealthKit no intervalo da sessão e exibir média e máxima no detalhe. | M2 |
| RF-15 | Editar catálogo de exercícios: nome, grupos musculares, equipamento, incremento, anotações de máquina. | M2 |
| RF-16 | Editar programa: trocar exercício, ajustar séries/faixa/RIR/descanso/carga inicial. | M2 |
| RF-17 | Painel de frequência semanal por grupo muscular (realizado / meta). | M2 |
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
| RF-32 | Botão "Por quê?" em notas de prescrição, metas e sugestões, mostrando a regra e as referências científicas completas do catálogo `references.v1.json` (§7.9). | M2 (catálogo e notas), cresce a cada milestone |

## 7. Regras de domínio

### 7.1 Conceitos

- **Exercício (catálogo)**: movimento + equipamento. Tem `slug` estável (ex.: `leg-press-45`), grupos musculares primário/secundários, tipo de carga (kg, placas, nível) e **incremento mínimo** (`loadIncrement`: 2,5 kg barra/halter; 5 kg máquina de placas; 1 nível).
- **Programa**: conjunto ordenado de **Dias** (A, B, C…). Cada Dia tem uma lista ordenada de **Exercícios do Programa** com parâmetros: `sets` (S), `repMin`/`repMax`, `targetRIR` (T), `restSeconds`, `startingLoad` (opcional).
- **Prescrição**: o que o motor manda fazer hoje para um exercício: carga, S, faixa de reps, meta de reps, RIR alvo, descanso e uma **nota** (`calibrate`, `increase`, `hold`, `retry`, `decrease`, `returning`, `deload`).
- **Sessão**: uma execução de um Dia, com status `inProgress`, `completed` ou `abandoned`. Contém **Exercícios da Sessão** (snapshot da prescrição) e **Séries** registradas.
- **RIR** (Reps in Reserve): quantas repetições faltavam para a falha. É a métrica de esforço primária. RPE, quando exibido, é `10 − RIR`. Só RIR é armazenado.
- **Histórico é por exercício, não por programa.** Trocar de programa não zera cargas.

### 7.2 Motor de progressão v1 — dupla progressão

Aplicado por exercício, independentemente dos demais.

| Regra | Descrição |
|-------|-----------|
| **P1 Séries de trabalho** | Só séries com `isWarmup = false` entram na avaliação. |
| **P2 Sem histórico** | Se `startingLoad` definido → carga = `startingLoad`, meta = `repMin`, nota `calibrate`. Senão → carga vazia; o usuário digita na 1ª série; RIR alvo = T + 1. |
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
| **S2** | Próximo = dia seguinte (na ordem de `order`) ao da última sessão `completed` ou `abandoned` com ≥ 1 série de trabalho. Se não há nenhuma, ou se o dia dessa sessão não existe mais no programa (programa editado) → D1. Após Dn → D1. `order` é único dentro do programa (invariante validado no seed). Empates de data são desfeitos pelo id da sessão (P11). |
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
- v1 (M2) só **exibe** realizado/meta. v2 (M4) usa isso na seleção (S5–S7).

### 7.5 Deload (M4)

Gatilhos (qualquer um): (a) ≥ 50 % dos exercícios do programa com nota `decrease` na prescrição atual; (b) a cada N semanas de treino (padrão 6, configurável); (c) manual.

Conteúdo: durante 1 semana (uma passagem completa da rotação), cada exercício recebe séries = ⌈S × 0,6⌉, carga = arredondar↓(L × 0,85, inc), RIR alvo = 4, nota `deload`. Sessões de deload **não** contam como falha nem sucesso para P4–P6; após o deload a prescrição volta ao estado anterior.

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
| **R3 Volume** | Séries de trabalho por grupo primário por semana, comparadas à faixa alvo do objetivo do programa (§7.9). Abaixo → sugerir +1 série por exercício do grupo (máx. +2 por revisão); acima do teto com fadiga (R2) → sugerir −1. |
| **R4 Aderência** | Sessões concluídas por semana vs. dias do programa; se < 70 % em 4 semanas, sugerir programa com menos dias antes de sugerir mais volume. |
| **R5 Sugestões** | Deload (R2 verdadeiro, ou R1 em ≥ 50 % dos exercícios); troca de exercício ou de faixa de repetições (R1 em um exercício por 2 revisões seguidas); ajuste de volume (R3); mudança de frequência (R4). Cada sugestão traz o motivo em uma frase e os números que a geraram. |
| **R6 Sinais secundários do HealthKit** | Tendência de HRV e de FC de repouso (média de 7 dias vs. 28 dias) e horas de sono, quando disponíveis. Só **modulam** sugestões já geradas por R1–R4: HRV em queda ≥ 10 % reforça deload; HRV estável ou em alta enfraquece (a sugestão vira "opcional"). Nunca geram sugestão sozinhos, nunca alteram carga de série (P12). |
| **R7 Determinismo** | Mesmo histórico → mesmo relatório. Cada sugestão exibe a regra (R1–R6) e os números que a geraram; não há geração de texto por IA. |

Base: autorregulação por RIR/RPE (Zourdos 2016; Helms 2016); dose-resposta de volume (Schoenfeld 2017); frequência ≥ 2×/semana por grupo (Schoenfeld 2016; Grgic 2018); HRV como marcador de recuperação com evidência moderada, majoritariamente em endurance, por isso secundário aqui.

### 7.9 Objetivo do programa (M2)

Cada programa tem um `goal`: `hypertrophy` (padrão), `strength`, `endurance`, `longevity` ou `combat`. Todo programa gerado por padrão tem **5 exercícios por dia** (decisão do usuário, 2026-09-23); o usuário pode adicionar ou remover na edição. O objetivo define os padrões usados pelo seed, pela edição de programa e pela revisão (§7.8):

| Objetivo | Faixa de reps | RIR alvo | Volume alvo por grupo/semana (séries de trabalho) | Descanso |
|----------|---------------|----------|---------------------------------------------------|----------|
| Hipertrofia | 6–12 (compostos), 8–15 (isolados) | 1–3 | 10–20 | 90–180 s |
| Força | 3–6 | 1–3 | 6–12 | 180–300 s |
| Resistência muscular | 12–20 | 2–4 | 8–16 | 60–90 s |
| Longevidade | 8–15 | 2–3 | 6–12 | 90–120 s |

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
| **A3 VO2max** | Lê `vo2Max` do HealthKit (estimado pelo Watch em caminhada/corrida/trilha ao ar livre). Mostra último valor, tendência de 90 dias e faixa por idade e sexo (tabela de referência ACSM/Cooper, "muito baixo" a "excelente"). Sem estimativa há 60 dias → sugestão "Faça 20 min de caminhada rápida ou corrida ao ar livre com o Watch para atualizar o VO2max". |
| **A4 Recuperação** | HRV (SDNN), FC de repouso e sono: média dos últimos 7 dias vs. 28 dias. Sem dado noturno em ≥ 5 dos últimos 7 dias → sugestão "Use o Apple Watch para dormir; ele mede HRV, FC de repouso e sono, que o app usa na revisão periódica". Quedas de HRV ≥ 10 % ou alta de FC de repouso ≥ 5 bpm são exibidas como alerta amarelo e alimentam §7.8 R6. |
| **A5 Encaixe sem interferência** | Ao sugerir aeróbico para completar a meta: preferir dias sem treino de inferior; se no mesmo dia, sugerir ≥ 6 h de intervalo e modalidade de baixo impacto (bicicleta, caminhada) em vez de corrida; nunca sugerir vigoroso nas 24 h antes de um dia de inferior. Base: meta-análises de treino concorrente (Wilson 2012; Schumann 2022) mostram que a interferência na hipertrofia e força é pequena e depende de volume, modalidade e proximidade das sessões. |
| **A6 Determinismo** | Regras fixas e testadas; sugestões trazem o motivo e os números. |

### 7.7 Determinismo

Motor de prescrição (§7.2, §7.3), políticas de programa (§7.5, §7.8) e saúde (§7.10) são código puro em Swift, testados por casos de tabela, sem aleatoriedade e sem IA. O usuário sempre vê a regra e os números por trás de qualquer número ou sugestão.

## 8. Requisitos não funcionais

| ID | Requisito |
|----|-----------|
| RNF-01 | Todas as funções de M1–M4 funcionam sem rede. |
| RNF-02 | Resposta a toque na sessão ativa < 100 ms; "Concluir série" persiste antes de retornar. |
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

Ver [TASKS.md](TASKS.md): M0 esqueleto → M1 MVP iPhone → M2 robustez + HealthKit + edição + backup → M3 Apple Watch (opcional, condicionado à instalação) → M4 inteligência de programa (deload, frequência, revisão periódica) → M5 saúde aeróbica e recuperação.

## 11. Decisões já tomadas

1. Só RIR é armazenado; RPE é exibido como conversão.
2. Séries retas em v1; sem pirâmide, sem drop set.
3. Histórico e progressão indexados por exercício do catálogo (`slug`), não por programa.
4. iPhone é a fonte da verdade; Watch sem SwiftData (snapshot Codable em arquivo).
5. Exatamente um `HKWorkout` por sessão; quem roda a `HKWorkoutSession` grava (M2: iPhone via `HKWorkoutBuilder`; M3: Watch).
6. UI em pt-BR com strings fixas no código; sem localização.
7. Sem CloudKit. Backup manual em JSON.
8. Programa inicial padrão: 3 dias (A: Superior empurrar, B: Inferior, C: Superior puxar) — ajustável no JSON semente.
9. Peso corporal: `loadIncrement` = 2,5 kg (carga adicional), carga 0 permitida só para `bodyweight`. Todo exercício do catálogo tem `loadIncrement` > 0 (validado no seed).
10. Só RIR entra na avaliação; séries com RIR ausente não recebem o bônus de P4.
11. O app do Watch é **opcional** por desenho: tudo em M1–M2 funciona só com o iPhone, e a FC vem do app Exercício nativo do relógio via HealthKit até o companion existir (ver §7.6 e §13).
12. Sem Mac: o projeto Xcode é gerado por XcodeGen no GitHub Actions; o motor é testado localmente no Windows (ARCHITECTURE ADR 008/009).
13. **Sem IA em nenhuma fase** (2026-09-23). Revisão periódica e saúde são regras determinísticas (§7.8, §7.10). Se um dia houver necessidade real, reabre-se a decisão com uma ADR.
14. Aeróbico é registrado pelo app Exercício do Watch e apenas lido pelo app; o app não prescreve sessões de cardio, só meta semanal e sugestões de encaixe.

## 12. Questões abertas (não bloqueiam M0–M1)

- Exercícios unilaterais: registrar um lado ou os dois? (Proposta M2: uma série = os dois lados; reps do lado mais fraco.)
- Regra de "grande salto" (P4, +2·inc) pode ser agressiva em máquinas de 5 kg; revisar após 4 semanas de uso real.
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
