# Guia de design: Magister

Versão 1.3 · 2026-09-27. Vale para iPhone e Apple Watch. Decisões do dono registradas na SPEC (decisões 15, 16 e 18): nome **Magister**, ícone de cinco pétalas creme separadas com miolo areia sobre **azul-marinho**, desde a 2.2 no desenho **Brisa** (pétalas com giro leve e feitas à mão), nada de cultura de academia, e uma interface simples: cada tela responde a uma pergunta.

## 0. O nome

**Magister** é latim para "mestre, quem ensina e guia" (a raiz de "magistério" e de *master*). É o papel de um personal trainer sem o vocabulário de academia: alguém que conhece o caminho, explica o porquê e acompanha a pessoa. Uma palavra só, curta, séria e amigável, que funciona em pt-BR, espanhol, italiano e inglês. Na tela aparece só "Magister". Se um dia for publicado, o título na loja pode ser "Magister: Personal Trainer". Colisões conhecidas ficam fora do fitness: um app escolar holandês e um app espanhol de concursos.

## 1. Princípios

1. **Os objetivos ficam no centro.** O app existe para cinco objetivos: Hipertrofia, Força, Resistência muscular, Longevidade e Combate. Cada tela responde "para qual objetivo isto serve?" antes de mostrar números.
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

Superfícies claras e quentes (bege-linho); um azul da família do ícone é a cor de ação; tons terrosos identificam os objetivos. O acento fica um tom acima do marinho do ícone (`#355A7C`, não `#2B3F58`). O marinho puro ficaria escuro demais e se confundiria com o texto marrom-escuro, e o botão deixaria de parecer tocável. Contraste WCAG de cada cor contra o fundo e contra a superfície (vale o menor valor); AA exige 4,5:1 para texto e 3:1 para gráficos.

| Token | Uso | Claro | Escuro | Contraste mínimo (claro / escuro) |
|---|---|---|---|---|
| `background` | fundo das telas | `#F2EBE0` | `#1C1714` | — |
| `surface` | cartões, folhas, listas | `#FAF6F0` | `#29221C` | — |
| `textPrimary` | texto e números | `#33281F` | `#F0E7DA` | 12,11 / 12,80 |
| `textSecondary` | legendas, rótulos | `#6B5A4C` | `#BCAB98` | 5,56 / 7,03 |
| `accent` | botão principal, links, seleção, tint global (AccentColor) — azul profundo | `#355A7C` | `#9DBAD6` | 6,11 / 7,78 |
| `onAccent` | texto sobre `accent` | `#FAF6F0` | `#1C1714` | 6,71 / 8,82 |
| `accentSoft` | fundo de item selecionado, chips (não é texto) | `#DDE5EC` | `#26323E` | texto primário sobre ele: 11,27 / 10,66 |
| `goalHypertrophy` | Hipertrofia (terracota) | `#904C36` | `#E0927A` | 5,42 / 6,39 |
| `goalStrength` | Força (argila) | `#7A583C` | `#C9A27F` | 5,39 / 6,69 |
| `goalEndurance` | Resistência muscular (ardósia) | `#4F6170` | `#9FB2C2` | 5,41 / 7,18 |
| `goalLongevity` | Longevidade (sálvia) | `#56654A` | `#A9B98F` | 5,28 / 7,48 |
| `goalCombat` | Combate (ameixa) | `#74506A` | `#C9A0BC` | 5,72 / 6,89 |
| `health` | saúde e aeróbico (ocre) | `#7A5B1A` | `#D4B062` | 5,31 / 7,60 |
| `destructive` | apagar, erro | vermelho do sistema | vermelho do sistema | — |

- As cores de objetivo e o acento sobre `accentSoft` também passam AA: no claro, o menor valor é 5,03:1 (Resistência); no escuro, 5,32:1 (Hipertrofia).
- **A cor nunca identifica sozinha:** todo objetivo aparece com nome, símbolo e posição da pétala (HIG).
- Vermelho é só para erro ou ação destrutiva, nunca "cor de esforço".
- Com Aumentar Contraste ligado, `textSecondary` passa a usar `textPrimary` e cartões ganham borda de 1 pt em `textSecondary`.
- A escolha é por coerência e legibilidade. O efeito emocional das cores tem evidência fraca, então não o usamos como argumento.

## 4. Os objetivos e a flor dentro do app

A mesma flor do ícone é o sistema de identidade. No app, a pétala do objetivo ativo fica preenchida com a cor dele, e as outras ficam em contorno de 1,5 pt em `textSecondary`. Desde a 2.2, a `FlowerView` desenha a geometria Brisa (§2): cada objetivo tem a sua pétala, com a curva e a inclinação dela, na mesma posição do ícone.

| Pétala (horário, a partir do topo) | Objetivo | Subtítulo | SF Symbol* |
|---|---|---|---|
| 1 (topo) | Longevidade | Viver bem por mais tempo | `tree` |
| 2 | Hipertrofia | Ganhar massa muscular | `leaf` |
| 3 | Força | Ficar mais forte | `mountain.2` |
| 4 | Combate | Potência e resistência | `shield` |
| 5 | Resistência muscular | Aguentar mais | `repeat` |

