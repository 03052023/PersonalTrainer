# Guia de design: Magister

Versão 1.5 · 2026-10-05 (2.4: atividades fora do app, §9.3, e os ajustes do §13). Vale para iPhone e Apple Watch. Decisões do dono registradas na SPEC (decisões 15, 16, 18, 20 e 21): nome **Magister**, ícone de cinco pétalas creme separadas com miolo areia sobre **azul-marinho**, desde a 2.2 no desenho **Brisa** (pétalas com giro leve e feitas à mão), nada de cultura de academia, uma interface simples (cada tela responde a uma pergunta) e, desde a 2.3, a direção visual **A · Tinta e papel** (§3, §14), só no visual: nenhuma mensagem de efeito em tela alguma (§6).

## 0. O nome

**Magister** é latim para "mestre, quem ensina e guia" (a raiz de "magistério" e de *master*). É o papel de um personal trainer sem o vocabulário de academia: alguém que conhece o caminho, explica o porquê e acompanha a pessoa. Uma palavra só, curta, séria e amigável, que funciona em pt-BR, espanhol, italiano e inglês. Na tela aparece só "Magister". Se um dia for publicado, o título na loja pode ser "Magister: Personal Trainer". Colisões conhecidas ficam fora do fitness: um app escolar holandês e um app espanhol de concursos.

## 1. Princípios

1. **Os objetivos ficam no centro.** O app existe para cinco objetivos: Hipertrofia, Força, Cardio, Longevidade e Combate. Cada tela responde "para qual objetivo isto serve?" antes de mostrar números.
2. **Calma no lugar de euforia.** Superfícies claras e quentes, pouco movimento, nenhum grito. Descanso e semana leve fazem parte do plano e nunca aparecem como fracasso.
3. **A ciência fica à vista.** Toda sugestão tem um "Por quê?" com autor, ano e nível de evidência. A referência é a autoridade, não um coach motivacional.
4. **Nada de cultura de academia.** Sem preto com neon, cromado, halteres, silhuetas musculosas, raios, chamas, troféus, fontes condensadas em itálico ou linguagem militar.
5. **Autonomia.** O app explica e a pessoa decide. Voz adulta, sem culpa e sem gamificação punitiva: nada de sequências que "quebram" nem de confete.

## 2. O ícone: cinco pétalas, um centro

Arquivos: `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/` com `AppIcon.png` (1024 px, opaco), `AppIcon-dark.png` e `AppIcon-tinted.png`, gerados por `docs/design/render-app-icon.ps1`, que também desenha a folha de conferência `docs/design/candidates/AppIcon-checks.png`. Desde a 2.2 (decisão 18 da SPEC, pedido S10), o desenho é o candidato **6 · Brisa** de `docs/design/icon-v22/` (gerador `render-icon-v22.ps1`, comparação `compare-v22.png`); o `render-app-icon.ps1` passa a usar os parâmetros dele (tarefa `flower` do `docs/V22-CONTRACT.md`).

**O que significa.** Uma flor de cinco pétalas vista de cima, em creme sobre azul-marinho, como papel de linho sobre tinta de caderno. O marinho lembra água funda e céu à noite: calma, profundidade, constância.
- **As 5 pétalas são os 5 objetivos**, do mesmo tamanho e peso: equilíbrio sem hierarquia. A flor inteira é a pessoa inteira. Treinar é o meio, e o fim é florescer, isto é, viver bem, capaz e por muito tempo (eudaimonia, "florescimento humano") [1][2].
- **As pétalas não se tocam.** Cada objetivo tem espaço próprio, e a pessoa escolhe qual cultivar agora; todos saem do mesmo centro.
- **As pétalas têm forma de gota:** estreitas junto ao miolo e abertas para fora, a direção do crescimento.
- **Brisa (2.2):** cada gota nasce de uma espinha levemente curva e todas giram um pouco no mesmo sentido, como uma flor mexida pelo vento. Cada pétala curva e inclina um pouco diferente das outras, com a borda feita à mão. É movimento e vida sem perder a calma: nada de hélice, ventilador ou espiral. As diferenças são números fixos (nada aleatório), e o mesmo desenho vale no ícone e na flor dentro do app.
- **O miolo areia é você:** o ponto quente e firme de onde os objetivos partem. É o único tom diferente da flor.
- **Leitura de índice (Peirce)** [3]: uma flor pede tempo, cuidado, estímulo e repouso, a mesma lógica de estímulo, recuperação e adaptação. É o contrário do metal cromado.
- **Cinco** é o número das flores pentâmeras mais comuns (a simetria radial é o estado ancestral das flores) [4] e ecoa o corpo inteiro (cabeça e quatro membros), sem desenhar figura nem estrela.
- **O que foi evitado de propósito:** pontas, linhas cruzadas e estrela central (pentagrama); círculos em 6 direções (Flor da Vida); lótus de perfil (ioga); entalhe na ponta (sakura); tons rosa e dourado (spa). As pétalas separadas e em gota também afastam o ícone do brasão japonês de círculos que se tocam (umebachi).

