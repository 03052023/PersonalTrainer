# Proposta: Como fazer (RF-40) — pesquisa de 2026-09-24

Protótipo nesta pasta (compare.png, compare-dark.png). Gerador: render-exercise-guides.ps1 com exercise-guides.sample.json. Aguarda aprovação do dono antes de entrar na SPEC.

**Decisões do dono (2026-09-24):**
- **Autoria aprovada:** o agente rascunha poses e textos (3 passos + 2 erros) e o dono revisa por lote, numa folha. Não é IA no app nem imagem gerada por modelo.
- **Exceção de design aprovada:** equipamento discreto só dentro da folha "Como fazer" (DESIGN §12 proposto); a proibição continua no resto do app.
- **Estilo: "dê mais clareza para o usuário".** A v2 (compare-v2.png) destaca o que se move, tem seta de movimento, legenda por posição, "Trabalha: …", o supino corrigido e a figura maior. Aguarda aprovação da v2.

## Recomendação

UMA ABORDAGEM: ilustração própria gerada pelo app (opção A), mais passos padronizados, sem nenhuma mídia de terceiros.

1. O que é: cada exercício vira dados num arquivo novo, Resources/Seed/exercise-guides.v1.json, ligado pelo slug. Os dados são: vista (lateral ou frontal), 2 ou 3 quadros em ângulos por segmento, a articulação que fica parada, o equipamento, o ritmo, a descrição para o VoiceOver, 3 passos e 2 erros comuns.
2. Onde fica o código:
   - A matemática (interpolação, cinemática, mão no implemento, validação) vai para TrainerCore/Guide: só Foundation, testada no Core tests do CI Linux.
   - O desenho usa TimelineView(.animation(minimumInterval:paused:)) com Canvas. Conferi na documentação da Apple: as duas APIs existem desde o iOS 15, e o schedule de animação tem pausa embutida. O Canvas não oferece acessibilidade por elemento, então a ilustração inteira recebe um único rótulo.
3. Reserva para os exercícios difíceis: o mesmo manequim, parado, com setas (motion "static") e o texto. Nada de fonte aberta:
   - o Everkinetic não tem 7 dos 11 difíceis;
   - mudaria o estilo no meio do app;
   - traria crédito e ShareAlike;
   - contraria a decisão que o dono já registrou no RF-40.
4. Ordem de entrega:
   - (1) motor e validador;
   - (2) ferramenta de autoria no Windows, com teste de paridade contra o Swift, e a tela [CI];
   - (3) lote 1 com os 54 exercícios dos programas, que é o que o usuário realmente faz;
   - (4) botão na sessão, na Home e no catálogo;
   - (5) revisão do dono pela folha de conferência e no iPhone;
   - (6) lote 2 com os 45 restantes.
   O botão só aparece quando a guia está completa.
5. Correções antes de começar:
   - alinhar as proporções dos braços a Drillis e Contini (0,186, 0,146 e 0,108 H; o protótipo usa 0,188 e 0,145);
   - desenhar o implemento que se move em textSecondary (≥ 3:1);
   - para o supino e outros exercícios deitados, desenhar o braço do lado de lá mais claro, ou mover o ponto de vista para o antebraço não cruzar o tronco;
   - acrescentar o §12 ao DESIGN.md, com as exceções para halteres dentro da folha e para o ritmo da demonstração.
6. Decisões do dono antes da T6.1:
   - (a) aprovar o manequim do protótipo;
   - (b) aceitar que poses e textos sejam rascunhados por um agente e revisados por ele. Não é IA dentro do app e não usa modelo de imagem, mas é bom confirmar, dada a regra "sem IA";
   - (c) aprovar a exceção do DESIGN.

## Comparação

ANTES DE COMPARAR: o RF-40 já está na SPEC (commit 083a8bb, 24/09/2026), com a decisão do dono: ilustração "própria, minimalista e sem realismo … sem mídia de terceiros", e a T6.1 é só um marcador de lugar. A tarefa gerada pede uma "regra nova" com "fonte aberta de reserva". Pela AGENTS §1, isso contradiz uma decisão já registrada, e eu não resolvi a contradição escolhendo um lado em silêncio: o texto entregue SUBSTITUI a linha do RF-40, e a pesquisa sustenta a decisão do dono (detalhes abaixo).

