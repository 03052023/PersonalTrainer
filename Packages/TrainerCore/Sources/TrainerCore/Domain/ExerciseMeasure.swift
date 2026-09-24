import Foundation

/// O que o número de uma série conta (SPEC RF-43). O campo `reps` da série e da prescrição guarda esse
/// número em qualquer medida, e a progressão (P4–P6) usa a mesma lógica sobre ele; só o rótulo muda
/// ("3 × 20–40 s", "30 passos").
///
/// Vem do catálogo do seed pelo `slug` (`ExerciseTraitsCatalog`), sem campo no esquema de dados.
/// Raw values ficam no JSON do seed: nunca renomear um case.
public enum ExerciseMeasure: String, Codable, CaseIterable, Sendable {
    /// Repetições: o padrão de todo exercício, inclusive os personalizados.
    case reps
    /// Segundos de sustentação: pranchas e isometrias.
    case seconds
    /// Passos andando com a carga: carregadas.
    case steps
}
