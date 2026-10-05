# Decisões do dono para a onda de telas da 2.3 (2026-09-27)

Aplicar no contrato da onda de telas; também vão para o HANDOFF quando o main estiver livre.

1. **Nome do objetivo cardiovascular: "Cardio"**, subtítulo "Coração forte e mais condicionamento". Troca o provisório "Fôlego" que o núcleo (v6/core) usou em GoalStyle, textos e SPEC. O raw value continua `endurance`.
2. **Carga opcional, no espírito do dono:** o uso mais simples do app (só marcar o treino e lembrar os exercícios) funciona sem preencher nada. Quem quiser pode informar carga e repetições diferentes. O app pode **sugerir com delicadeza** quando o dado ajuda no acompanhamento ("Anotar a carga ajuda a sugerir quando subir"), sem obrigar e sem insistir: no máximo uma vez por exercício, com dispensa.
3. **Animação de abertura com a flor:**
   - Tela de lançamento estática azul-marinho com a flor Brisa no centro, idêntica ao ícone: `UILaunchScreen` com `UIColorName` e `UIImageName` no project.yml, tarefa [PROJ], mais os assets.
   - Na primeira tela, a flor gira meia volta, suave (cerca de 0,8 s), e as pétalas se abrem para fora e se dissolvem, revelando a tela Hoje.
   - Com Reduzir Movimento, só um esmaecimento rápido.
   - Nunca bloqueia a interação e só roda na abertura a frio.
   - O movimento do ícone até o centro é o zoom do próprio iOS; o app não controla isso.
4. **Mais de um plano ao mesmo tempo** (pedido de 2026-09-27): a pessoa pode ativar mais de um plano (ex.: Hipertrofia Equilibrado + Cardio). O app **verifica o encaixe** antes de aceitar: dias disponíveis na semana, se aceita 2 sessões no mesmo dia ou treino todo dia, descanso de ≥ 48 h por grupo muscular (S6), cardio vigoroso nunca nas 24 h antes de um dia de pernas e, no mesmo dia, força antes do cardio ou ≥ 6 h de intervalo (A5), pelo menos 1 dia de descanso completo recomendado. Se não couber, explica e sugere (menos sessões de cardio, cardio leve depois da força nos dias de superior etc.). A tela Hoje mostra as sessões do dia ("Superior + Cardio leve 25 min"). Precisa de regras novas na SPEC (§7.14) e de uma função pura no TrainerCore (encaixe semanal), testada.
5. **Prévia do Cardio aprovada para referência** (ver a mensagem de 2026-09-27): A contínuo moderado 25–40 min + complemento curto; B intervalos 6–10 × (1 min forte / 2 min leve) com aquecimento e volta à calma; C longo leve 40–60 min; progressão pela duração/número de intervalos; meta OMS 150 min moderados-equivalentes.
6. **Animação:** conferir se está elegante e satisfatória; se ficar tosca ou desconfortável, mudar (protótipo em docs/design/v23-animation/).
7. ~~Cardio base em todo plano~~ **CANCELADO pelo dono (2026-09-27): "deixe como está".** Os planos não ganham cardio obrigatório; o cartão de Saúde continua acompanhando os minutos de aeróbico e sugerindo completar a meta, como hoje.
8. **Plano Cardio focado em VO2máx — APROVADO pelo dono ("boa")** (substitui a prévia do item 5):
   - A: base aeróbica, 30–45 min contínuos, conversando (modelo polarizado, cerca de 80/20).
   - B: 4×4, aquecimento de 10 min + 4 × (4 min a 85–95 % da FCmáx + 3 min leves) (Helgerud 2007).
   - C: longo leve, 45–75 min.
   - D opcional: 6 × 30 s bem fortes com 2–4 min leves (SIT; Gist 2014).
   - Progressão: o longo cresce aos poucos; o 4×4 vai de 3 para 4 e depois 5 blocos.
   - Zonas de FC e VO2máx mostrados quando o relógio fornece.
   - Referências a verificar no Crossref: Helgerud 2007 (MSSE), Milanović 2016, Stöggl & Sperlich 2014, Gist 2014, Bacon 2013.
9. **Quando os planos não cabem:** o app mostra todas as mudanças que fazem caber (mais dias por semana, permitir 2 sessões no mesmo dia, cardio leve depois da força, menos sessões de cardio), cada uma com a semana resultante. A pessoa escolhe o que pesa mais.
10. **Hipertrofia × Força:** mantidos os dois. O "Por quê?" de cada objetivo explica a diferença:
    - na hipertrofia, cargas leves ou pesadas dão resultado parecido perto do limite (Schoenfeld 2017);
    - na força máxima, carga alta vence (especificidade).
11. **Consequências de combinar planos** (2026-09-27): ao adicionar um segundo plano, o app mostra as consequências **positivas, negativas e neutras** da combinação, em frases curtas e com "Por quê?" (referências). É uma tabela determinística por par de objetivos, na SPEC §7.14. Exemplos:
    - Hipertrofia + Cardio: + coração e VO2máx, + recuperação entre séries; = ganho de músculo quase igual, se o cardio for separado ou moderado (Schumann 2022); − semana mais longa e mais cansaço; − os intervalos fortes na véspera de pernas atrapalham.
    - Força + Cardio: + condicionamento; − pode reduzir um pouco a força explosiva, sobretudo com cardio intenso no mesmo dia; = força máxima pouco afetada com a separação certa.
    - Força + Combate ou Hipertrofia + Força: = grande sobreposição (os mesmos levantamentos); o app avisa que é quase redundante e sugere um plano só ou um formato.
    - Longevidade + qualquer um: + equilíbrio e mobilidade; = pouco conflito.
