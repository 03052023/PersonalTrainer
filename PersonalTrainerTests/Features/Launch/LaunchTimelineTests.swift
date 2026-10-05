import XCTest
@testable import PersonalTrainer

/// A linha do tempo da abertura (SPEC RF-50; docs/V23-UI-CONTRACT.md §4.2), com os números do
/// protótipo aprovado (`docs/design/v23-animation/launch.html`). Tabela de tempos: cada teste fixa um
/// `t` e confere o quadro, como a folha "Quadro a quadro" do protótipo.
final class LaunchTimelineTests: XCTestCase {

    private let tolerance = 0.0005

    // MARK: - RF-50: primeiro e último quadro

    func testRF50_firstFrameMatchesLaunchScreen() {
        // t = 0: idêntico à tela de lançamento — azul cheio, flor inteira (pétalas e miolo cheios,
        // sem giro nem crescimento), sem conteúdo da tela Início, barra de status escondida.
        let frame = LaunchTimeline.frame(at: 0, reduceMotion: false, dark: false, hasGoal: false)

        XCTAssertEqual(frame.turn, 0, accuracy: tolerance)
        XCTAssertEqual(frame.breathe, 1, accuracy: tolerance)
        XCTAssertEqual(frame.dawn, 0, accuracy: tolerance)
        XCTAssertEqual(frame.content, 0, accuracy: tolerance)
        XCTAssertEqual(frame.coreScale, 1, accuracy: tolerance)
        XCTAssertEqual(frame.coreOpacity, 1, accuracy: tolerance)
        XCTAssertFalse(frame.statusBarVisible)
        XCTAssertEqual(frame.petals.count, 5)
        for petal in frame.petals {
            XCTAssertEqual(petal.grow, 1, accuracy: tolerance, "a pétala não deveria ter crescido em t = 0")
            XCTAssertEqual(petal.slide, 0, accuracy: tolerance, "a pétala não deveria ter deslizado em t = 0")
            XCTAssertEqual(petal.opacity, 1, accuracy: tolerance, "a pétala deveria estar inteira em t = 0")
        }
        for grain in frame.pollen {
            XCTAssertEqual(grain.opacity, 0, accuracy: tolerance, "nenhum grão de pólen nasceu ainda em t = 0")
        }
    }

    func testRF50_endFrame() {
        // t = 0,92 (TL.end): conteúdo livre, escala de assentamento em 1, todas as pétalas somem,
        // barra de status visível.
        let frame = LaunchTimeline.frame(at: LaunchTimeline.duration, reduceMotion: false, dark: false, hasGoal: false)

        XCTAssertEqual(frame.content, 1, accuracy: tolerance)
        XCTAssertEqual(frame.todayScale, 1, accuracy: tolerance)
        XCTAssertTrue(frame.statusBarVisible)
        for petal in frame.petals {
            XCTAssertEqual(petal.opacity, 0, accuracy: tolerance, "toda pétala deveria ter sumido no fim")
        }
    }

    // MARK: - RF-50: Reduzir Movimento

    func testRF50_reduceMotion() {
        // Sem giro, sem respiro (constante 1) e sem pólen em nenhum instante; termina em 0,60 (mais
        // curto que os 0,92 normais).
        let times: [Double] = [0, 0.10, 0.30, LaunchTimeline.durationReduceMotion]
        for t in times {
            let frame = LaunchTimeline.frame(at: t, reduceMotion: true, dark: false, hasGoal: false)
            XCTAssertEqual(frame.turn, 0, accuracy: tolerance, "sem giro em t = \(t)")
            XCTAssertEqual(frame.breathe, 1, accuracy: tolerance, "sem respiro em t = \(t)")
            XCTAssertEqual(frame.todayScale, 1, accuracy: tolerance, "sem assentamento (tamanho final direto) em t = \(t)")
            for petal in frame.petals {
                XCTAssertEqual(petal.grow, 1, accuracy: tolerance, "sem crescimento em t = \(t)")
                XCTAssertEqual(petal.slide, 0, accuracy: tolerance, "sem deslizar em t = \(t)")
            }
            for grain in frame.pollen {
                XCTAssertEqual(grain.opacity, 0, accuracy: tolerance, "pólen é movimento: nada em t = \(t)")
            }
        }

        // No fim de Reduzir Movimento, o conteúdo já está livre.
        let end = LaunchTimeline.frame(at: LaunchTimeline.durationReduceMotion, reduceMotion: true, dark: false, hasGoal: false)
        XCTAssertEqual(end.content, 1, accuracy: tolerance)
        XCTAssertTrue(end.statusBarVisible)
    }

