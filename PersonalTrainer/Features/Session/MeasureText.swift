import Foundation
import TrainerCore

/// Textos pt-BR da medida da série (SPEC RF-43): o mesmo número gravado em `reps` aparece como
/// repetições, segundos ou passos na prescrição ("3 × 20–40 s"), no registro da série (stepper
/// "Segundos") e no histórico ("0 kg × 30 s"). Compartilhado por Sessão, Home e Histórico.
///
/// Só formatação: a progressão (P4–P6) usa o número como ele é, em qualquer medida.
enum MeasureText {
    /// Título do stepper de registro: "Repetições", "Segundos", "Passos".
    static func title(_ measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps: return "Repetições"
        case .seconds: return "Segundos"
        case .steps: return "Passos"
        }
    }

    /// Plural minúsculo para rótulos de acessibilidade: "Diminuir segundos".
    static func pluralNoun(_ measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps: return "repetições"
        case .seconds: return "segundos"
        case .steps: return "passos"
        }
    }

    /// Limites do stepper. Repetições seguem o limite de sempre (0–50); uma prancha ou uma
    /// carregada passa fácil de 50, então segundos e passos têm teto maior.
    static func stepperRange(_ measure: ExerciseMeasure) -> ClosedRange<Int> {
        switch measure {
        case .reps: return 0...50
        case .seconds: return 0...600
        case .steps: return 0...400
        }
    }

    /// Faixa da prescrição depois de "S ×": "8–12", "20–40 s", "20–40 passos".
    static func range(min: Int, max: Int, measure: ExerciseMeasure) -> String {
        let numbers = "\(min)–\(max)"
        switch measure {
        case .reps: return numbers
        case .seconds: return "\(numbers) s"
        case .steps: return "\(numbers) passos"
        }
    }

    /// Número de uma série depois de "×": "10", "30 s", "30 passos" (ou "1 passo").
    static func amount(_ value: Int, measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps: return "\(value)"
        case .seconds: return "\(value) s"
        case .steps: return value == 1 ? "1 passo" : "\(value) passos"
        }
    }

    /// Leitura por voz de um número da série: "10 repetições", "1 segundo", "30 passos".
    static func spokenAmount(_ value: Int, measure: ExerciseMeasure) -> String {
        let singular: String
        switch measure {
        case .reps: singular = "repetição"
        case .seconds: singular = "segundo"
        case .steps: singular = "passo"
        }
        return value == 1 ? "1 \(singular)" : "\(value) \(pluralNoun(measure))"
    }

    /// Leitura por voz de "3 × 8–12": "3 séries de 8 a 12 repetições". Faixa de um número só
    /// ("3 × 10–10") vira "3 séries de 10 repetições".
    static func spokenSetsAndRange(sets: Int, min: Int, max: Int, measure: ExerciseMeasure) -> String {
        let setsText = sets == 1 ? "1 série" : "\(sets) séries"
        let low = Swift.min(min, max)
        let high = Swift.max(min, max)
        if low == high {
            return "\(setsText) de \(spokenAmount(low, measure: measure))"
        }
        return "\(setsText) de \(low) a \(high) \(pluralNoun(measure))"
    }

    /// Medida de um exercício do store pelo `slug` do catálogo do seed. Exercício personalizado,
    /// slug desconhecido ou relação anulada (exercício que sumiu do store) medem em repetições
    /// (SPEC RF-43).
    static func measure(of exercise: ExerciseModel?, in traits: ExerciseTraitsCatalog) -> ExerciseMeasure {
        guard let exercise, !exercise.isCustom else {
            return .reps
        }
        return traits.traits(forSlug: exercise.slug).measure
    }

    /// Tonelagem (SPEC RF-12, Σ carga × repetições das séries de trabalho) só com os exercícios
    /// medidos em repetições: carga × segundos ou carga × passos não é tonelagem e inflaria o
    /// total em "kg" (SPEC RF-43). Mesma conta de `SessionStats`, sobre os exercícios filtrados.
    static func tonnage(of exercises: [(measure: ExerciseMeasure, sets: [SetResult])]) -> Double {
        let repsOnly: [[SetResult]] = exercises.filter { $0.measure == .reps }.map { $0.sets }
        return SessionStats.compute(startedAt: .distantPast, endedAt: nil, exerciseSets: repsOnly).tonnage
    }

    /// A mesma tonelagem a partir dos exercícios gravados de uma sessão (resumo e histórico).
    static func tonnage(of sessionExercises: [SessionExerciseModel], traits: ExerciseTraitsCatalog) -> Double {
        let measured: [(measure: ExerciseMeasure, sets: [SetResult])] = sessionExercises.map {
            (exercise: SessionExerciseModel) -> (measure: ExerciseMeasure, sets: [SetResult]) in
            let sets: [SetResult] = exercise.sets.map { HistoryMapper.setResult(from: $0) }
            return (measure: MeasureText.measure(of: exercise.exercise, in: traits), sets: sets)
        }
        return tonnage(of: measured)
    }
}