OPÇÕES VIÁVEIS
A = ilustração própria gerada pelo app (Frente 3)
B = Everkinetic recolorido, CC BY-SA
C = híbrido B + A nas lacunas
D = vídeos do wger (autor Goulart)
E = só texto

1. Clareza para reconhecer o exercício
- A: boa em cerca de 88/99 (inferência da Frente 3). Fraca em 11: rotação no plano horizontal, saltos e máquinas específicas. Anima entre os quadros. Meta-análise de Höffler e Leutner (2007): animação supera imagem parada, com efeito maior em habilidade motora (d ≈ 1,06; vi só o resumo da busca).
- B: boa (traço, 2 quadros parados).
- C: boa, mas o estilo muda de um exercício para outro.
- D: a mais realista (pessoa real).
- E: fraca.

2. Padronização visual
- A: máxima (uma figura, uma escala, uma paleta).
- B: média (espessura do traço e detalhe variam).
- C: baixa (dois estilos).
- D: alta, mas só nos 46 que têm vídeo.
- E: total.

3. Licença e risco
- A: nenhum. Obra própria, sem atribuição. As proporções do corpo são um dado científico.
- B: CC BY-SA. Exige crédito e ShareAlike nas imagens recoloridas. Proveniência média: o ilustrador não é nomeado (licença conferida no Wayback pela Frente 1, no Commons pela Frente 2 e no GitHub, CC BY-SA 4.0, por mim).
- C: os riscos de B, mais o esforço de A.
- D: CC BY-SA 4.0, mas nenhum vídeo foi assistido.
- E: nenhum.

4. Cobertura dos 99
- A: 99 possíveis (cerca de 88 bons).
- B: 55 a 57 equivalentes, 64 a 68 com variantes. Contei agora: 15 dos 54 exercícios usados nos programas não têm imagem nenhuma (hip thrust, remadas unilateral e na máquina, swing, terra com kettlebell e hexagonal, dead bug, perdigueiro, Pallof, 3 carregamentos, salto na caixa, 2 de medicine ball). Também faltam 7 dos 11 exercícios "difíceis", justamente onde uma reserva ajudaria.
- C: 99.
- D: 26 a 31%.
- E: 99.

5. Tamanho no app
- A: cerca de 150 KB de JSON, zero imagens.
- B: cerca de 1,5 a 2,5 MB em SVG.
- C: B mais A.
- D: 20 a 45 MB, e só depois de transcodificar.
- E: cerca de 50 KB.

6. Adequação ao DESIGN.md
- A: alta. Manequim liso, tokens, modo escuro automático.
- B: parcial. Homem sem camisa e com músculos desenhados, o que bate no §1.4.
- C: parcial.
- D: ruim (academia real).
- E: neutra.

7. Esforço de implementação
- A: alto no conteúdo. A Frente 3 estima 65 a 70 h de poses e textos, cerca de 2 h de revisão do dono por lote e 3 a 4 dias de código. A autoria pode ser conferida no Windows, com o renderizador PowerShell que já existe.
- B: baixo para 64 exercícios (recolorir e importar; "Preserve Vector Data" não verificado). Ainda exige textos para todos e deixa 31 a 35 lacunas.
- C: o maior (motor de A + importação de B + tela de créditos).
- D: assistir e transcodificar 78 vídeos, e 53 exercícios ficam sem vídeo.
- E: baixo.

8. Compatível com o RF-40 atual?
- A: sim. B, C e D: não. E: parcial.

DESCARTADOS DE SAÍDA
- free-exercise-db e wrkout/exercises.json: o autor admite que as fotos foram raspadas, e o visual é de academia.
- ExerciseDB/Gym Visual, MuscleWiki e Darebee: licença proíbe redistribuir ou usar em app.
- RepDB: as imagens foram geradas por IA e a licença é proprietária.
- Manuais do Exército, NIA e CDC: choque de identidade, licença mista ou copyright da Tufts.
- Coleções CC0 genéricas: não têm poses de exercício.