**Geometria** (1024 px, Brisa): a flor é centralizada pela caixa envolvente. Cada pétala sai a 70 px do centro e tem comprimento de 252 a 275 px e meia-largura máxima de 95 a 103 px, a cerca de 62% do comprimento. A espinha é uma Bézier cúbica com desvio lateral de até 30% do comprimento na ponta; a inclinação vai de −7° a −14° e a flor inteira gira −5°. O miolo tem raio de 52 px, com um contorno levemente irregular. O menor vão entre pétalas mede 34,1 px (1024 px de referência), o que ainda aparece a 60 px; a distância mínima entre pétala e miolo é 15,9 px. O raio externo é 358 px, dentro do recorte circular do Watch (512 px), e o símbolo (as 5 pétalas) ocupa 651 × 648 px. Não há texto, cantos arredondados nem sombra pintada. Na aparência padrão há só um halo muito leve atrás da flor e um sombreado de volume discreto num flanco de cada pétala; o Liquid Glass fica por conta do sistema (HIG) [5].

**Cores do ícone:** azul-marinho `#2B3F58` → `#1C2B40` (degradê vertical); pétalas `#F1EDE4`, com a base levemente sombreada e as pontas clareando para o branco; miolo `#E9DCC6` (areia).
- Contrastes: pétala contra o fundo, de 9,20:1 (topo) a 12,24:1 (base); miolo contra o fundo, 7,94:1.
- O bloco do ícone contra o papel de parede claro `#F2F2F7` dá 9,63:1. Contra o escuro `#1C1C1E` dá só 1,19:1: o quadrado quase some e quem faz a leitura é a flor creme, o mesmo comportamento dos ícones escuros do sistema.
- Aparência escura: pétalas `#E3DED3` e miolo `#D3C4AB` sobre `#18222F` → `#101822`, com 11,96:1. Aparência tingida: tons de cinza puros (R = G = B) sobre preto, com miolo cinza médio; o iOS aplica a cor escolhida pela pessoa.
- Alternativas testadas e descartadas pelo dono: barro bege (versão 1.0), três musgos, rosácea de pétalas sobrepostas (conceito B) em seis tons de azul, pétalas de cores vivas ou discretas sobre azul profundo e pétalas claras de cores diferentes sobre marinho. Os candidatos estão em `docs/design/candidates/`.

## 3. Paleta

Desde a 2.3, a paleta é a da direção **A · Tinta e papel** (SPEC decisão 20; `docs/design/v23-aesthetics/directions.html`): papel washi quente, tinta sumi em tons de uma tinta só, um índigo (ai) como única cor de ação e pigmentos terrosos para os objetivos. O acento continua um tom acima do marinho do ícone, para o botão parecer tocável e não se confundir com o texto. Contraste WCAG de cada cor contra o fundo e contra a superfície (vale o menor valor), calculado sobre os hexadecimais; AA exige 4,5:1 para texto e 3:1 para gráficos.

| Token | Uso | Claro | Escuro | Contraste mínimo (claro / escuro) |
|---|---|---|---|---|
| `background` | fundo das telas (washi) | `#F4EEE4` | `#191715` | — |
| `surface` | cartões, folhas, listas (papel novo) | `#FCF9F3` | `#25211E` | — |
| `textPrimary` | texto e números (sumi) | `#27221F` | `#EEE7DC` | 13,63 / 13,00 |
| `textSecondary` | legendas, rótulos (tinta diluída) | `#635850` | `#B2A595` | 5,98 / 6,62 |
| `accent` | botão principal, links, seleção, tint global (índigo) | `#2B4D6B` | `#A4BDD6` | 7,66 / 8,23 |
| `onAccent` | texto sobre `accent` | `#FCF9F3` | `#191715` | 8,41 / 9,22 (sobre `accent`) |
| `accentSoft` | fundo de item selecionado, chips (não é texto) | `#DEE5EA` | `#27313B` | texto primário sobre ele: 12,36 / 10,76 |
| `inkMuted` | ícones e traços junto do texto (tinta 2); decorativo | `#4A4139` | `#CFC4B5` | — |
| `line` | fios, divisórias, borda fina dos cartões, trilho do ensō (tinta 5); decorativo, nunca texto | `#DAD1C4` | `#3A332D` | — |
| `goalHypertrophy` | Hipertrofia (terra vermelha, bengara) | `#8E3E2C` | `#E09A82` | 6,33 / 6,93 |
| `goalStrength` | Força (chá torrado) | `#6F5238` | `#CDAA86` | 6,19 / 7,37 |
| `goalEndurance` | Cardio (celadon profundo) | `#3A6765` | `#93C2BE` | 5,50 / 8,14 |
| `goalLongevity` | Longevidade (verde pinheiro) | `#50613F` | `#AFC194` | 5,83 / 8,27 |
| `goalCombat` | Combate (uva acinzentada) | `#6C4862` | `#CFA6C3` | 6,64 / 7,53 |
| `health` | saúde e aeróbico (folha seca) | `#775816` | `#D7B568` | 5,70 / 8,14 |
| `flowerCenter` | miolo da flor (areia); decorativo | `#E7D9C2` | `#CDBEA4` | — |
| `destructive` | apagar, erro | vermelho do sistema | vermelho do sistema | — |

- Os tons `inkMuted` e `line` são decorativos: nunca levam texto que precise ser lido.
- **A cor nunca identifica sozinha:** todo objetivo aparece com nome, símbolo e posição da pétala (HIG).
- Vermelho é só para erro ou ação destrutiva, nunca "cor de esforço" nem meta não cumprida.
- Com Aumentar Contraste ligado, `textSecondary` passa a usar `textPrimary`, cartões ganham borda de 1 pt em `textSecondary` e a fibra do papel some (§14).
- A escolha é por coerência e legibilidade. O efeito emocional das cores tem evidência fraca, então não o usamos como argumento.
- A paleta da 2.2 (bege-linho, acento `#355A7C`) fica registrada no histórico do Git; os nomes dos tokens não mudaram.