    // MARK: - RF-50: amanhecer quente só no claro

    func testRF50_darkHasNoWarmVeil() {
        // No pico do amanhecer (t = 0,45), o véu de areia existe no claro e nunca no escuro — em
        // nenhum instante, com ou sem Reduzir Movimento.
        let peak = 0.45
        let lightFrame = LaunchTimeline.frame(at: peak, reduceMotion: false, dark: false, hasGoal: false)
        let darkFrame = LaunchTimeline.frame(at: peak, reduceMotion: false, dark: true, hasGoal: false)
        XCTAssertGreaterThan(lightFrame.warm, 0, "o véu deveria aparecer no claro, no pico do amanhecer")
        XCTAssertEqual(darkFrame.warm, 0, accuracy: tolerance, "o véu nunca aparece no escuro")

        for t in stride(from: 0.0, through: LaunchTimeline.duration, by: 0.05) {
            XCTAssertEqual(
                LaunchTimeline.frame(at: t, reduceMotion: false, dark: true, hasGoal: false).warm, 0,
                accuracy: tolerance, "sem véu de areia no escuro, em t = \(t)"
            )
            XCTAssertEqual(
                LaunchTimeline.frame(at: t, reduceMotion: true, dark: true, hasGoal: false).warm, 0,
                accuracy: tolerance, "sem véu de areia no escuro (Reduzir Movimento), em t = \(t)"
            )
        }
    }

    // MARK: - RF-50: sem objetivo, nenhuma pétala cora

    func testRF50_noGoalNoTint() {
        for t in stride(from: 0.0, through: LaunchTimeline.duration, by: 0.04) {
            let frame = LaunchTimeline.frame(at: t, reduceMotion: false, dark: false, hasGoal: false)
            XCTAssertEqual(frame.goalTint, 0, accuracy: tolerance, "sem objetivo, nenhuma pétala cora, em t = \(t)")
            XCTAssertEqual(frame.goalHeader, 0, accuracy: tolerance, "sem objetivo, a florzinha não chega antes, em t = \(t)")

            let reducedFrame = LaunchTimeline.frame(at: t, reduceMotion: true, dark: false, hasGoal: false)
            XCTAssertEqual(reducedFrame.goalTint, 0, accuracy: tolerance)
            XCTAssertEqual(reducedFrame.goalHeader, 0, accuracy: tolerance)
        }
    }

    // MARK: - RF-50: cada grão de pólen só vive na própria janela

    func testRF50_pollenGrainsLiveOnlyInTheirWindow() {
        for (index, grain) in LaunchPollen.grains.enumerated() {
            let before = LaunchTimeline.frame(at: max(0, grain.start - 0.01), reduceMotion: false, dark: false, hasGoal: false)
            let after = LaunchTimeline.frame(at: grain.start + grain.life + 0.01, reduceMotion: false, dark: false, hasGoal: false)
            let middle = LaunchTimeline.frame(at: grain.start + grain.life / 2, reduceMotion: false, dark: false, hasGoal: false)

            XCTAssertEqual(before.pollen[index].opacity, 0, accuracy: tolerance, "grão de ângulo \(grain.angle) não deveria existir antes de nascer")
            XCTAssertEqual(after.pollen[index].opacity, 0, accuracy: tolerance, "grão de ângulo \(grain.angle) não deveria existir depois de morrer")
            XCTAssertGreaterThan(middle.pollen[index].opacity, 0, "grão de ângulo \(grain.angle) deveria estar visível no meio da própria vida")
        }
    }

