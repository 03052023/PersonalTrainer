# Guia de design: Magister

Versão 1.2 · 2026-09-23. Vale para iPhone e Apple Watch. Decisões do dono registradas na SPEC (decisões 15 e 16): nome **Magister**, ícone de cinco pétalas creme separadas com miolo areia sobre **azul-marinho**, nada de cultura de academia.

## 0. O nome

**Magister** é latim para "mestre, quem ensina e guia" (a raiz de "magistério" e de *master*). É o papel de um personal trainer sem o vocabulário de academia: alguém que conhece o caminho, explica o porquê e acompanha a pessoa. Uma palavra só, curta, séria e amigável, que funciona em pt-BR, espanhol, italiano e inglês. Na tela aparece só "Magister". Se um dia for publicado, o título na loja pode ser "Magister: Personal Trainer". Colisões conhecidas ficam fora do fitness: um app escolar holandês e um app espanhol de concursos.

## 1. Princípios

1. **Os objetivos ficam no centro.** O app existe para cinco objetivos: Hipertrofia, Força, Resistência muscular, Longevidade e Combate. Cada tela responde "para qual objetivo isto serve?" antes de mostrar números.
2. **Calma no lugar de euforia.** Superfícies claras e quentes, pouco movimento, nenhum grito. Descanso e semana leve fazem parte do plano e nunca aparecem como fracasso.
3. **A ciência fica à vista.** Toda sugestão tem um "Por quê?" com autor, ano e nível de evidência. A referência é a autoridade, não um coach motivacional.
4. **Nada de cultura de academia.** Sem preto com neon, cromado, halteres, silhuetas musculosas, raios, chamas, troféus, fontes condensadas em itálico ou linguagem militar.
5. **Autonomia.** O app explica e a pessoa decide. Voz adulta, sem culpa e sem gamificação punitiva: nada de sequências que "quebram" nem de confete.

## 2. O ícone: cinco pétalas, um centro

Arquivos: `PersonalTrainer/Resources/Assets.xcassets/AppIcon.appiconset/` com `AppIcon.png` (1024 px, opaco), `AppIcon-dark.png` e `AppIcon-tinted.png`, gerados por `docs/design/render-app-icon.ps1`, que também desenha a folha de conferência `docs/design/candidates/AppIcon-checks.png`.

**O que significa.** Uma flor de cinco pétalas vista de cima, em creme sobre azul-marinho, como papel de linho sobre tinta de caderno. O marinho lembra água funda e céu à noite: calma, profundidade, constância.
- **As 5 pétalas são os 5 objetivos**, todas iguais: equilíbrio sem hierarquia. A flor inteira é a pessoa inteira. Treinar é o meio, e o fim é florescer, isto é, viver bem, capaz e por muito tempo (eudaimonia, "florescimento humano") [1][2].
- **As pétalas não se tocam.** Cada objetivo tem espaço próprio, e a pessoa escolhe qual cultivar agora; todos saem do mesmo centro.
- **As pétalas têm forma de gota:** estreitas junto ao miolo e abertas para fora, a direção do crescimento.
- **O miolo areia é você:** o ponto quente e firme de onde os objetivos partem. É o único tom diferente da flor.
- **Leitura de índice (Peirce)** [3]: uma flor pede tempo, cuidado, estímulo e repouso, a mesma lógica de estímulo, recuperação e adaptação. É o contrário do metal cromado.
- **Cinco** é o número das flores pentâmeras mais comuns (a simetria radial é o estado ancestral das flores) [4] e ecoa o corpo inteiro (cabeça e quatro membros), sem desenhar figura nem estrela.
- **O que foi evitado de propósito:** pontas, linhas cruzadas e estrela central (pentagrama); círculos em 6 direções (Flor da Vida); lótus de perfil (ioga); entalhe na ponta (sakura); tons rosa e dourado (spa). As pétalas separadas e em gota também afastam o ícone do brasão japonês de círculos que se tocam (umebachi).

**Geometria** (1024 px): centro da flor em (512; 534,4), escolhido para centralizar a caixa envolvente da flor. Cada pétala é uma gota que vai de 68 px a 338 px do centro, com largura máxima de 196 px a 66% do comprimento. O miolo tem raio de 52 px. O símbolo mede 653 × 631 px (64% × 62% do lado) e cabe no recorte circular do Watch (raio externo de 338 px, contra 512 px do recorte). Não há texto, cantos arredondados nem sombra pintada. Na aparência padrão há só um halo muito leve atrás da flor; o Liquid Glass fica por conta do sistema (HIG) [5].

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

A mesma flor do ícone é o sistema de identidade. No app, a pétala do objetivo ativo fica preenchida com a cor dele, e as outras ficam em contorno de 1,5 pt em `textSecondary`.