## 4. Os objetivos e a flor dentro do app

A mesma flor do ícone é o sistema de identidade. No app, a pétala do objetivo ativo fica preenchida com a cor dele, e as outras ficam em contorno de 1,5 pt em `textSecondary`. Desde a 2.2, a `FlowerView` desenha a geometria Brisa (§2): cada objetivo tem a sua pétala, com a curva e a inclinação dela, na mesma posição do ícone.

| Pétala (horário, a partir do topo) | Objetivo | Subtítulo | SF Symbol* |
|---|---|---|---|
| 1 (topo) | Longevidade | Viver bem por mais tempo | `tree` |
| 2 | Hipertrofia | Ganhar massa muscular | `leaf` |
| 3 | Força | Ficar mais forte | `mountain.2` |
| 4 | Combate | Potência e resistência | `shield` |
| 5 | Cardio | Coração forte e mais condicionamento | `wind` |

O subtítulo do Combate foi decidido pelo dono em 2026-09-27 (SPEC decisão 18): o antigo "Saber se defender" prometia técnica de defesa, que o app não ensina (SPEC §7.9). Na 2.3, "Resistência muscular" virou cardiovascular (SPEC decisão 19), com o símbolo `wind` (o vento da flor Brisa), e o dono deu o nome **Cardio** e o subtítulo "Coração forte e mais condicionamento" (decisão 20; o núcleo usava "Fôlego"). O token de cor e a pétala não mudam.

**Vários planos (2.3):** com dois planos ativos, as duas pétalas ficam cheias, cada uma na cor do seu objetivo; o primeiro de `activeGoals` é o do plano principal (SPEC §7.15 M1), o que cora na abertura.

Com essa ordem, cada par de pétalas vizinhas é uma afinidade real: Longevidade e Hipertrofia (massa muscular contra sarcopenia), Hipertrofia e Força, Força e Combate (potência), Combate e Cardio (condicionamento), Cardio e Longevidade (o VO2máx prediz a longevidade). **A ordem é decisão do dono.** No ícone as pétalas são todas creme; no app, cada uma ganha a cor do seu objetivo (§3). \*Confirmar nomes e disponibilidade no app SF Symbols (iOS 18 / watchOS 11).

## 5. Tipografia (só fontes do sistema, sempre com Dynamic Type)

| Papel | Fonte | SwiftUI | Por quê |
|---|---|---|---|
| Títulos de tela e de seção, cartão de referência | **New York** (serifada) | `.font(.system(.title2, design: .serif))` | Evoca livro e periódico: a ciência fica visível. É o oposto da fonte condensada de academia. |
| Números: carga, repetições, tempo, RIR | **SF Pro Rounded** | `.fontDesign(.rounded).monospacedDigit()` | Suaviza sem perder precisão; os dígitos de largura fixa não "pulam" no cronômetro. |
| Texto corrido, botões, listas | **SF Pro** | padrão (`.body`, `.headline`) | A leitura mais neutra e legível do sistema. |
| Apple Watch | SF Compact (padrão) e Rounded nos números | `.fontDesign(.rounded)` | A tela é pequena; a serifada fica reservada ao iPhone. |

Proibido: fontes condensadas, itálico agressivo, caixa-alta gritada e fontes baixadas.

## 6. Tom de voz (pt-BR)

Trate por "você". Explique o porquê em uma frase e mostre a referência. Use frases curtas e verbos de cuidado, progresso e autonomia.

| Evite | Use |
|---|---|
| treino pesado, treino insano, monstro | sessão de hoje |
| shape, definição, projeto verão, maromba, frango | (não usar; fale de capacidade e de saúde) |
| no pain no gain, sem desculpas, foco total, bora | "Hoje o plano é X. Se algo doer, pare e ajuste." |
| guerreiro, missão, batalha, destruir, esmagar | objetivo, plano, prática contínua |
| falhou, falha (como veredito) | ficou abaixo do alvo / não completou |
| deload | semana leve |
| PR, recorde | melhor marca |
| queimar calorias | gasto de energia |
| você perdeu a sequência | (não usar; mostre só o fato: "1 sessão nesta semana.") |

**Sem mensagens de efeito** (SPEC decisão 20, itens 15 e 16 do dono, 2026-09-28). Nenhuma tela tem citação, frase inspiracional, mensagem estoica ou budista, "mensagem do dia", elogio ou frase de efeito: nem o Início, nem a abertura, nem a sessão, nem o resumo, nem os estados vazios, nem o Ajustes. Os textos dizem o que é e o que fazer, com números quando houver ("Hoje é dia de descanso.", "3 de 4 sessões"). A calma vem do visual (§14), não de frases. Os avisos funcionais do diálogo (SPEC §7.11 C1–C8: semana leve, revisão, saúde, validade da instalação, backup) continuam, porque são recursos.

## 7. Vocabulário da interface

| Hoje no app | Proposta | Motivo |
|---|---|---|
| Aba "Treino" | **Hoje** | Fala do dia e da pessoa, não do esforço. |
| "Iniciar treino" | **Começar** | Verbo simples e convidativo; o contexto já diz o quê. |
| treino (unidade) | **sessão** | Termo neutro da literatura científica ("sessão de treino"). "Prática" soa a ioga e meditação e fica vago; "treino" carrega a cultura de academia. |
| "Treino concluído" | **Sessão concluída** | Mesmo termo em todo o app. |
| Aba "Programa" | **Plano** (2.2) | Objetivo e programa viram uma coisa só: o objetivo, e o plano dele (SPEC RF-45). |
| "Concluir série", seletor de RIR, chave Aquecimento | **bolinha** por série e **Feito** por exercício (2.2) | Marcar o que foi feito é um toque; a ficha é para consultar (SPEC RF-44). |
| "Finalizar" | **Concluir** (2.2) | Verbo de quem terminou, sem cara de ordem. |
| Histórico, Ajustes | mantidos | Já são neutros e claros. |