12. **Força × Combate:** compartilham a base de força máxima (compostos com 3–6 repetições). O Combate acrescenta potência, condicionamento intermitente, pegada, tronco e pescoço, com menos volume nos grandes levantamentos. O "Por quê?" e a tela de objetivos explicam a diferença; ao combinar os dois, o app marca como "grande sobreposição".
13. **Detalhes sutis da abertura** (2026-09-28): o resultado do método (crítico + refino, workflow `wf_033bc874-622`) vale como está, inclusive a continuidade, se o crítico mantiver. O dono gostou da luz e do ensō e não gostou da continuidade, mas disse que é só um sinal de gosto para as próximas etapas, não uma correção: NÃO sobrepor o resultado do método.
14. **Decisões de 2026-09-28** (valem para a onda de telas):
    - **Direção visual: A · Tinta e papel** (docs/design/v23-aesthetics/directions.html), trazendo também **mensagens estoicas** junto com o lado budista. As citações são de domínio público (Sêneca, Marco Aurélio, Epicteto, Dhammapada), em pt-BR, com a fonte.
    - **Pólen: entra**, discreto, na abertura. O dono pediu explicitamente.
    - **Desenhos do "Como fazer": aprovados** (T6.8, CA6-7 para os 55 de 2026-09-28).
    - **Tela inicial nova:** o app não abre direto no treino do dia. Primeiro vem uma **home bonita**: a flor pintada em tinta, uma saudação, a mensagem do dia (estoica ou budista), um resumo calmo da semana e um caminho claro para o treino de hoje. A tela Hoje com os treinos vem em seguida.
15. **Tela inicial SEM mensagem** (2026-09-28, decisão do dono, PREVALECE sobre o contrato V23-UI e sobre o item 14): a home nova não tem mensagem do dia nem citação estoica ou budista. Fica com a flor pintada em tinta, a saudação, o resumo calmo da semana e o caminho claro para o treino de hoje. Não criar o JSON de citações. Se o contrato ou uma tarefa já previu mensagens na home, remova.
16. **Sem mensagens em NENHUM local do app** (2026-09-28, decisão do dono, PREVALECE sobre o contrato V23-UI e sobre a direção A): nenhuma citação, frase inspiracional, mensagem estoica ou budista, "mensagem do dia" ou frase de efeito em tela alguma (home, sessão, resumo, estados vazios, abertura, Ajustes). A direção Tinta e papel fica só no visual. Os avisos FUNCIONAIS do diálogo do app (§7.11 C1–C8: semana leve, revisão, saúde, validade da instalação, backup) continuam, porque são recursos, não mensagens de efeito.
17. **Tela "Metas da semana"** (2026-09-28, pedido do dono): uma tela que reúne as metas da semana para a pessoa ver como está. Sempre: sessões do plano (ex.: 3 de 4), músculos (frequência 2×/semana por grupo, o painel que hoje está no Histórico), aeróbico (150 min moderados-equivalentes), passos (média de 7.000/dia) e sono (média de 7–9 h). Só quando o plano pede: equilíbrio e mobilidade (Longevidade) e sessões de cardio (plano Cardio ativo). Visual Tinta e papel: cada meta como uma marca de tinta que se completa, sem anéis, sem vermelho, sem culpa; os dados que faltam (sem relógio) aparecem como "sem dados", não como falha. Acesso a partir da tela inicial. Sem mensagens de efeito (item 16).
18. **Passos só em Longevidade e Cardio** (2026-09-28, decisão do dono, PREVALECE sobre o item 17): a meta de passos aparece na tela Metas da semana, e em qualquer outro lugar do app, só quando um plano ativo é Longevidade ou Cardio. O motivo: passos se associam a menor mortalidade e a saúde cardiovascular (Paluch 2022; Saint-Maurice 2020), e não a hipertrofia nem a força. Nos outros planos, a meta e a linha de passos do cartão de Saúde não aparecem.
19. **Atividades fora do app** (2026-09-29, ideia do dono, para a PRÓXIMA versão, 2.4, não para a onda atual): um espaço para registrar exercícios feitos fora do app (pilates, cross, spinning, aula de luta, futebol etc.), com duração e intensidade, avulsos ou fixos na semana (ex.: pilates toda terça). Eles contam para as metas da semana (aeróbico, quando for o caso), para o encaixe semanal (ocupam o dia, grupos e intensidade: spinning é cardio vigoroso e segue A5; cross é corpo todo intenso; pilates é leve, com tronco e mobilidade) e para a recuperação. Treinos gravados no app Saúde por outros apps ou pelo relógio já contam no aeróbico; o registro manual cobre o que não passa pelo relógio. Persistência sem SchemaV3, se der (JSON como as decisões de semana leve), incluída no backup.
20. **Lançamento na App Store** (2026-10-05, decisões do dono; SPEC decisão 22, §7.18 L1–L8, TASKS M6):
    - "1. aprovo" lançar grátis na App Store do Brasil, sem anúncios. Vender ou repassar dados de usuários está fora de questão (regras da Apple para dados de saúde e LGPD).
    - "2. pode" reduzir os builds de CI antes de fechar o repositório (feito na T11.1).
    - "3. só o que for indispensável" em avisos; "avaliação depois de 1 semana", "do jeito menos invasivo possível" (L3).
    - "Dados não coletados: inclua", mostrando com fatos que o app segue as regras e as leis (L1, L2), sem promessas absolutas.
    - **Nome na loja: "Magister: Treino com Ciência"** ("esse"). Embaixo do ícone continua "Magister". O dono queria ressaltar a base científica: os textos dizem "com base científica" ou "baseado em estudos publicados", nunca "validado cientificamente".
    - Em aberto (decisões do dono): subtítulo da loja, bundle ID da loja, classificação de idade, modelo e conteúdo do plano pago (inclusive o uso de IA; decisão 13 em revisão).