CONFERI NO PROTÓTIPO (compare.png e interpolation-strip.png)
- A vista lateral e a frontal funcionam: pés parados, barra em linha reta, cabo acompanhando o puxador.
- Defeitos: no fim do supino o antebraço atravessa o tronco e o banco, e o escorço lê como braço quebrado. As anilhas saem em cerca de #B5ABA1, com contraste de cerca de 2,1:1 contra a superfície (abaixo de 3:1). A figura é uma silhueta preenchida, não "traço simples" como diz o RF-40 atual; a redação foi ajustada.

## Lacunas apontadas pelo crítico

- O RF-40 e a T6.1 já existem (commit 083a8bb, 24/09/2026), com 'sem mídia de terceiros' decidido pelo dono. A tarefa gerada chamou de 'regra nova' e sugeriu uma fonte aberta de reserva, o que contradiz essa decisão. Entreguei uma substituição do RF-40 e não recomendei reserva de terceiros.
- Verifiquei por URL (1): TimelineView, TimelineSchedule.animation e animation(minimumInterval:paused:) existem desde o iOS 15 (developer.apple.com/tutorials/data/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:).json), assim como o Canvas. Ele avisa que 'doesn't offer interactivity or accessibility for individual elements'. accessibilityReduceMotion existe desde o iOS 13. Não medi o consumo de bateria e CPU da animação a 30 fps; só o aparelho confirma.
- Verifiquei (2): as proporções de Drillis e Contini (1966) no Fromuth 2008, ASME DETC08, fig. 1: 0,818 ombro, 0,530 quadril, 0,285 joelho, 0,039 tornozelo, 0,186 braço, 0,146 antebraço, 0,108 mão. A lista de exercícios da UTK (BME473) dá coxa 0,245 e perna 0,246. A fig. 4.1 de Winter é esse mesmo dado. Correção à Frente 3: a fonte é Drillis e Contini, reproduzida em Winter, e o protótipo usa 0,188/0,145 nos braços (outra fonte); é preciso alinhar.
- Conferi também: o GitHub everkinetic/data declara CC BY-SA 4.0 e credita Greg Priday; o ilustrador não é nomeado em lugar nenhum. A originalidade do Everkinetic não tem prova positiva. Isso fica irrelevante sob a recomendação.
- Não verificado por ninguém: a origem dos cerca de 226 exercícios novos do bryllim/workout-guide (possível conteúdo gerado); os 78 vídeos do autor Goulart no wger (nenhum foi assistido); a hipótese de que as fotos do free-exercise-db vêm do Bodybuilding.com (é inferência); a licença das imagens da Physiopedia e da Noun Project (403).
- A classificação A/B/C (39/49/11) e as 65 a 70 h de conteúdo são estimativas da Frente 3. O protótipo cobre só 4 dos 99 exercícios, e nenhum da classe C (Pallof, arremesso rotacional, saltos, voador, abdutora ainda não foram testados).
- Defeitos que vi no protótipo: no quadro final do supino, o antebraço cruza o tronco e o banco e lê como braço quebrado. As anilhas (cerca de #B5ABA1, mistura de textSecondary com surface a 0,52) dão cerca de 2,1:1 contra a surface, abaixo de 3:1 para gráfico essencial. A figura é uma silhueta preenchida, não 'traço simples' como diz o RF-40 atual (a redação foi ajustada).
- Conflitos com o DESIGN.md que exigem o §12 novo: o §1.4 proíbe halteres, o §9.6 proíbe silhuetas de corpo na Home e o §10 limita animações a 0,4–0,6 s. O dono precisa aprovar as exceções.
- Regra 'sem IA': poses e textos seriam rascunhados por um agente, como o código. O ADR 012 e a decisão 13 tratam de IA no app e nenhuma imagem é gerada por modelo, mas o dono deve confirmar que aceita.
- Correção de técnica: nenhum profissional revisou poses nem textos, e não há fonte bibliográfica por guia; a revisão do dono é a única checagem. Os textos não podem copiar sites ou livros (copyright).
- Dois renderizadores (PowerShell para autoria e Swift no app) podem divergir. O Swift não roda localmente (o Smart App Control bloqueia o toolchain), então a pré-visualização no Windows não usa o motor Swift. Mitigação: o teste de paridade da T6.4.
- Diferenças de pegada (pronada, supinada, neutra) quase não aparecem na vista lateral; os passos precisam dizer. Rotação no plano horizontal e isometrias não animam bem em 2D (motion 'static'). A máquina genérica pode não ser igual à da academia do usuário.
- Um exercício do seed editado pelo usuário mantém o slug, então a guia pode não bater se ele for reaproveitado para outro movimento (pendência C11). Exercícios personalizados ficam sem guia.
- Dependência de escopo: a T6.2 (RF-41) também edita Features/Home/PrescriptionRow.swift, então a T6.7 precisa vir depois dela.
- O repositório não tem arquivo LICENSE: a arte própria fica 'todos os direitos reservados' por padrão. Serve para uso pessoal; escolher uma licença é decisão do dono, fora do escopo.
- Correção aos achados da Frente 3: são 6 exercícios de medicine ball com equipment 'dumbbell', não 7. hip-abduction-machine está com movementPattern 'hipThrust'. Ambos fora do escopo, mas a cena da guia não deve depender do campo equipment.
- Höffler e Leutner (2007): uso só o resumo da busca (d = 0,37 geral, d = 1,06 em conhecimento procedimental-motor); as páginas do resumo original deram 403/405. É apoio, não base da recomendação.
- Transparência: o WebFetch salvou sozinho 3 PDFs (Illinois, UTK, Fromuth) em C:\Users\leona\.claude\projects\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\tool-results, fora do repositório. Escrevi o script C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\pdftext.py para ler o texto deles. Nada foi alterado no repositório.

## Texto proposto para SPEC e DESIGN

=== 1) SPEC §6: substituir a linha RF-40 ===

