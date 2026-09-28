# Como desenhar um lote do "Como fazer"

Guia prático para quem escreve um `batch-<id>.json` (docs/V23-CORE-CONTRACT.md §4). O formato e as regras estão em §2.5 do contrato; aqui ficam os atalhos que evitam as reprovações mais comuns.

## 1. O ciclo de trabalho

Rode tudo nesta pasta (`docs/design/exercise-guides/`), com `powershell -NoProfile -ExecutionPolicy Bypass -File`:

1. `render-exercise-guides.ps1 -Check -Data batch-<id>.json` até imprimir só `ok <slug>`.
2. `render-exercise-guides.ps1 -Sheet <id> -Data batch-<id>.json` gera `sheet-<id>.png` e `sheet-<id>-dark.png`.
3. Abra os dois PNG e confira cada quadro (lista no §8). Corrija e volte ao passo 1.
4. `-Only <slug,slug>` desenha só as guias que você está mexendo, e fica mais rápido.
5. Commit só com o `batch-<id>.json` e as duas folhas. O seed e o golden são gerados na integração, por `merge-guides.ps1`.

Na integração, depois do `merge-guides.ps1`, o `review-sheets.ps1` desenha as folhas do dono a partir do arquivo do seed: `sheet-all.png` (todas as guias) e `sheet-grupo-<grupo>.png` (por grupo de movimento, com uns 10 exercícios cada), cada uma também em `-dark`. Uma guia corrigida volta pelo lote dela: `batch-<id>.json`, `merge-guides.ps1` e `review-sheets.ps1`.

O `vocabulary.png` mostra um exemplo de cada cena, acessório e recurso. Os dados estão em `vocabulary.sample.json`, e copiar de lá é o jeito mais rápido de começar.

O arquivo é UTF-8 sem BOM, com fim de linha LF. O `-Check` recusa BOM, CRLF e qualquer chave desconhecida, e diferencia maiúsculas: `"Side"` não vale.

## 2. Ângulos e poses que passam

Os ângulos são absolutos, em graus: 0 é para a direita (para onde a figura olha), 90 para cima, −90 para baixo e 180 para a esquerda. O rosto aponta para `neck − 90`.

| Posição | trunk | neck | thigh | shin | foot | Âncora típica |
|---|---|---|---|---|---|---|
| Em pé | 88 a 90 | 90 | −88 a −90 | −88 a −92 | −10 a −12 | `ankle` em `[0, 0.039]` |
| Agachado (coxa paralela) | 50 a 65 | 64 a 75 | −10 a −12 | −110 a −118 | −12 | `ankle` |
| Sentado reto | 90 a 100 | 90 a 95 | 0 a 12 | −85 a −10 | conforme o pé | `hip` |
| Deitado de costas, cabeça à esquerda | 180 | 178 | −4 | −96 | −12 | `hip` |
| De bruços, cabeça à direita (prancha) | 5 | 3 | −175 | −175 | −90 | `toe` |
| Quatro apoios, virado à direita | 0 a 5 | ≈ −20 | −90 | 180 | −90 | `kneeFar` ou `toe` |

Trava E10 (vista lateral, nos dois lados). Calcule o ângulo relativo e normalize para (−180, 180]:
- joelho `shin − thigh`: de −165 a 5. Com a perna esticada, deixe de 0 a −5; valor positivo é o joelho dobrado para trás;
- tornozelo `foot − shin`: de 0 a 140. Em pé dá cerca de 78;
- pescoço `neck − trunk`: de −60 a 60;
- quadril `thigh − trunk`: de 150 a 180, ou de −180 a −25. Em pé dá −178; sentado, cerca de −90; o limite −25 é o joelho quase no peito.

Se uma pose real não couber, pare e reporte: a faixa muda na SPEC, com o motivo.

## 3. Âncora

- Escolha o ponto que fica parado de verdade: o tornozelo em pé, o quadril no banco, a mão na barra fixa, a ponta do pé na prancha, o tornozelo do pé que fica no degrau.
- Âncora na mão ou no braço (`hand`, `wrist`, `elbow`, `fist` e os `Far`) exige braços por ângulos, sem `arms.reach`.
- `"anchor": {"joint": "none"}` é só para saltos. Cada quadro leva `root` (a posição do quadril), e nada fica preso ao chão: confira os pés no quadro de apoio.

## 4. Braços

