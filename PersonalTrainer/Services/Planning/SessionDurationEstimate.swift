import Foundation
import TrainerCore

/// Duração estimada de uma sessão planejada (DESIGN §9.2; docs/V21-CONTRACT.md B7), mostrada na
/// Home como "≈ N min". Conta simples e determinística, sobre a prescrição de cada exercício:
///
/// - por série: o tempo de execução mais o descanso prescrito;
///   - repetições (`ExerciseMeasure.reps`): repetições médias da faixa × 3 s;
///   - segundos (`.seconds`): os segundos médios da faixa;
///   - passos (`.steps`): passos médios da faixa × 1 s. O contrato não fixa o ritmo das
///     carregadas; andar com carga dá perto de um passo por segundo, e 3 s por passo dobraria o
///     tempo de uma caminhada curta;
/// - mais 2 min por exercício para preparar (ajustar a carga, trocar de aparelho).
///
/// É só uma ordem de grandeza para a pessoa planejar o dia: aquecimento, séries unilaterais e
/// pausas fora do descanso não entram. Sem exercícios, 0 (a Home esconde a estimativa).
enum SessionDurationEstimate {
    /// Segundos por repetição (contrato B7).
    static let secondsPerRep = 3.0
    /// Segundos por passo numa carregada (ver comentário do tipo).
    static let secondsPerStep = 1.0
    /// Preparação de cada exercício (contrato B7: 2 min).
    static let setupSecondsPerExercise = 120.0

    /// Minutos inteiros, arredondados para o mais próximo; pelo menos 1 quando há exercício.
    static func minutes(for exercises: [PlannedExercise], traits: ExerciseTraitsCatalog) -> Int {
        guard !exercises.isEmpty else {
            return 0
        }
        let total = seconds(for: exercises, traits: traits)
        return max(1, Int((total / 60).rounded()))
    }

    /// Segundos da sessão inteira, sem arredondar.
    static func seconds(for exercises: [PlannedExercise], traits: ExerciseTraitsCatalog) -> Double {
        exercises.reduce(0) { total, planned in
            total + seconds(for: planned, measure: traits.traits(for: planned.exercise).measure)
        }
    }

    /// Um exercício: `sets` × (execução + descanso) + preparação. Valores negativos gravados por
    /// engano contam como zero, para a estimativa nunca ficar negativa.
    static func seconds(for planned: PlannedExercise, measure: ExerciseMeasure) -> Double {
        let prescription = planned.prescription
        let sets = Double(max(0, prescription.sets))
        let averageAmount = Double(max(0, prescription.repMin) + max(0, prescription.repMax)) / 2
        let work: Double
        switch measure {
        case .reps:
            work = averageAmount * secondsPerRep
        case .seconds:
            work = averageAmount
        case .steps:
            work = averageAmount * secondsPerStep
        }
        let rest = Double(max(0, prescription.restSeconds))
        return sets * (work + rest) + setupSecondsPerExercise
    }
}