| RF-40 | **Como fazer** (pedido do usuário, 2026-09-24; detalhado após a pesquisa `exercise-illustrations-research`): botão "Como fazer" (símbolo `play.circle`) em cada exercício que tem guia, na sessão (ao lado do nome), na Home (linha da prescrição) e no catálogo (tela do exercício). Abre uma folha com: (a) uma ilustração **própria, minimalista e sem realismo**, um manequim liso de cor única, sem músculos, sem rosto e sem roupa marcada, com o equipamento só sugerido, desenhada pelo app a partir de números de pose (§7.12) e animada em loop lento entre a posição inicial e a final, com botão Pausar; (b) **3 passos curtos e 2 erros comuns** em pt-BR, com palavras próprias. Todos os exercícios usam a mesma figura, a mesma escala, as cores do DESIGN §3 e o mesmo formato. **Origem e licença:** nenhuma foto, vídeo, GIF ou desenho de terceiros e nenhuma imagem gerada por modelo de imagem. A arte é obra própria do projeto, gerada em tempo de execução a partir de `Resources/Seed/exercise-guides.v1.json`, por isso não há atribuição a exibir (as proporções do corpo são um dado científico citado em §7.12 E3). **Offline:** tudo vem no app (cerca de 150 KB de dados, nenhuma imagem) e nada usa rede. **Acessibilidade:** com Reduzir Movimento, as posições aparecem paradas lado a lado, com a inicial em fantasma e uma seta. Para o VoiceOver, a ilustração é um único elemento com descrição própria, seguido de "Passo 1 de 3…" e dos erros comuns. Os textos seguem o Dynamic Type, e a figura e o implemento têm contraste ≥ 3:1 nos modos claro e escuro. Exercício sem guia (por exemplo, um personalizado) não mostra o botão. | v2.1 |

=== 2) SPEC §7: nova seção (depois da §7.11) ===

### 7.12 Como fazer: guias de execução (v2.1)

Cada guia descreve em dados um exercício do catálogo: a vista (lateral ou frontal), 2 ou 3 quadros de pose em ângulos por segmento do corpo, a articulação que fica parada, o equipamento, o ritmo, a descrição acessível, 3 passos e 2 erros comuns. O app desenha e anima a figura a partir desses números. A matemática (interpolação, posição das articulações, mão no implemento) fica em `TrainerCore/Guide`, pura e testada por tabela; a tela só pinta o resultado.

