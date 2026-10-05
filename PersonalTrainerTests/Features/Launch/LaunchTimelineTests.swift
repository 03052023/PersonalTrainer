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
}