| Pétala (horário, a partir do topo) | Objetivo | Subtítulo | SF Symbol* |
|---|---|---|---|
| 1 (topo) | Longevidade | Viver bem por mais tempo | `tree` |
| 2 | Hipertrofia | Ganhar massa muscular | `leaf` |
| 3 | Força | Ficar mais forte | `mountain.2` |
| 4 | Combate | Saber se defender | `shield` |
| 5 | Resistência muscular | Aguentar mais | `repeat` |

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
| Histórico, Programa, Ajustes | mantidos | Já são neutros e claros. |

Termos técnicos úteis ficam, com explicação no primeiro uso ou no "Por quê?":
- **série**: um bloco de repetições seguidas;
- **repetições**;
- **RIR**: repetições em reserva, isto é, quantas você ainda conseguiria fazer. "RIR 0" substitui "até a falha";
- **carga**;
- **semana leve**: redução planejada de volume para recuperar;
- **VO2max**: capacidade aeróbica;
- **HRV**: variabilidade da frequência cardíaca.

## 8. Abas e símbolos

| Aba | Título | SF Symbol | Substitui |
|---|---|---|---|
| today | Hoje | `sun.max` | `figure.strengthtraining.traditional` |
| history | Histórico | `clock.arrow.circlepath` | (mantém) |
| program | Programa | `list.bullet.rectangle` | (mantém) |
| settings | Ajustes | `gearshape` | (mantém) |

- Renderização monocromática ou hierárquica, com o mesmo peso do texto ao lado.
- **Não usar:** `dumbbell`, `figure.strengthtraining.*`, `figure.boxing`, `figure.kickboxing`, `figure.martial.arts`, `flame`, `bolt`, `trophy`.
- Trocas no código atual (tarefa futura):
  - `figure.strengthtraining.traditional` nos estados vazios de Home, Sessão e Catálogo → `sun.max` ou `list.bullet`;
  - `flame` na série de aquecimento → `thermometer.medium`;
  - `target` no cartão do plano → símbolo do objetivo (§4).

## 9. Home: regras

1. **No topo, o objetivo ativo:** a flor (cerca de 56 pt) com a pétala do objetivo preenchida, o nome em New York e o subtítulo humano ("Ficar mais forte"). Nada fica acima disso.
2. **Logo abaixo, a sessão de hoje:** cartão em `surface` com o nome do dia, o número de exercícios e a duração estimada. O único botão proeminente da tela é **Começar**, em `accent`.
3. **Dia de descanso ou semana leve** aparecem no lugar da sessão como parte do plano: "Hoje é dia de descanso. Recuperar também faz você progredir." Nunca em vermelho nem com tom de alerta.
4. **Saúde vem depois** (sono, HRV, VO2max, aeróbico), em cartões discretos com cor `health`. Nunca acima do objetivo.
5. O **"Por quê?"** (referências) fica a um toque de qualquer sugestão.
6. **Proibido na Home:** anéis concêntricos (a estética do app Fitness), sequências punitivas, confete, fotos ou silhuetas de corpo, números gigantes de calorias.

## 10. Movimento e retorno

- Animações lentas (0,4 a 0,6 s, `easeInOut`): a pétala se enche ao concluir a sessão. A flor pode crescer de 0,5× a 1× na abertura ou na tela de progresso, como índice de adaptação gradual.
- Vibração leve (`.sensoryFeedback(.success)`) ao concluir uma série. Nada de fogos por "melhor marca".
- Respeitar Reduzir Movimento: trocar crescimento por esmaecimento.

## 11. Incertezas e decisões do dono

- **Ícone sem Mac:** o caminho é o catálogo de imagens com PNG de 1024 px mais as aparências escura e tingida (suportadas desde o iOS 18; `appearances` → `luminosity` `dark`/`tinted` no `Contents.json`). Para a aparência escura, a Apple sugere fundo transparente; a entregue é opaca, e só o CI (`actool`) e o aparelho confirmam como fica. Cores não foram testadas em tela P3 com True Tone. Não foi feita busca por ícones parecidos na App Store.
- **Decisões do dono ainda abertas:** a ordem das pétalas (§4); manter "Combate" ou trocar por "Autodefesa" (exige registro na SPEC). Nome (Magister) e ícone (pétalas creme sobre azul-marinho, 2026-09-23) já decididos.

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

## Fontes

1. VanderWeele, T. J. (2017). On the promotion of human flourishing. *PNAS*. https://www.pnas.org/doi/10.1073/pnas.1702996114
2. Aristóteles, ética e eudaimonia (Stanford Encyclopedia of Philosophy). https://plato.stanford.edu/entries/aristotle-ethics/
3. Peirce, teoria dos signos: ícone, índice e símbolo (SEP). https://plato.stanford.edu/entries/peirce-semiotics/
4. Evolução da simetria floral, revisão (PMC). https://pmc.ncbi.nlm.nih.gov/articles/PMC9472818/
5. Apple Human Interface Guidelines, App icons. https://developer.apple.com/design/human-interface-guidelines/app-icons