Selos da nota da prescrição (2.2), só quando há novidade:

| Nota | Selo | Nota | Selo |
|---|---|---|---|
| `calibrate` | **Primeira vez** (antes "Calibrar") | `decrease` | **Carga menor** |
| `increase` | **Carga maior** | `returning` | **Retorno** |
| `hold` | sem selo (antes "Manter") | `deload` | **Semana leve** |
| `retry` | **Tentar de novo** | | |

Outras palavras da 2.2: "Informações do exercício", "Da última vez", "Por que esta carga", "Marcar como feitos, como previsto", "Encerrar só com o que marquei", "Sair sem registrar", "Voltar ao treino", "escolha a carga", "+ 2,5 kg extra", "Trocar" (objetivo), "Ajustar exercícios", "Mais opções".

Palavras da 2.4: "Fora do app", "Registrar atividade", "Atividades fixas", "Acrescentar atividade fixa", "Toda semana", "Também hoje", "Feito", "Apagar atividade", "Duração", "Intensidade", "Leve", "Moderada", "Forte", "Mais um bloco", "1 de 2 vezes", e os nomes dos tipos da SPEC §7.17 ("Pilates", "Cross ou funcional", "Aula de luta"…). A carga vazia diz "sem carga" também na tela Hoje (antes "escolha a carga").

Palavras da 2.3: "Início", "Metas da semana", "Ver a sessão de hoje", "Retomar a sessão", "Ver o dia", "Marcar série", "Marcar como feito", "Concluir a sessão", "Agora: …", "A seguir: …", "sem carga", "Anotar carga", "Agora não", "Como fazer", "Recuperação andando", "Adicionar X ao seu plano", "Tirar este plano", "Sua semana", "Seus dias", "Aceito 2 sessões no mesmo dia", "Cardio leve depois da força", "Treinar mesmo assim", "Ganha", "Fica igual", "Custa", "sem dados". Intensidade do Cardio pelo teste da fala: "Leve: a conversa é fácil", "Moderado: dá para conversar, mas não para cantar", "Forte: só dá para dizer poucas palavras".

Termos técnicos úteis ficam, com explicação no primeiro uso ou no "Por quê?":
- **série**: um bloco de repetições seguidas;
- **repetições**;
- **carga**;
- **semana leve**: redução planejada de volume para recuperar;
- **VO2max**: capacidade aeróbica;
- **HRV**: variabilidade da frequência cardíaca.

**RIR** (repetições em reserva) saiu da interface na 2.2: o app continua usando por dentro, mas a pessoa não vê nem escolhe (SPEC RF-41). Não escrever "RIR", "pare com N sobrando" nem "pare N antes do limite" em nenhuma tela, rótulo ou leitura do VoiceOver. A explicação fica só nas Referências científicas.

## 8. Abas e símbolos

| Aba | Título | SF Symbol | Substitui |
|---|---|---|---|
| landing | Início (2.3; a primeira, aberta no lançamento) | `house` | (nova) |
| today | Hoje | `sun.max` | `figure.strengthtraining.traditional` |
| history | Histórico | `clock.arrow.circlepath` | (mantém) |
| program | Plano (2.2; antes "Programa") | `list.bullet.rectangle` | (mantém) |
| settings | Ajustes | `gearshape` | (mantém) |

- Renderização monocromática ou hierárquica, com o mesmo peso do texto ao lado.
- **Não usar:** `dumbbell`, `figure.strengthtraining.*`, `figure.boxing`, `figure.kickboxing`, `figure.martial.arts`, `flame`, `bolt`, `trophy`.
- Trocas no código atual (tarefa futura):
  - `figure.strengthtraining.traditional` nos estados vazios de Home, Sessão e Catálogo → `sun.max` ou `list.bullet`;
  - `flame` na série de aquecimento → `thermometer.medium`;
  - `target` no cartão do plano → símbolo do objetivo (§4).

## 9. Hoje, Início e Metas da semana: regras

Tela Hoje da 2.2 em `docs/design/v22/mockup.html` ("Hoje"). Critério: a tela responde "o que eu faço hoje?" e nada mais.