    // MARK: - RF-50: determinístico

    func testRF50_deterministic() {
        let times: [Double] = [0, 0.12, 0.33, 0.45, 0.61, 0.77, 0.92]
        for t in times {
            for reduceMotion in [false, true] {
                for dark in [false, true] {
                    for hasGoal in [false, true] {
                        let first = LaunchTimeline.frame(at: t, reduceMotion: reduceMotion, dark: dark, hasGoal: hasGoal)
                        let second = LaunchTimeline.frame(at: t, reduceMotion: reduceMotion, dark: dark, hasGoal: hasGoal)
                        XCTAssertEqual(first, second, "o mesmo t deveria sempre dar o mesmo quadro")
                    }
                }
            }
        }
    }

    // MARK: - RF-50: a pétala do objetivo sai por último

    func testRF50_goalPetalFadesLast() {
        // No meio do desvanecer, com objetivo, a pétala designada (LaunchTimeline.designatedGoalPetalIndex)
        // ainda está mais inteira do que as outras — foi adiada. Sem objetivo, ela desvanece na ordem
        // normal, junto com (ou antes das) as outras.
        let t = 0.50
        let withGoal = LaunchTimeline.frame(at: t, reduceMotion: false, dark: false, hasGoal: true)
        let withoutGoal = LaunchTimeline.frame(at: t, reduceMotion: false, dark: false, hasGoal: false)

        let goalIndex = LaunchTimeline.designatedGoalPetalIndex
        let othersWithGoal = (0..<5).filter { $0 != goalIndex }.map { withGoal.petals[$0].opacity }
        let maxOtherOpacity = othersWithGoal.max() ?? 0

        XCTAssertGreaterThan(
            withGoal.petals[goalIndex].opacity, maxOtherOpacity,
            "com objetivo, a pétala designada deveria estar mais inteira que qualquer outra em t = \(t)"
        )

        // Sem objetivo, a pétala designada não tem tratamento especial: não fica à frente de todas as
        // outras (a ordem normal de desvanecer já a inclui como mais uma pétala qualquer).
        let othersWithoutGoal = (0..<5).filter { $0 != goalIndex }.map { withoutGoal.petals[$0].opacity }
        let maxOtherOpacityWithoutGoal = othersWithoutGoal.max() ?? 0
        XCTAssertLessThanOrEqual(
            withoutGoal.petals[goalIndex].opacity, maxOtherOpacityWithoutGoal + tolerance,
            "sem objetivo, a pétala designada não deveria ficar à frente de todas as outras"
        )
    }

    // MARK: - RF-50 (B5 da 2.3): o índice real da pétala do objetivo

    /// Os cinco `ProgramGoal.petalIndex`.
    private let allPetals: [Int] = [0, 1, 2, 3, 4]

    func testRF50_goalPetalOneOpensAfterPetalZero() {
        // Com o objetivo na pétala 1, a ordem de abrir continua a do protótipo (ORDER = 0, 4, 3, 2, 1,
        // de cima, no sentido anti-horário): a pétala 0 começa em 0,16 s e a 1, a última, em 0,30 s.
        // Em 0,26 s a 0 já cresceu e a 1 ainda nem começou. Antes (troca de estado no overlay), a
        // pétala do objetivo herdava os números da pétala 0 e abria primeiro.
        let frame = LaunchTimeline.frame(at: 0.26, reduceMotion: false, dark: false, goalPetalIndex: 1)

        XCTAssertGreaterThan(frame.petals[0].grow, 1.01, "a pétala 0 já deveria estar abrindo em t = 0,26")
        XCTAssertGreaterThan(frame.petals[0].slide, 0.01)
        XCTAssertEqual(frame.petals[1].grow, 1, accuracy: tolerance, "a pétala 1 (a do objetivo) é a última a abrir")
        XCTAssertEqual(frame.petals[1].slide, 0, accuracy: tolerance)
    }