| Regra | Descrição |
|-------|-----------|
| **E1 Ligação por slug** | Cada guia aponta um `slug` do catálogo do seed, com no máximo uma guia por `slug`. Exercício sem guia (personalizado ou ainda não desenhado) não mostra "Como fazer". Na sessão vale o exercício realizado: se foi trocado (RF-34), aparece a guia do substituto. |
| **E2 Conteúdo fixo** | 2 ou 3 quadros com rótulo ("Início", "Fim" e, se houver, "Meio"); exatamente 3 passos e 2 erros comuns, cada um com no máximo 120 caracteres, em pt-BR e no tom do DESIGN §6; descrição acessível não vazia. Os textos usam palavras próprias: nada é copiado de sites, livros ou apps. |
| **E3 Uma figura só** | Todas as guias usam o mesmo manequim e a mesma escala. Comprimentos em fração da estatura H segundo Drillis e Contini (1966), reproduzidos em Winter, *Biomechanics and Motor Control of Human Movement*, fig. 4.1: ombro 0,818 H; quadril 0,530 H; joelho 0,285 H; tornozelo 0,039 H; braço 0,186 H; antebraço 0,146 H; mão 0,108 H (coxa 0,245 H e perna 0,246 H, por diferença). |
| **E4 Pose determinística** | A pose é função pura do tempo t dentro do ciclo. Cada ângulo é interpolado pelo menor arco, com `easeInOut`, e no início de cada fase a pose é exatamente a do quadro. Mesma guia e mesmo t → mesmas coordenadas. |
| **E5 Ponto fixo** | A articulação âncora (por exemplo, tornozelo no agachamento, quadril no supino) não se move em nenhum t (tolerância 0,001 H). Exceção declarada: `anchor: "none"` nos saltos, que seguem a trajetória do quadril dada pelos quadros. |
| **E6 Mão no implemento** | Se o braço tem alvo ao alcance (pegada ou acessório), a mão chega a ele (tolerância 0,005 H), com o cotovelo do lado indicado. Fora do alcance, o braço estende na direção do alvo. O cálculo nunca produz valor inválido (NaN). |
| **E7 Ritmo calmo** | Ciclo = pausa no início + ida + pausa no fim + volta; padrão de 0,4 s, 1,5 s, 0,4 s e 1,5 s, com cada fase de movimento entre 0,8 s e 3 s. Guias marcadas `motion: "static"` (rotação no plano horizontal, isometrias) não animam e mostram setas. A animação para com Pausar, com Reduzir Movimento e quando a folha fecha. |
| **E8 Falha tratável** | Arquivo de guias ausente ou reprovado na validação (E1–E7) → registro no log e nenhum botão "Como fazer"; a sessão nunca é interrompida. Os testes garantem que o arquivo do bundle passa. |

=== 3) SPEC §11: nova decisão ===

17. **Como fazer com ilustração própria** (pedido do usuário e pesquisa de 2026-09-24): as guias usam só arte gerada pelo app a partir de dados do projeto. Os bancos gratuitos foram descartados por motivos diferentes: fotos raspadas de sites comerciais (free-exercise-db, exercises.json), fotos de usuários com licença não confiável (wger), mídia paga ou com redistribuição proibida (ExerciseDB/Gym Visual, MuscleWiki, Darebee) e imagens geradas por IA (RepDB). O Everkinetic (CC BY-SA) é legítimo, mas cobre cerca de 57 % do catálogo, mostra um corpo musculoso sem camisa (DESIGN §1.4) e exige atribuição e ShareAlike. Para exercícios difíceis de desenhar, a reserva é o mesmo manequim parado com setas, nunca mídia de outra fonte.

=== 4) DESIGN.md: novo §12 (na mesma PR da T6.1) ===

## 12. Ilustrações de exercício ("Como fazer", SPEC RF-40)

- Manequim liso em `accent`; membros do lado de lá em `accent` misturado a 50 % com `surface`; sem músculos, rosto ou roupa marcada. O implemento que se move (barra, halter, puxador, cabo) usa `textSecondary` (≥ 3:1); a estrutura fixa (banco, torre, assento) fica mais clara, como fundo.
- Única exceção ao "sem halteres" do §1.4: equipamento aparece só dentro da folha Como fazer, nunca em ícones, estados vazios, abas ou na Home. A figura também nunca aparece na Home (§9.6), só na folha.
- Exceção ao §10: a demonstração segue o ritmo do exercício (fases de 0,8 a 3 s, padrão 1,5 s, `easeInOut`, pausas de 0,4 s) e tem botão Pausar. Com Reduzir Movimento, os quadros ficam parados lado a lado.