- **Por ângulos** (sem `arms`, ou `arms` sem `reach`): dê `upperArm` e `forearm` em todos os quadros. Serve para braços soltos, para halteres pendurados e para qualquer âncora no braço.
- **IK até a pegada** (`"reach": "grip"`): cada quadro leva `grip` em estaturas, no mundo. A mão alcança até 0,375 H do ombro (0,186 + 0,146 + 0,4 × 0,108). Além disso o braço estica na direção da pegada e não chega, e isso aparece na folha.
- **IK até um acessório** (`"reach": "<id>"`): o acessório tem de estar em `back`, `chest` ou `hip`. É a barra do agachamento.
- `elbow` (em `arms` ou por quadro) escolhe o lado do cotovelo: −90 para baixo, −150 para baixo e para trás, 0 para a frente, 170 para trás.
- `arms.forearm` trava o antebraço (90 = vertical), como no supino. O `-Check` recusa se o braço precisar esticar mais que 0,186 H.
- `"farArm": "pose"` (só de lado, com `reach`): o braço de lá segue `upperArmFar` e `forearmFar` de cada quadro. Use em exercício de um braço só.
- `armDepth` (0,3 a 1) encurta o braço que sai do plano do desenho. Na vista frontal ele é ignorado, porque os braços de frente não têm escorço.

## 5. Cena e acessórios

- **Cena:** é fixa. Use `block` para caixa, degrau ou cadeira, `pad` para encosto ou apoio, `post` para tubo ou armação, `wheel` para aro (com `radius` 0,018 vira a barra fixa vista de ponta) e `steps` para escada.
  - `layer` muda a ordem: `back`, `mid` ou `front`. Ponha a barra fixa em `front`, para ela aparecer sobre a mão.
  - `tone: "soft"` clareia o item.
- **Acessórios:** movem-se com o corpo e precisam de `attach`, que pode ser:
  - um ponto do esqueleto, com `offset` no mundo;
  - `back` ou `chest`, com `offset` = [frente, cima] no referencial do tronco;
  - um segmento (`thigh`, `shin`, `foot`, `upperArm`, `forearm` e os `Far`), com `along` de 0 a 1 e `side` (positivo = lado esquerdo de quem vai do começo ao fim do segmento).
- `cable` e `band` não têm `attach`. Eles vão de `from`, que é o id de uma `pulley`, `wheel`, `pad`, `footPlate` ou `post`, até `to`, que é um acessório ou um ponto do esqueleto.
- Na vista frontal, um acessório em `hand` aparece nas duas mãos, com o `offset` espelhado. Nessa vista, `back` e `chest` partem da base do pescoço (`neckBase`), que é o topo do tronco de frente.
- Não decida a cena pelo campo `equipment` do catálogo: os 6 exercícios de medicine ball estão como `dumbbell`. A máquina é genérica, só sugerida.

## 6. Seta, partes em destaque e guias paradas

- `cue.track` é o ponto que anda: `hip` nos agachamentos e dobradiças, `hand` ou o id do acessório nos exercícios de braço.
  - Afaste a seta do corpo com `offset`, ou com `side` + `gap` (à direita ou à esquerda de quem anda pelo caminho).
  - Use `span` para cortar as pontas, como `[0.05, 0.95]`.
- O acento forte sai do cálculo (E9). Se a folha destacar a parte errada, force com `moving`: uma chave do lado de cá vale também para o de lá.
- `motion: "static"` é para o que não lê bem animado: rotação no plano horizontal, isometria, pedalada.
  - Com 2 ou 3 quadros, a folha mostra os quadros lado a lado com seta.
  - Com 1 quadro, o rótulo é `Posição`, `moving` é obrigatório e não há `cue`.

## 7. Textos (DESIGN §6 e §7)

- **Passos:** exatamente 3, no imperativo ("Apoie…", "Desça…", "Suba…"), com até 120 caracteres cada.
- **Erros:** exatamente 2, no formato "o erro: o que fazer", com ": ". A parte antes dos dois-pontos sai em negrito.
- **Legendas:** até 28 caracteres, descrevendo a posição ("Coxas paralelas ao chão").
- **`a11y`:** até 240 caracteres, descrevendo o movimento inteiro para quem não vê a figura.
- **`works`:** obrigatório nos aeróbicos ("coração e pulmões, com as pernas") e no pescoço ("pescoço"). Vai em minúsculas.
- **Aeróbicos:** os passos dizem a intensidade pelo teste da fala.
  - Moderado: dá para conversar, mas não para cantar.
  - Forte: só dá para dizer poucas palavras.
  - Leve: a conversa é fácil.
  - Nos intervalos, o descanso é andar ou pedalar devagar. Nada de frequência cardíaca, zonas ou ritmo em números.
- **Pescoço:** isometria leve, empurrando sem mexer a cabeça.
- **O que não entra:** jargão de academia, "falha", RIR e texto copiado de sites, livros ou apps.

## 8. Conferir a folha antes do commit

- Os pés estão no chão (ou no degrau e na plataforma) e não afundam.
- A mão está na barra, no puxador ou no halter em todos os quadros.
- Nada atravessa o corpo, o banco ou o chão, inclusive o kettlebell e a corda.
- O que se move está em acento forte, e o resto em acento suave.
- A seta segue o caminho certo e não cobre o rosto.
- No quadro final, o fantasma mostra a posição inicial.
- A figura continua legível na folha escura.
