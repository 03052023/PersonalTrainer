import Foundation

/// A sessão guiada (SPEC RF-44 i; DESIGN §13; docs/V23-UI-CONTRACT.md §4.4 item 1): depois de "Começar", um botão
/// grande preso embaixo da ficha guia série por série. Função pura sobre o estado de cada exercício, testável sem
/// SwiftData e sem tela.
///
/// O passo atual é o primeiro exercício pendente (nem feito nem pulado), com a série seguinte dele. O botão diz
/// "Marcar série" (exercício com várias séries), "Marcar como feito" (uma série só, como o aeróbico contínuo) ou,
/// com tudo feito, "Concluir a sessão". Acima do botão, uma linha: "Agora: Agachamento livre · série 2 de 3" ou,
/// durante o descanso, "A seguir: série 3".
enum SessionGuide {
    /// O que a ficha sabe de um exercício, na ordem da ficha.
    struct Item: Sendable, Hashable {
        let id: UUID
        let name: String
        let prescribedSets: Int
        /// Séries de trabalho já gravadas (SPEC P1; aquecimentos antigos fora).
        let loggedSets: Int
        let isSkipped: Bool

        init(id: UUID, name: String, prescribedSets: Int, loggedSets: Int, isSkipped: Bool) {
            self.id = id
            self.name = name
            self.prescribedSets = prescribedSets
            self.loggedSets = loggedSets
            self.isSkipped = isSkipped
        }

        /// Pendente = não pulado e com menos séries que o prescrito (a mesma regra do `ActiveSessionViewModel`).
        var isPending: Bool {
            !isSkipped && loggedSets < prescribedSets
        }
    }

    /// O que o botão grande faz.
    enum Action: Sendable, Hashable {
        /// Grava a série seguinte, como a bolinha vazia (RF-44 b), e inicia o descanso.
        case markSet
        /// O mesmo toque num exercício de uma série só.
        case markDone
        /// Tudo feito: o mesmo "Concluir" da barra, que vai direto ao resumo (RF-44 e).
        case finish
    }

    /// O passo da sessão.
    struct Step: Sendable, Hashable {
        /// Exercício do passo; `nil` com tudo feito.
        let exerciseID: UUID?
        let exerciseName: String
        /// Série seguinte, contada a partir de 1.
        let setNumber: Int
        let totalSets: Int
        let action: Action

        static let finished = Step(exerciseID: nil, exerciseName: "", setNumber: 0, totalSets: 0, action: .finish)
    }

    /// O primeiro pendente, com a série seguinte; sem pendentes, `finished`.
    static func step(for items: [Item]) -> Step {
        guard let current = items.first(where: { $0.isPending }) else {
            return .finished
        }
        return Step(
            exerciseID: current.id,
            exerciseName: current.name,
            setNumber: current.loggedSets + 1,
            totalSets: current.prescribedSets,
            action: current.prescribedSets > 1 ? .markSet : .markDone
        )
    }

    /// Texto do botão grande.
    static func buttonTitle(_ action: Action) -> String {
        switch action {
        case .markSet: return "Marcar série"
        case .markDone: return "Marcar como feito"
        case .finish: return "Concluir a sessão"
        }
    }

    /// Linha acima do botão. Sem descanso: "Agora: Agachamento livre · série 2 de 3" (uma série só: "Agora:
    /// Caminhada rápida"). Durante o descanso: "A seguir: série 3" se o passo continua no exercício que iniciou o
    /// descanso; senão, "A seguir: Supino reto". Tudo feito: "Tudo marcado.".
    static func line(for step: Step, isResting: Bool, restSourceID: UUID?) -> String {
        guard let exerciseID = step.exerciseID else {
            return allDone
        }
        if isResting {
            if exerciseID == restSourceID {
                return "A seguir: série \(step.setNumber)"
            }
            return "A seguir: \(step.exerciseName)"
        }
        guard step.totalSets > 1 else {
            return "Agora: \(step.exerciseName)"
        }
        return "Agora: \(step.exerciseName) · série \(step.setNumber) de \(step.totalSets)"
    }

    /// Linha com tudo marcado.
    static let allDone = "Tudo marcado."
}