## Tarefas propostas

=== TASKS.md: substituir a linha T6.1 ("Pendências para a versão 2.1") por este bloco ===

### Versão 2.1: Como fazer (RF-40, SPEC §7.12)

**Critérios de aceitação**

| CA | Verificação |
|----|-------------|
| CA6-1 | Core tests verdes com ao menos um teste por regra E1–E8 e o teste de paridade com o renderizador de autoria (T6.4). |
| CA6-2 | Todo exercício usado em `programs.v2.json` tem guia válida (o teste lê os dois arquivos); ao fim do lote 2, os 99 do seed também. |
| CA6-3 | No aparelho, "Como fazer" aparece na sessão, na Home e no catálogo para um exercício com guia, e não aparece para um exercício personalizado. Um exercício trocado mostra a guia do substituto. |
| CA6-4 | Em modo avião a folha abre e anima; o app cresce menos de 1 MB, e nenhum arquivo de imagem foi adicionado para as guias. |
| CA6-5 | Com Reduzir Movimento, as duas posições aparecem paradas lado a lado. Pausar para a animação. O VoiceOver lê a descrição, "Passo 1 de 3…" e os erros comuns, nessa ordem. |
| CA6-6 | No modo escuro e com Aumentar Contraste, figura e implemento continuam legíveis (tokens do DESIGN §3 e §12). |
| CA6-7 | O dono aprovou a folha de revisão de cada lote (data anotada aqui). |

- [ ] **T6.1 Guias de execução em TrainerCore (RF-40, §7.12 E1–E8)** — G1 — Escopo:
  - `Packages/TrainerCore/Sources/TrainerCore/Guide/`, arquivos novos: `ExerciseGuideCatalog.swift`, `ExerciseGuide.swift`, `GuideFrame.swift`, `GuidePose.swift`, `GuideRig.swift`, `GuidePoint.swift`, `GuideTiming.swift`, `GuideKinematics.swift`, `GuideSkeleton.swift`, `ExerciseGuideValidator.swift`, `ExerciseGuideError.swift`.
  - Testes `ExerciseGuideTests.swift` e `GuideKinematicsTests.swift`, que leem os arquivos reais por `#filePath`, como `SeedBundleTests`.
  - `PersonalTrainer/Resources/Seed/exercise-guides.v1.json`, só com as 4 guias do protótipo: agachamento livre, supino reto com barra, remada baixa e elevação lateral.
  - Documentos: SPEC §6 (RF-40), §7.12 e decisão 17; ARCHITECTURE §11 (formato do arquivo) e §17 (pastas `Guide/`, `Features/ExerciseGuide/`, `Services/ExerciseGuides/`); DESIGN §12.

  Base: `render-exercise-guides.ps1` e `exercise-guides.sample.json`, do protótipo da pesquisa. Correções pedidas:
  - proporções dos braços em 0,186, 0,146 e 0,108 H (E3);
  - no supino, antebraço sem cruzar o tronco.

  Só Foundation (R1). A pose é função de `t`, sem `Date()`. O arquivo novo entra no bundle sem [PROJ], porque o `project.yml` inclui `PersonalTrainer/` inteiro e os JSON do seed vão para a raiz do bundle. Depende de: nada. Aceite: CA6-1 parcial (E1–E8) e 4 guias válidas.
- [ ] **T6.4 Ferramenta de autoria no Windows** — G2 — Escopo:
  - `docs/design/render-exercise-guides.ps1`, porta do protótipo, no mesmo padrão do `render-app-icon.ps1`. Lê `exercise-guides.v1.json` e `exercises.v2.json` e gera `docs/design/exercise-guides/sheet-<lote>.png` nos modos claro e escuro, com quadros, passos e erros. A opção `-Golden` grava as coordenadas das articulações em t = 0, ¼, ½, ¾ e 1.
  - `Packages/TrainerCore/Tests/TrainerCoreTests/Fixtures/exercise-guides-golden.v1.json`.
  - `GuideGoldenTests.swift`: o motor Swift e o script concordam em até 0,001 H. Essa é a proteção contra os dois renderizadores divergirem, já que o Swift não roda localmente.

  Depende de: T6.1. Aceite: CA6-1 completo e folha das 4 guias gerada.