1. **No topo, o objetivo ativo, que é um botão:** a flor (cerca de 56 pt) com a pétala do objetivo preenchida, o nome em New York, o subtítulo humano ("Potência e resistência") e a pílula **"Trocar ›"** (`accentSoft` com texto `accent`). O toque abre a folha "Seu objetivo" (SPEC RF-45). Com sessão em andamento, fica desabilitado. Nada fica acima disso.
2. **Logo abaixo, a sessão de hoje:** cartão em `surface` com o rótulo pequeno "Hoje", o nome do dia (menu para escolher outro), "5 exercícios · ≈ 55 min" e a chave "Em casa" na mesma linha. As faixas de motivo (semana leve, frequência) e os avisos do modo casa só aparecem quando existem. Cada exercício é uma linha com número, nome e a meta de hoje em palavras ("3 séries de 3 · 62,5 kg"; peso do corpo sem carga). Não aparecem RIR, descanso, nome do programa nem o selo repetido do objetivo. O único botão proeminente da tela é **Começar**, em `accent`.
3. **Dia de descanso ou semana leve** aparecem no lugar da sessão como parte do plano: "Hoje é dia de descanso." (2.3: sem frase de efeito depois, §6), com "Treinar mesmo assim" quando há dois planos. Nunca em vermelho nem com tom de alerta.
4. **Do diálogo, só a mensagem principal**, com "Ver todas (N)" quando houver mais. **Saúde vem depois** (sono, HRV, VO2max, aeróbico), em cartões discretos com cor `health`. Nunca acima do objetivo. O painel "Esta semana" fica no Histórico (desde a 2.3, nas Metas da semana, §9.2 abaixo).
5. O **"Por quê?"** (referências) fica a um toque de qualquer sugestão. Na linha do exercício, **o próprio selo da nota abre o "Por quê?"** (sem link separado); o selo só aparece quando há novidade (§7). Tocar na linha abre "Informações do exercício" (§13).
6. **Proibido na Home:** anéis concêntricos (a estética do app Fitness), sequências punitivas, confete, fotos ou silhuetas de corpo, números gigantes de calorias.
7. **Dois planos (2.3, SPEC §7.15 M6):** o topo mostra os dois objetivos ("Hipertrofia + Cardio") com a flor de duas pétalas cheias; em cima dos cartões, a linha "Hoje: Superior + Cardio leve 25 min"; um cartão por sessão, a força antes do aeróbico. **Começar** continua o único botão proeminente (a primeira sessão pendente); o segundo cartão tem "Começar esta", menor. Sessão feita hoje vira "✓ Feito hoje" com "A seguir: …". Com um plano só, a tela fica como na 2.2.
8. **Também hoje (2.4, SPEC RF-01, §7.17 X2):** embaixo das sessões (e no lugar delas, no dia de descanso), um cartão de papel com o rótulo pequeno "Também hoje" e uma linha por atividade fixa de hoje ("Pilates · 19h · 50 min"), com "Feito" em `accent` à direita (botão sem fundo, ≥ 44 pt). Depois do toque, a linha vira "✓ Feito", em `textSecondary`. Sem fixa hoje, o cartão não existe. Nunca é o botão proeminente da tela.

### 9.1 Início (2.3, SPEC RF-49)

A primeira aba responde "como eu estou?" antes de "o que eu faço hoje?". É a tela mais vazia do app (ma, §14): o vazio pesa tanto quanto o cheio.
1. De cima para baixo: a aguada de montanha no canto de cima, atrás de tudo (cerca de 55 % da largura e 140 pt de altura); a data em `textSecondary` ("segunda-feira, 28 de setembro"); a flor pintada grande (168 pt), centralizada; a saudação em New York ("Bom dia", "Boa tarde", "Boa noite"); os objetivos ativos em `textSecondary`.
2. "Esta semana": 7 marcas de tinta, de segunda a domingo (cheia nos dias com sessão concluída com ao menos uma série; hoje com um fio fino em volta), e uma frase de fato ("2 sessões nesta semana."). O bloco inteiro é um botão que abre as **Metas da semana** (§9.2), com um "›" discreto.
3. O caminho para hoje, num cartão de papel com o rótulo pequeno "Hoje", o nome da sessão com os textos da tela Hoje (2.4: "Superior + Cardio moderado 30 min"; numa sessão só de aeróbico, "30 min") e o **único botão proeminente**: "Ver a sessão de hoje", "Retomar a sessão", "Ver o dia" ou "Escolher um objetivo". Com uma atividade fixa hoje ainda sem "Feito", uma linha pequena em `textSecondary`: "Também hoje: Pilates às 19h".
4. Sem mensagem, sem diálogo, sem Saúde, sem números grandes, sem anéis. A florzinha da abertura pousa na flor desta tela (§10).

### 9.2 Metas da semana (2.3, SPEC RF-52 e §7.16)

Responde "como está a minha semana?" sem cobrar.
1. Título "Metas da semana" em New York e o intervalo da semana ("22 set. – 28 set.") em `textSecondary`.
2. Uma linha por meta, na ordem de W2: nome, o número em palavras ("3 de 4 sessões", "95 de 150 min", "média de 6.200 por dia", "média de 7 h 20 min"), o "Por quê?" e a **marca de tinta**: um traço de pincel horizontal que se pinta da esquerda para a direita conforme a fração (o mesmo pincel do ensō, §14), em `inkMuted` sobre o trilho `line`; a meta cumprida fica com o traço inteiro e "✓". As sessões de cada plano usam a cor do objetivo dele. A linha de passos só existe com um plano de Longevidade ou de Cardio (SPEC §7.16 W7), e o mesmo vale para os passos do cartão e do detalhe de Saúde.
3. Músculos: a linha dos grupos e, embaixo, os 10 grupos em duas colunas ("Peito 1 de 2"), com um ponto de tinta por vez feita.
4. "sem dados" em `textSecondary`, com o trilho pontilhado, para o que depende do app Saúde e não chegou; no fim, a linha "Aeróbico, passos e sono vêm do app Saúde.". Nunca vermelho, nunca "faltam", nunca porcentagem, nunca anel.
5. **Na 2.4:** o aeróbico soma as atividades fora do app (sem o app Saúde, só elas, com a linha "Aeróbico só das atividades registradas no app."); equilíbrio e mobilidade dizem "1 de 2 vezes"; e, depois das metas, a seção **"Fora do app"** (§9.3).

### 9.3 Atividades fora do app (2.4, SPEC RF-53 e §7.17)