O subtítulo do Combate foi decidido pelo dono em 2026-09-27 (SPEC decisão 18): o antigo "Saber se defender" prometia técnica de defesa, que o app não ensina (SPEC §7.9).

Com essa ordem, cada par de pétalas vizinhas é uma afinidade real: Longevidade e Hipertrofia (massa muscular contra sarcopenia), Hipertrofia e Força, Força e Combate (potência), Combate e Resistência (condicionamento), Resistência e Longevidade. **A ordem é decisão do dono.** No ícone as pétalas são todas creme; no app, cada uma ganha a cor do seu objetivo (§3). \*Confirmar nomes e disponibilidade no app SF Symbols (iOS 18 / watchOS 11).

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
| você perdeu a sequência | "Voltar também é progresso." |

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

## 9. Home: regras

Tela Hoje da 2.2 em `docs/design/v22/mockup.html` ("Hoje"). Critério: a tela responde "o que eu faço hoje?" e nada mais.

1. **No topo, o objetivo ativo, que é um botão:** a flor (cerca de 56 pt) com a pétala do objetivo preenchida, o nome em New York, o subtítulo humano ("Potência e resistência") e a pílula **"Trocar ›"** (`accentSoft` com texto `accent`). O toque abre a folha "Seu objetivo" (SPEC RF-45). Com sessão em andamento, fica desabilitado. Nada fica acima disso.
2. **Logo abaixo, a sessão de hoje:** cartão em `surface` com o rótulo pequeno "Hoje", o nome do dia (menu para escolher outro), "5 exercícios · ≈ 55 min" e a chave "Em casa" na mesma linha. As faixas de motivo (semana leve, frequência) e os avisos do modo casa só aparecem quando existem. Cada exercício é uma linha com número, nome e a meta de hoje em palavras ("3 séries de 3 · 62,5 kg"; peso do corpo sem carga). Não aparecem RIR, descanso, nome do programa nem o selo repetido do objetivo. O único botão proeminente da tela é **Começar**, em `accent`.
3. **Dia de descanso ou semana leve** aparecem no lugar da sessão como parte do plano: "Hoje é dia de descanso. Recuperar também faz você progredir." Nunca em vermelho nem com tom de alerta.
4. **Do diálogo, só a mensagem principal**, com "Ver todas (N)" quando houver mais. **Saúde vem depois** (sono, HRV, VO2max, aeróbico), em cartões discretos com cor `health`. Nunca acima do objetivo. O painel "Esta semana" fica no Histórico.
5. O **"Por quê?"** (referências) fica a um toque de qualquer sugestão. Na linha do exercício, **o próprio selo da nota abre o "Por quê?"** (sem link separado); o selo só aparece quando há novidade (§7). Tocar na linha abre "Informações do exercício" (§13).
6. **Proibido na Home:** anéis concêntricos (a estética do app Fitness), sequências punitivas, confete, fotos ou silhuetas de corpo, números gigantes de calorias.

## 10. Movimento e retorno

- Animações lentas (0,4 a 0,6 s, `easeInOut`): a pétala se enche ao concluir a sessão. A flor pode crescer de 0,5× a 1× na abertura ou na tela de progresso, como índice de adaptação gradual.
- Vibração leve (`.sensoryFeedback(.success)`) ao concluir uma série. Nada de fogos por "melhor marca".
- Respeitar Reduzir Movimento: trocar crescimento por esmaecimento.

## 11. Incertezas e decisões do dono

- **Ícone sem Mac:** o caminho é o catálogo de imagens com PNG de 1024 px mais as aparências escura e tingida (suportadas desde o iOS 18; `appearances` → `luminosity` `dark`/`tinted` no `Contents.json`). Para a aparência escura, a Apple sugere fundo transparente; a entregue é opaca, e só o CI (`actool`) e o aparelho confirmam como fica. Cores não foram testadas em tela P3 com True Tone. Não foi feita busca por ícones parecidos na App Store.
- **Decisões do dono ainda abertas:** a ordem das pétalas (§4). Já decididos: nome (Magister), ícone (pétalas creme sobre azul-marinho, 2026-09-23), desenho Brisa e subtítulo do Combate "Potência e resistência", mantendo o nome "Combate" (2026-09-27, SPEC decisão 18).
- **Brisa sem Mac:** a geometria da `FlowerView` é portada do gerador em PowerShell; só o CI e o aparelho confirmam que as duas coincidem a 56 pt.

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

## 13. Sessão, informações e objetivo (versão 2.2)

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

## Fontes

1. VanderWeele, T. J. (2017). On the promotion of human flourishing. *PNAS*. https://www.pnas.org/doi/10.1073/pnas.1702996114
2. Aristóteles, ética e eudaimonia (Stanford Encyclopedia of Philosophy). https://plato.stanford.edu/entries/aristotle-ethics/
3. Peirce, teoria dos signos: ícone, índice e símbolo (SEP). https://plato.stanford.edu/entries/peirce-semiotics/
4. Evolução da simetria floral, revisão (PMC). https://pmc.ncbi.nlm.nih.gov/articles/PMC9472818/
5. Apple Human Interface Guidelines, App icons. https://developer.apple.com/design/human-interface-guidelines/app-icons
