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
| P-2 | Motor determinístico | Mesma entrada → mesma prescrição. Sem aleatoriedade, sem IA no caminho crítico. IA é opcional e periódica (M5). |
| P-3 | Offline-first | Todas as funções principais funcionam sem rede. Nenhum backend, nenhuma API paga. |
| P-4 | iPhone é a fonte da verdade | O Apple Watch é um cliente fino que espelha a sessão ativa e envia eventos. Não há dois bancos de dados a reconciliar. |
| P-5 | Dados são sagrados | Cada série é persistida no momento em que é concluída. Exportação completa em JSON a partir do M2. |
| P-6 | Frequência cardíaca é informação, não controle | FC é registrada e exibida, nunca usada para prescrever carga/volume (ver §7.6). |
| P-7 | Simplicidade adequada a app pessoal | Sem contas, sem sync em nuvem, sem localização, sem App Store. Distribuição via Xcode no próprio aparelho. |

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
- Pacote de análise periódica (JSON/Markdown) para revisão por IA fora do app (M5, opcional).

### 3.4 Fora do escopo (explicitamente)

Backend, contas, sync em nuvem/CloudKit, funções sociais, nutrição, cardio programado, vídeos de exercícios, planos pagos, Android, layout de iPad, publicação na App Store, localização para outros idiomas (UI em pt-BR fixo), IA em tempo real durante o treino.

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
| RF-12 | Exibir duração da sessão, total de séries de trabalho e tonelagem (Σ carga × reps). | M2 |
| RF-13 | Gravar `HKWorkout` do tipo treino de força ao finalizar, com início/fim reais. Exatamente um `HKWorkout` por sessão. | M2 |
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
| RF-26 | Gerar pacote de análise periódica para revisão externa (IA opcional). | M5 |

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
| **P3 Referência** | Avalia-se a **última sessão concluída ou abandonada** em que o exercício teve ≥ 1 série de trabalho. Carga de referência **L** = moda das cargas das séries de trabalho dessa sessão (empate → maior). |
| **P4 Sucesso → subir** | Se nº de séries de trabalho ≥ S **e** todas com reps ≥ `repMax` → nova carga = L + inc, meta = `repMin`, nota `increase`. Se além disso min(RIR) ≥ T + 2 → L + 2·inc. |
| **P5 Manter → mais reps** | Se todas as séries com reps ≥ `repMin` mas P4 não vale → carga = L, meta = min(`repMax`, menor reps da última sessão + 1), nota `hold`. |
| **P6 Falha** | Se alguma série de trabalho com reps < `repMin`: primeira ocorrência → carga = L, meta = `repMin`, nota `retry`. Se a sessão anterior a essa (mesmo exercício) também foi falha **na mesma carga L** → nova carga = arredondar↓(L × 0,9, inc), no mínimo L − inc, nota `decrease`. |
| **P7 Séries incompletas** | Se séries de trabalho < S, não há sucesso (P4). Avalia-se P5/P6 sobre as realizadas. Se 0 séries de trabalho, a sessão é ignorada e usa-se a anterior. |
| **P8 Arredondamento** | Toda carga prescrita é múltiplo de inc. Mínimo = inc (0 para peso corporal). |
| **P9 Retorno após pausa (M2)** | Se a última sessão do exercício tem > 21 dias → carga = arredondar↓(L × 0,9, inc), nota `returning`. Prevalece sobre P4–P6. |
| **P10 Override** | O usuário pode alterar carga/reps na hora. Vale o registro real. Nada é corrigido retroativamente. |
| **P11 Determinismo** | Mesma entrada → mesma saída. `now` é parâmetro explícito. Sem aleatoriedade. |
| **P12 FC** | Nenhuma métrica de frequência cardíaca é entrada do motor. Garantido por tipo: a struct de entrada não tem campo de FC. |

Parâmetros padrão: S = 3, faixa 8–12, T = 2, descanso 120 s. Séries retas (mesma carga em todas as séries de trabalho). Autorregulação intra-sessão automática **não** existe em v1; o usuário ajusta a carga da próxima série manualmente se quiser.

### 7.3 Seleção do próximo treino

**v1 — rotação (M1)**