Responde "o que eu fiz fora do app conta?" com o mínimo de toques e nenhuma cobrança.
1. **Seção "Fora do app"** nas Metas da semana: um cartão de papel com uma linha por registro da semana, do mais antigo ao mais novo ("Pilates · terça · 50 min · leve"; o dia em palavras, o nome do tipo em `textPrimary`, o resto em `textSecondary`), tocar abre a edição e deslizar mostra "Apagar" (com confirmação). Sem registros: "Nada registrado nesta semana." Embaixo, o botão sem fundo **"Registrar atividade"** (`plus.circle`, `accent`) e o "Por quê?" do `topic.activities`.
2. **Folha "Registrar atividade"** (e a mesma para editar e para a fixa): título em New York; o tipo em chips de duas colunas, na ordem da tabela X1 (o tocado com borda `accent`); "Duração" com um stepper de 5 em 5 min (5 a 300), já com a duração sugerida do tipo; "Intensidade" em três opções empilhadas, cada uma com a frase do teste da fala ("Leve: a conversa é fácil", "Moderada: dá para conversar, mas não para cantar", "Forte: só dá para dizer poucas palavras"), já na sugerida do tipo; "Quando" com dia e hora (padrão: agora menos a duração, arredondado a 5 min); a chave **"Toda semana"**, que transforma o registro numa fixa daquele dia da semana e hora; e o botão principal "Registrar" (ou "Salvar"). Sem campos de texto livre, sem FC, sem calorias.
3. **"Atividades fixas"** na aba Plano, depois dos planos: uma linha por fixa ("Pilates · terça · 19h · 50 min"), tocar edita, deslizar apaga (com confirmação, avisando que os registros já feitos ficam); embaixo, "Acrescentar atividade fixa". Até 10.
4. **"Também hoje"** na tela Hoje (§9, item 8) e a linha "Também hoje: …" do Início (§9.1).
5. **Na semana da aba Plano** (dois planos), a fixa aparece no dia dela, depois das sessões ("Ter · Dia B — Inferior + Pilates"), sem cor de objetivo.
6. Sem ícones por tipo (nenhum `figure.*`, §8), sem selos de conquista, sem contagem de "dias seguidos". Os textos dizem o fato (§6).

## 10. Movimento e retorno

- Animações lentas (0,4 a 0,6 s, `easeInOut`): a pétala se enche ao concluir a sessão. A flor pode crescer de 0,5× a 1× na abertura ou na tela de progresso, como índice de adaptação gradual.
- Vibração leve (`.sensoryFeedback(.success)`) ao concluir uma série. Nada de fogos por "melhor marca". Vibrar quer dizer "feito": por isso a abertura não vibra.
- Respeitar Reduzir Movimento: trocar crescimento por esmaecimento.
- **Abertura (2.3, SPEC RF-50):** a tela de lançamento é o azul-marinho do ícone com a flor Brisa no centro; no primeiro quadro, a flor respira, gira 10° e desabrocha pétala por pétala enquanto o azul amanhece até o papel, com o véu de areia (não no escuro), a pétala do objetivo principal corando e saindo por último e um **pólen discreto** (8 grãos de números fixos, creme, saindo do miolo). Total 0,92 s; com Reduzir Movimento, só esmaecimentos em 0,60 s, sem pólen. Nunca bloqueia o toque, só roda a frio e não vibra. Os números são os do protótipo aprovado, `docs/design/v23-animation/launch.html`.
- **Descanso em ensō (2.3):** o traço de pincel se pinta conforme o descanso passa, no ritmo de 1 s; sem pulsar, sem piscar.

## 11. Incertezas e decisões do dono

- **Ícone sem Mac:** o caminho é o catálogo de imagens com PNG de 1024 px mais as aparências escura e tingida (suportadas desde o iOS 18; `appearances` → `luminosity` `dark`/`tinted` no `Contents.json`). Para a aparência escura, a Apple sugere fundo transparente; a entregue é opaca, e só o CI (`actool`) e o aparelho confirmam como fica. Cores não foram testadas em tela P3 com True Tone. Não foi feita busca por ícones parecidos na App Store.
- **Decisões do dono ainda abertas:** a ordem das pétalas (§4). Já decididos: nome (Magister), ícone (pétalas creme sobre azul-marinho, 2026-09-23), desenho Brisa e subtítulo do Combate "Potência e resistência", mantendo o nome "Combate" (2026-09-27, SPEC decisão 18).
- **Brisa sem Mac:** a geometria da `FlowerView` é portada do gerador em PowerShell; só o CI e o aparelho confirmam que as duas coincidem a 56 pt.
- **Tinta e papel sem Mac (2.3):** a textura de papel, a flor em aguada, o ensō e a aguada de montanha são desenhados em `Canvas` a partir dos mesmos números das folhas de conferência (`docs/design/v23-ink/`); só o aparelho confirma a textura com True Tone, a leitura da aguada a 26 pt e a abertura a 120 Hz.

## 12. Ilustrações de exercício ("Como fazer", SPEC RF-40 e §7.12)

Aprovado pelo dono em 2026-09-24 (protótipo v2 em `docs/design/exercise-guides/compare-v2.png` e `compare-v2-dark.png`).

- **A figura:** manequim liso, sem músculos, rosto ou roupa marcada.
  - As partes que se movem ficam em `accent`; o resto do corpo, em `accent` misturado ao fundo.
  - Os membros do lado de lá ficam mais claros que os do lado de cá.
  - O que se move tem contraste ≥ 3:1.
- **Equipamento:**
  - o que se move (barra, anilhas, halter, puxador, cabo) usa `textSecondary`;
  - a estrutura fixa (banco, torre, assento) fica mais clara, como fundo.
