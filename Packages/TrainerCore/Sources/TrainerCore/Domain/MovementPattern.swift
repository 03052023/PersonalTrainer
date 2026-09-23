import Foundation

/// Padrão de movimento de um exercício (RF-34). Dois exercícios com o mesmo padrão e o mesmo grupo
/// primário são substitutos naturais (ex.: supino com barra ↔ supino com halteres ↔ flexão).
/// Raw values são persistidos (`ExerciseModel.movementPatternRaw`): nunca renomear um case.
public enum MovementPattern: String, Codable, Sendable, Hashable, CaseIterable {
    /// Empurrar na horizontal: supinos, flexão, chest press.
    case horizontalPush
    /// Empurrar na vertical: desenvolvimentos.
    case verticalPush
    /// Adução horizontal do ombro: crucifixo, voador, crossover.
    case chestFly
    /// Puxar na horizontal: remadas.
    case horizontalPull
    /// Puxar na vertical: puxadas, barra fixa.
    case verticalPull
    /// Isolamento de ombro: elevação lateral, frontal, crucifixo inverso, face pull.
    case shoulderIsolation
    /// Flexão de cotovelo: roscas.
    case elbowFlexion
    /// Extensão de cotovelo: tríceps.
    case elbowExtension
    /// Agachar: agachamentos, leg press, hack.
    case squat
    /// Passada/unilateral de joelho: afundo, búlgaro, step-up.
    case lunge
    /// Dobradiça de quadril: terra, stiff, good morning, swing sem ênfase explosiva.
    case hinge
    /// Extensão de quadril com joelho flexionado: elevação pélvica, glute bridge, abdução.
    case hipThrust
    /// Extensão de joelho isolada: cadeira extensora.
    case kneeExtension
    /// Flexão de joelho isolada: mesa/cadeira flexora, nórdico.
    case kneeFlexion
    /// Flexão plantar: panturrilhas.
    case calfRaise
    /// Flexão de tronco: abdominais.
    case coreFlexion
    /// Estabilidade de tronco: prancha, pallof, anti-rotação, roda.
    case coreStability
    /// Carregar peso andando: farmer's walk, suitcase carry.
    case carry
    /// Explosivo/potência: arremesso de medicine ball, saltos, kettlebell swing explosivo.
    case explosive
    /// Pescoço: isometrias.
    case neck

    /// Nome curto em pt-BR para a UI.
    public var displayName: String {
        switch self {
        case .horizontalPush: return "Empurrar (horizontal)"
        case .verticalPush: return "Empurrar (vertical)"
        case .chestFly: return "Crucifixo"
        case .horizontalPull: return "Puxar (horizontal)"
        case .verticalPull: return "Puxar (vertical)"
        case .shoulderIsolation: return "Ombro (isolado)"
        case .elbowFlexion: return "Bíceps"
        case .elbowExtension: return "Tríceps"
        case .squat: return "Agachar"
        case .lunge: return "Passada"
        case .hinge: return "Dobradiça de quadril"
        case .hipThrust: return "Glúteo (extensão de quadril)"
        case .kneeExtension: return "Extensão de joelho"
        case .kneeFlexion: return "Flexão de joelho"
        case .calfRaise: return "Panturrilha"
        case .coreFlexion: return "Abdominal"
        case .coreStability: return "Estabilidade de tronco"
        case .carry: return "Carregar"
        case .explosive: return "Explosivo"
        case .neck: return "Pescoço"
        }
    }
}