| Regra | Descrição |
|-------|-----------|
| **S1** | O programa ativo tem dias ordenados D1…Dn. |
| **S2** | Próximo = dia seguinte ao da última sessão `completed` ou `abandoned` com ≥ 1 série de trabalho. Se não há nenhuma → D1. Após Dn → D1. |
| **S3** | Se existe sessão `inProgress`, o "próximo treino" é retomá-la. |
| **S4** | O usuário pode escolher outro dia manualmente; a rotação segue a partir do dia escolhido. |

**v2 — frequência e recuperação (M4)**

| Regra | Descrição |
|-------|-----------|
| **S5** | Para cada dia candidato, pontuar = nº de grupos primários do dia que estão abaixo da meta semanal (§7.4). |
| **S6** | Excluir candidatos com algum grupo primário trabalhado (como primário) há < 48 h. Se todos forem excluídos, ignorar S6. |
| **S7** | Escolher maior pontuação; empate → ordem da rotação (S2). |

### 7.4 Frequência semanal por grupo muscular

- Grupos: peito, costas, ombros, bíceps, tríceps, quadríceps, posteriores, glúteos, panturrilhas, core.
- Semana começa na segunda-feira (configurável).
- Um grupo conta **1** em uma sessão concluída se houve ≥ 1 exercício com esse grupo como **primário** e ≥ 1 série de trabalho registrada. Secundário não conta (v1).
- Meta padrão: 2×/semana por grupo; configurável por grupo.
- v1 (M2) só **exibe** realizado/meta. v2 (M4) usa isso na seleção (S5–S7).

### 7.5 Deload (M4)

Gatilhos (qualquer um): (a) ≥ 50 % dos exercícios do programa com nota `decrease` na prescrição atual; (b) a cada N semanas de treino (padrão 6, configurável); (c) manual.

Conteúdo: durante 1 semana (uma passagem completa da rotação), cada exercício recebe séries = ⌈S × 0,6⌉, carga = arredondar↓(L × 0,85, inc), RIR alvo = 4, nota `deload`. Sessões de deload **não** contam como falha nem sucesso para P4–P6; após o deload a prescrição volta ao estado anterior.

### 7.6 Política de frequência cardíaca

FC **é usada para**: exibir ao vivo no relógio (M3); resumo da sessão (média/máx); pacote de análise periódica (M5); opcionalmente, dica no timer ("FC abaixo de X bpm"), desligada por padrão (M3).

FC **nunca é usada para**: prescrever carga, séries ou repetições; decidir deload; alterar seleção de treino.

Motivo: em musculação, FC reflete descanso, cafeína, temperatura e estresse muito mais do que prontidão muscular. Usá-la para carga produziria prescrições erráticas e não determinísticas na prática.

### 7.7 Determinismo e IA

O motor (progressão + seleção + deload) é código puro em Swift, testado por casos de tabela. IA (M5) só recebe um **pacote de análise** exportado e devolve **sugestões de alteração de programa** que o usuário aplica manualmente ou importa como novo programa. A IA nunca escreve no banco durante uma sessão.

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

Ver [TASKS.md](TASKS.md): M0 esqueleto → M1 MVP iPhone → M2 robustez + HealthKit + edição + backup → M3 Apple Watch → M4 inteligência de programa → M5 análise por IA (opcional).

## 11. Decisões já tomadas

1. Só RIR é armazenado; RPE é exibido como conversão.
2. Séries retas em v1; sem pirâmide, sem drop set.
3. Histórico e progressão indexados por exercício do catálogo (`slug`), não por programa.
4. iPhone é a fonte da verdade; Watch sem SwiftData (snapshot Codable em arquivo).
5. Exatamente um `HKWorkout` por sessão; quem roda a `HKWorkoutSession` grava (M2: iPhone via `HKWorkoutBuilder`; M3: Watch).
6. UI em pt-BR com strings fixas no código; sem localização.
7. Sem CloudKit. Backup manual em JSON.
8. Programa inicial padrão: 3 dias (A: Superior empurrar, B: Inferior, C: Superior puxar) — ajustável no JSON semente.

## 12. Questões abertas (não bloqueiam M0–M1)

- Exercícios unilaterais: registrar um lado ou os dois? (Proposta M2: uma série = os dois lados; reps do lado mais fraco.)
- Peso corporal com carga adicional: `loadIncrement` = 2,5 kg e carga = adicional; peso corporal puro = 0.
- Regra de "grande salto" (P4, +2·inc) pode ser agressiva em máquinas de 5 kg; revisar após 4 semanas de uso real.