- **Sinais de leitura:**
  - seta sólida na cor de texto principal, mostrando o caminho da ida;
  - posição inicial em fantasma tracejado no quadro final;
  - legenda numerada curta sob cada quadro;
  - "Trabalha: …" sob o nome.
- **Exceção ao "sem halteres" do §1.4:** equipamento aparece só dentro da folha Como fazer, nunca em ícones, estados vazios, abas ou na Home. A figura também nunca aparece na Home (§9.6), só na folha.
- **Exceção ao §10:** a demonstração segue o ritmo do exercício (fases de 0,8 a 3 s, padrão de 1,5 s, `easeInOut`, pausas de 0,4 s) e tem botão Pausar. Com Reduzir Movimento, os quadros ficam parados lado a lado.

## 13. Sessão, informações e objetivo (versões 2.2 e 2.3)

Telas de referência em `docs/design/v22/mockup.html`; regras em SPEC RF-44 a RF-47.

**A ficha da sessão** responde "o que eu faço agora?" e se lê de relance entre as séries, como a folha de papel de um treinador.
- Paleta do §3 também na sessão: fundo `background`, cartões `surface`, tint `accent`. A sessão abre em `fullScreenCover`, fora do tint da raiz, então quem monta a sessão aplica tint e fundo (antes aparecia preto com o azul do sistema, o que o §1.4 proíbe).
- Uma lista rolável com todos os exercícios. Cada cartão: número e nome em SF Pro semibold, selo da nota só com novidade; a meta de hoje em **SF Rounded** grande ("3 repetições · 62,5 kg"), com a carga sublinhada em `accent` quando dá para tocar nela; as bolinhas, uma por série (desenho de 32 pt, alvo de toque de 44 pt; cheia = `accent` com o número feito em `onAccent`); a pílula "✓ Feito"; e a linha pequena em `textSecondary` ("3 séries · descanso 4 min").
- O exercício atual tem borda de 1,5 pt em `accent`. Feito vira uma linha compacta sem fundo ("✓ 5, 5, 4 · 60 kg"). Pulado fica esmaecido com "Pulado", nunca em vermelho.
- O descanso fica preso no topo sem empurrar a lista: anel de 48 pt, "Descanso", "A seguir: …", "+30 s" e "Pular".
- Linha fixa no topo: "Aqueça com 1 ou 2 séries leves antes dos exercícios com carga. Não precisa marcar."
- Primeira vez com carga: a dica numa caixa em `background` e o campo de carga com o teclado numérico; bolinhas e "Feito" em cinza até haver carga.
- "Concluir" na barra, em semibold. O diálogo de pendentes só aparece quando falta algo.
- Sem chips, steppers, seletor de RIR, chave de aquecimento, "Série X de Y" nem botão vermelho na tela principal. A correção de uma série é uma folha pequena só com carga, repetições e "Apagar série".
- Vibração leve ao marcar uma série (`.sensoryFeedback(.success)`, §10). A tela fica acesa só enquanto a ficha está aberta.

**Informações do exercício** é leitura, não formulário: título em New York, seções em `surface` ("Hoje", "Por que esta carga", "Da última vez", notas da máquina) e, na sessão, as ações "Máquina ocupada? Trocar por outro parecido" e "Pular este exercício" em `accent`. Nada de RIR.

**Seu objetivo** é uma folha só para trocar de objetivo e para o primeiro uso: a flor grande, os 5 objetivos na ordem das pétalas (flor pequena com a pétala dele, nome, subtítulo, dias), o tocado com borda `accent`, o formato em chips (só na Hipertrofia), a prévia do Dia A em `textSecondary`, a frase sobre as cargas e um botão principal que diz o que vai acontecer ("Trocar para Hipertrofia").

**Sessão concluída** usa a flor do objetivo (a pétala se enche devagar, §10), duração, "Exercícios 5 de 5", séries, FC quando houver e "A próxima sessão já está pronta: Dia B". Sem tonelagem, sem verde nem laranja do sistema.

**Na 2.4** (SPEC RF-44 j, RF-46, RF-47, §7.14 F5 a F7; decisão 21):
- O cartão do exercício que acabou de ser concluído **continua aberto** até a pessoa marcar outro exercício: corrigir uma série é um toque na bolinha.
- A carga digitada vale até o fim da sessão, mesmo depois de "Voltar".
- A tela Hoje também diz **"sem carga"**.
- Nos intervalos do Cardio, o selo da nota `increase` diz **"Mais um bloco"**, e a folha de informações explica que cada bloco sobe 1 min por sessão até o topo e que depois entra mais um bloco, até 5.
- **Histórico:** a evolução de um exercício sem carga mostra as repetições (ou a medida), sem "0 kg" nem 1RM; a sessão encerrada sem nenhuma série não aparece; e o detalhe de uma sessão de aeróbico mostra, quando o relógio gravou FC, o tempo em cada intensidade ("Leve 6 min · Moderada 22 min · Forte 12 min", em `textSecondary`, numa barra de tinta fina dividida em três tons de `health`, sem vermelho) e o último VO2máx com a faixa. Só leitura, sem conselho.
- **Trocar em modo casa:** a folha sem opções diz "Nenhuma opção de casa parecida com este exercício.".