- [ ] **T6.5 [CI] Ilustração e folha "Como fazer"** — G2 — Escopo:
  - `Features/ExerciseGuide/GuideIllustrationView.swift`: `TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused))` com `Canvas`; partes do corpo como cápsulas; ordem de desenho do protótipo. O Canvas recebe um único `accessibilityLabel` com a descrição, porque não tem acessibilidade por elemento.
  - `Features/ExerciseGuide/GuideStaticFramesView.swift`: modo Reduzir Movimento, com quadros lado a lado, a posição inicial em fantasma e uma seta.
  - `Features/ExerciseGuide/ExerciseGuideSheet.swift`: título em New York, ilustração, Pausar/Continuar com ≥ 44 pt, passos numerados e erros comuns.
  - `Features/ExerciseGuide/ExerciseGuideButton.swift`: segue o padrão do `WhyButton` e some sem guia.

  Previews com as 4 guias. Usar só APIs do iOS 15 ou posterior, conferidas na documentação. Depende de: T6.1. Aceite: App build verde, previews das 4 guias e lista "Verificado/Incerto" (R11).
- [ ] **T6.6 Conteúdo, lote 1: os 54 exercícios dos programas** — G3 — Escopo: `PersonalTrainer/Resources/Seed/exercise-guides.v1.json`, `docs/design/exercise-guides/sheet-1*.png`, e o teste de cobertura em `ExerciseGuideTests.swift` (todos os slugs de `programs.v2.json` têm guia).
  - Ordem: fáceis e médios primeiro. Os 4 difíceis (cadeira abdutora, Pallof, salto na caixa, arremesso rotacional) podem sair como `motion: "static"`, com setas.
  - Poses e textos escritos à mão, sem modelo de imagem. Conferir cada quadro na folha antes do commit.
  - Não usar o campo `equipment` para decidir a cena: os 6 exercícios de medicine ball estão como `dumbbell`.

  Depende de: T6.1 e T6.4. Aceite: CA6-2 (54) e folha pronta para o dono.
- [ ] **T6.7 [CI] "Como fazer" no app** — G3 — Escopo:
  - `Services/ExerciseGuides/ExerciseGuideLibrary.swift`: mesmo padrão do `ReferenceLibrary` (lê o bundle, valida, devolve `.empty` em caso de falha; E8).
  - `App/AppEnvironment.swift` e `App/AppEnvironment+Factories.swift`: injeção.
  - Botão em `Features/Session/CurrentExercisePanel.swift` (ao lado do nome, usando o slug do exercício realizado), `Features/Home/PrescriptionRow.swift` e `Features/Catalog/ExerciseEditorView.swift`.

  Depende de: T6.5 e **T6.2**. Não rodar em paralelo com a T6.2, porque as duas editam `PrescriptionRow.swift`. Aceite: CA6-3 a CA6-6 no simulador.
- [ ] **T6.8 [USER] Revisão do lote 1 e teste no aparelho** — G4 — O dono olha a folha e o app e anota as correções por exercício (por exemplo, "o joelho não vai tão para a frente" ou "a máquina da minha academia é outra"). O agente corrige no escopo da T6.6. Aceite: CA6-7 (lote 1) e CA6-3 a CA6-6 no iPhone.
- [ ] **T6.9 Conteúdo, lote 2: os 45 restantes** — G5 — Escopo: `exercise-guides.v1.json`, `docs/design/exercise-guides/sheet-2*.png` e teste de cobertura ampliado para os 99. Difíceis previstos: voador, crucifixo inverso na máquina, abdominal na máquina, power clean suspenso, salto horizontal, arremesso para trás e extensão de pescoço na polia. Depende de: T6.8. Aceite: CA6-2 (99) e CA6-7 (lote 2).
