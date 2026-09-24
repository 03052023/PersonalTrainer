import Foundation

/// Raw values são persistidos (`ExerciseModel.equipmentRaw`) e vão para o backup: nunca renomear um case.
public enum Equipment: String, Codable, Sendable, Hashable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case smith
    case kettlebell
    /// Objeto comum de casa usado como carga: mochila com peso, garrafas de água, sacolas (SPEC RF-42,
    /// §7.13 H1). Exercício em que o objeto só apoia o corpo (cadeira, degrau, toalha) continua
    /// `bodyweight`, porque a carga mínima 0 de P8 vale só para peso do corpo.
    case household
}