    func testRF50_openOrderIgnoresGoal() {
        // Em 0,30 s, as pétalas abriram na ordem 0, 4, 3, 2, 1: cada uma mais que a seguinte, e a
        // última ainda nem começou — para qualquer objetivo, e idêntico ao quadro sem objetivo.
        let t = 0.30
        let baseline = LaunchTimeline.frame(at: t, reduceMotion: false, dark: false, goalPetalIndex: nil)
        let order = LaunchFlowerGeometry.openOrder
        XCTAssertEqual(order, [0, 4, 3, 2, 1])

        for goal in allPetals {
            let frame = LaunchTimeline.frame(at: t, reduceMotion: false, dark: false, goalPetalIndex: goal)
            let grows = order.map { frame.petals[$0].grow }
            for position in 1..<grows.count {
                XCTAssertGreaterThan(
                    grows[position - 1], grows[position],
                    "com o objetivo na pétala \(goal), a pétala \(order[position - 1]) deveria abrir antes da \(order[position])"
                )
            }
            XCTAssertEqual(frame.petals[order[order.count - 1]].grow, 1, accuracy: tolerance)

            for petalIndex in allPetals {
                XCTAssertEqual(frame.petals[petalIndex].grow, baseline.petals[petalIndex].grow, accuracy: tolerance)
                XCTAssertEqual(frame.petals[petalIndex].slide, baseline.petals[petalIndex].slide, accuracy: tolerance)
            }
        }
    }

    func testRF50_fadeOrderPutsGoalLast() {
        // Para os 5 objetivos: a ordem de sumir é a de abrir sem a pétala do objetivo, e ela no fim; e,
        // durante o desvanecer, ela é a mais inteira de todas.
        let openOrder = LaunchFlowerGeometry.openOrder
        XCTAssertEqual(LaunchTimeline.fadeOrder(goalPetalIndex: nil), openOrder, "sem objetivo, sai na ordem de abrir")

        let times: [Double] = [0.40, 0.45, 0.50, 0.55]
        for goal in allPetals {
            let order = LaunchTimeline.fadeOrder(goalPetalIndex: goal)
            XCTAssertEqual(order.last, goal, "o objetivo \(goal) deveria sair por último")
            XCTAssertEqual(Array(order.dropLast()), openOrder.filter { $0 != goal })
            XCTAssertEqual(order.sorted(), allPetals)

            for t in times {
                let frame = LaunchTimeline.frame(at: t, reduceMotion: false, dark: false, goalPetalIndex: goal)
                let others = allPetals.filter { $0 != goal }.map { frame.petals[$0].opacity }
                XCTAssertGreaterThan(
                    frame.petals[goal].opacity, others.max() ?? 0,
                    "com o objetivo na pétala \(goal), ela deveria estar mais inteira que as outras em t = \(t)"
                )
            }
        }
    }

    func testRF50_goalPetalReduceMotionFadesLast() {
        // Reduzir Movimento: as quatro outras esmaecem em 0,04...0,26 s e a do objetivo em 0,10...0,32 s.
        let t = 0.20
        for goal in allPetals {
            let frame = LaunchTimeline.frame(at: t, reduceMotion: true, dark: false, goalPetalIndex: goal)
            for petalIndex in allPetals where petalIndex != goal {
                XCTAssertGreaterThan(
                    frame.petals[goal].opacity, frame.petals[petalIndex].opacity,
                    "com Reduzir Movimento e o objetivo na pétala \(goal), ela deveria esmaecer depois da \(petalIndex)"
                )
            }
        }
    }