**Na 2.3** (SPEC RF-44 c e i, RF-46, RF-47, §7.14; SPEC decisão 20):
- **Sessão guiada:** um botão grande preso embaixo (56 pt, `accent`) guia a sessão: "Marcar série", "Marcar como feito" ou "Concluir a sessão". Acima dele, uma linha: "Agora: Agachamento livre · série 2 de 3" e a meta de hoje em SF Rounded. Durante o descanso, "A seguir: série 3". A lista de cartões continua em cima, para consultar; bolinhas, "Feito", carga, Trocar e Pular continuam nos cartões, como caminho secundário.
- **Sem carga:** num exercício com equipamento e carga 0 ou vazia, o cartão mostra "sem carga" em `textSecondary`, sublinhado em `accent` porque se toca. Sai a caixa "Escolha uma carga…" que bloqueava. A sugestão delicada aparece uma vez na vida de cada exercício, embaixo do cartão, em `textSecondary`: "Anotar a carga ajuda a sugerir quando subir." com "Anotar carga" e "Agora não", sem ícone de alerta.
- **Cardio na ficha:** "30 min" ou "4 × 3 min" em SF Rounded; no lugar da carga, a frase do teste da fala; "sem nível" quando a máquina tem nível e ninguém pôs; nos intervalos, "Recuperação andando" e a linha fixa "Antes, aqueça 10 minutos andando devagar.". Nada de FC, zonas ou ritmo.
- **Como fazer:** o botão "Como fazer" (`play.circle`, `accent`) ao lado do nome, só quando há guia; a folha segue o §12, com o fundo de papel.
- **Descanso:** o anel de 48 pt vira o ensō (§14), com o tempo no centro.
- **Papel:** `paperBackground()` na ficha, no resumo e nas folhas; `inkCard()` nos cartões. O resumo continua sem citação nem elogio (§6).

**Seu objetivo na 2.3** (SPEC RF-45, §7.15 M7 e M8): com um plano ativo e outro objetivo tocado, dois botões: "Trocar para X" e "Adicionar X ao seu plano". Adicionar abre três páginas curtas: "O que muda" (os grupos "Ganha", "Fica igual" e "Custa", cada item com "Por quê?"), "Seus dias" (chips de segunda a domingo e as duas chaves) e "Sua semana" (os 7 dias, com o que cabe em cada um e "descanso" nos livres, ou o motivo e as saídas, cada uma com a semana que resulta e "Escolher esta"). Na aba Plano, cada plano ativo aparece com a flor pequena, o nome e a semana dele; com dois, "Sua semana", "Seus dias" e "Tirar este plano".

## 14. Tinta e papel (direção A, 2.3)

Escolhida pelo dono em 2026-09-28 (SPEC decisão 20; `docs/design/v23-aesthetics/directions.html`, direção A). O app vira um caderno de caligrafia: papel washi, tinta sumi em tons de uma tinta só e um único índigo. A beleza vem do pincel e do vazio. **Só o visual muda:** nenhuma frase estoica, budista ou de efeito entra no app (§6).

- **Ma (o vazio):** mais espaço livre em volta do que importa, sobretudo no Início. Um cartão por assunto; nada de grades cheias.
- **Papel:** `paperBackground()` = `background` com a fibra de washi (`PaperFiber`, PNG de 256 px ladrilhável, gerado por script com semente fixa) a 4 %, só no fundo, por baixo das áreas seguras. Some com Aumentar Contraste. Cartões com `inkCard()`: `surface`, canto contínuo de 16 pt e fio de 0,5 pt em `line` (1 pt em `textSecondary` com Aumentar Contraste). Sem sombra.
- **Tinta:** os tons de uma tinta só (gosai) vão do texto (`textPrimary`) aos traços (`inkMuted`), às legendas (`textSecondary`) e aos fios (`line`). A cor fica nas pétalas dos objetivos e no índigo da ação.
- **Flor em aguada:** as pétalas fora dos objetivos são uma lavagem de tinta a 7 % com contorno fino no tom das legendas; a pétala de cada objetivo ativo é pigmento, mais escuro na base e mais claro na ponta (nōtan); o miolo é areia. A partir de 120 pt, uma borda de tinta levemente mais escura dá o "pintado". Sem desfoque, sem textura animada; tudo determinístico, a mesma flor de 26 a 168 pt.
- **Ensō:** um traço de pincel aberto (vão de cerca de 30°), que começa mais grosso e afina, pintado de 0 até o progresso; o trilho em `line`; o fim do traço em "branco voador" (3 fios finos com falhas fixas). É o descanso da ficha e o pincel das marcas das Metas da semana.
- **Aguada de montanha:** duas silhuetas em curvas, em `textPrimary` a 7 % e 4 %, com a base esmaecendo; parada; só no canto de cima do Início.
- **Letras:** as do §5, sem fonte baixada. SF Symbols em peso leve, para acompanhar o traço fino.
- **Proibido nesta direção:** lótus, Buda decorativo, caracteres japoneses ou chineses como enfeite, dourado, confete, anéis concêntricos, e qualquer texto de sabedoria ou motivação.

## Fontes

1. VanderWeele, T. J. (2017). On the promotion of human flourishing. *PNAS*. https://www.pnas.org/doi/10.1073/pnas.1702996114
2. Aristóteles, ética e eudaimonia (Stanford Encyclopedia of Philosophy). https://plato.stanford.edu/entries/aristotle-ethics/
3. Peirce, teoria dos signos: ícone, índice e símbolo (SEP). https://plato.stanford.edu/entries/peirce-semiotics/
4. Evolução da simetria floral, revisão (PMC). https://pmc.ncbi.nlm.nih.gov/articles/PMC9472818/
5. Apple Human Interface Guidelines, App icons. https://developer.apple.com/design/human-interface-guidelines/app-icons
