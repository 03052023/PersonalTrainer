import Foundation

/// Tempo da animação (SPEC E7; docs/V23-CORE-CONTRACT.md §2.5). O ciclo é pausa + ida + pausa + volta; a suavização
/// fica em `GuideKinematics`, dentro de cada trecho entre quadros. Quem mede o relógio é a tela (TimelineView); aqui
/// só entra o número de segundos.
public enum GuideTiming {
    /// Duração do ciclo em segundos; 0 em `static` ou sem `timing`.
    public static func cycleSeconds(of guide: ExerciseGuide) -> Double {
        guard guide.motion == .loop, let timing = guide.timing else {
            return 0
        }
        return timing.hold + timing.toEnd + timing.hold + timing.toStart
    }

    /// O instante t, em 0…(n − 1) quadros, para `seconds` desde o começo do loop (o ciclo se repete; segundos
    /// negativos contam de trás para a frente). Em `static`, sempre 0.
    ///   - s < pausa → 0;
    ///   - na ida, (n − 1) × (s − pausa) / ida;
    ///   - na pausa do fim, n − 1;
    ///   - na volta, (n − 1) × (1 − (s − 2 × pausa − ida) / volta).
    public static func frameTime(of guide: ExerciseGuide, atSeconds seconds: Double) -> Double {
        let cycle = cycleSeconds(of: guide)
        guard cycle > 0, let timing = guide.timing, seconds.isFinite, timing.toEnd > 0, timing.toStart > 0 else {
            return 0
        }
        let last = Double(max(0, guide.frames.count - 1))
        var s = seconds.truncatingRemainder(dividingBy: cycle)
        if s < 0 {
            s += cycle
        }
        let value: Double
        if s < timing.hold {
            value = 0
        } else if s < timing.hold + timing.toEnd {
            value = last * (s - timing.hold) / timing.toEnd
        } else if s < 2 * timing.hold + timing.toEnd {
            value = last
        } else {
            value = last * (1 - (s - 2 * timing.hold - timing.toEnd) / timing.toStart)
        }
        return max(0, min(last, value))
    }
}