    func testRF50_goalPetalIndexTintsOnlyWithAGoal() {
        // Em 0,60 s a pétala já corou (janela 0,30...0,46) e a florzinha do cabeçalho já chegou (0,53...0,68).
        let withGoal = LaunchTimeline.frame(at: 0.60, reduceMotion: false, dark: false, goalPetalIndex: 3)
        XCTAssertGreaterThan(withGoal.goalTint, 0)
        XCTAssertGreaterThan(withGoal.goalHeader, 0)

        let withoutGoal = LaunchTimeline.frame(at: 0.60, reduceMotion: false, dark: false, goalPetalIndex: nil)
        XCTAssertEqual(withoutGoal.goalTint, 0, accuracy: tolerance)
        XCTAssertEqual(withoutGoal.goalHeader, 0, accuracy: tolerance)
    }

    func testRF50_hasGoalUsesTheDesignatedPetal() {
        // A assinatura congelada com `hasGoal` é só a sobrecarga com o índice designado.
        let times: [Double] = [0, 0.20, 0.45, 0.70, 0.92]
        for t in times {
            for reduceMotion in [false, true] {
                XCTAssertEqual(
                    LaunchTimeline.frame(at: t, reduceMotion: reduceMotion, dark: false, hasGoal: true),
                    LaunchTimeline.frame(at: t, reduceMotion: reduceMotion, dark: false, goalPetalIndex: LaunchTimeline.designatedGoalPetalIndex)
                )
                XCTAssertEqual(
                    LaunchTimeline.frame(at: t, reduceMotion: reduceMotion, dark: false, hasGoal: false),
                    LaunchTimeline.frame(at: t, reduceMotion: reduceMotion, dark: false, goalPetalIndex: nil)
                )
            }
        }
    }

    func testRF50_outOfRangeGoalPetalCountsAsNoGoal() {
        // Um índice que não é de nenhuma pétala não derruba nem muda a abertura: vale como sem objetivo.
        for badIndex in [-1, 5, 99] {
            XCTAssertEqual(LaunchTimeline.fadeOrder(goalPetalIndex: badIndex), LaunchFlowerGeometry.openOrder)
            for reduceMotion in [false, true] {
                XCTAssertEqual(
                    LaunchTimeline.frame(at: 0.45, reduceMotion: reduceMotion, dark: false, goalPetalIndex: badIndex),
                    LaunchTimeline.frame(at: 0.45, reduceMotion: reduceMotion, dark: false, goalPetalIndex: nil)
                )
            }
        }
    }

    // MARK: - RF-50 (B6 da 2.3): degradês da flor grande

    func testRF50_petalGradientMixesMatchScript() {
        // Os números que `docs/design/v23-animation/render-launch-assets.ps1` calcula com `Mix` para a
        // tela de lançamento (claro: 5 % para #1C2B40 e 35 % para #FFFFFF; escuro: 6 % para #101822 e
        // 30 % para #F4F1EA): o primeiro quadro da `Canvas` é a imagem da tela de lançamento.
        let light = LaunchPalette.petalRamp(dark: false)
        XCTAssertEqual(light.start, LaunchPalette.RGB(red: 230, green: 227, blue: 220), "#E6E3DC")
        XCTAssertEqual(light.end, LaunchPalette.RGB(red: 246, green: 243, blue: 237), "#F6F3ED")

        let dark = LaunchPalette.petalRamp(dark: true)
        XCTAssertEqual(dark.start, LaunchPalette.RGB(red: 214, green: 210, blue: 200), "#D6D2C8")
        XCTAssertEqual(dark.end, LaunchPalette.RGB(red: 232, green: 228, blue: 218), "#E8E4DA")
    }

    func testRF50_coreGradientMixesMatchScript() {
        // Miolo: a cor cheia em cima e, embaixo, 18 % do topo do degradê do fundo do ícone
        // (claro #2B3F58, escuro #18222F).
        let light = LaunchPalette.coreRamp(dark: false)
        XCTAssertEqual(light.start, LaunchPalette.RGB(red: 233, green: 220, blue: 198), "#E9DCC6")
        XCTAssertEqual(light.end, LaunchPalette.RGB(red: 199, green: 192, blue: 178), "#C7C0B2")

        let dark = LaunchPalette.coreRamp(dark: true)
        XCTAssertEqual(dark.start, LaunchPalette.RGB(red: 211, green: 196, blue: 171), "#D3C4AB")
        XCTAssertEqual(dark.end, LaunchPalette.RGB(red: 177, green: 167, blue: 149), "#B1A795")
    }

    func testRF50_paletteHexParsing() {
        XCTAssertEqual(LaunchPalette.RGB(hex: "#24354C"), LaunchPalette.RGB(red: 36, green: 53, blue: 76))
        XCTAssertEqual(LaunchPalette.RGB(hex: "FFFFFF"), LaunchPalette.RGB(red: 255, green: 255, blue: 255))
        XCTAssertEqual(LaunchPalette.RGB(hex: "não é cor"), LaunchPalette.RGB(red: 0, green: 0, blue: 0), "texto malformado vira preto")

        let black = LaunchPalette.RGB(red: 0, green: 0, blue: 0)
        let white = LaunchPalette.RGB(red: 255, green: 255, blue: 255)
        XCTAssertEqual(black.mixed(with: white, fraction: 0), black)
        XCTAssertEqual(black.mixed(with: white, fraction: 1), white)
        XCTAssertEqual(black.mixed(with: white, fraction: 0.5), LaunchPalette.RGB(red: 128, green: 128, blue: 128))
    }

    func testRF50_petalAxisRunsFromBaseToTip() {
        // O degradê de cada pétala vai de `base` a `tip`: a ponta da espinha tem de ser mesmo a ponta da
        // pétala (a pétala mede de 0,7 a 0,8 do raio da flor da base à ponta, e a ponta fica perto da
        // borda da flor), não um ponto qualquer do contorno.
        XCTAssertEqual(LaunchFlowerGeometry.petalAxes.count, 5)
        for (index, axis) in LaunchFlowerGeometry.petalAxes.enumerated() {
            let outline = BrisaGeometry.unitPetalOutlines[index]
            func distance(from point: CGPoint, to other: CGPoint) -> Double {
                Double(hypot(point.x - other.x, point.y - other.y))
            }

            let length = distance(from: axis.base, to: axis.tip)
            XCTAssertGreaterThan(length, 0.6, "pétala \(index): base e ponta deveriam estar longe uma da outra")
            XCTAssertLessThan(length, 0.9, "pétala \(index)")

            let farthest = outline.map { distance(from: axis.base, to: $0) }.max() ?? 0
            XCTAssertGreaterThanOrEqual(length, farthest - 0.01, "pétala \(index): a ponta é (quase) o ponto mais longe da base")

            let tipRadius = distance(from: .zero, to: axis.tip)
            XCTAssertGreaterThan(tipRadius, 0.85, "pétala \(index): a ponta fica perto da borda da flor")
            XCTAssertLessThanOrEqual(tipRadius, 1.0001, "pétala \(index)")
        }
    }

    func testRF50_coreGradientCoversTheWholeCore() {
        // O degradê vertical do miolo (±(52 + 4) px do ícone) cobre o miolo inteiro.
        let halfHeight = Double(LaunchFlowerGeometry.coreGradientHalfHeight)
        XCTAssertEqual(halfHeight, 56.0 / LaunchPollen.iconMaxRadius, accuracy: 0.0001)
        let tallest = BrisaGeometry.unitCenterOutline.map { abs(Double($0.y)) }.max() ?? 0
        XCTAssertGreaterThan(tallest, 0.1, "o miolo não é vazio")
        XCTAssertGreaterThan(halfHeight, tallest)
    }
}
