import Foundation
import TrainerCore

/// Textos e escolhas puras do "Como fazer" (SPEC RF-40, §7.12 E1, E2 e E9; DESIGN §12): quando o botão aparece,
/// o "Trabalha: …", os rótulos da folha e as legendas numeradas. Sem estado e sem SwiftUI, para os testes.
///
/// Os nomes dos grupos no "Trabalha: …" são os da folha de revisão das guias
/// (`docs/design/exercise-guides/render-exercise-guides.ps1`, `$MuscleNames` e `$MuscleGloss`), em minúsculas
/// porque entram no meio da frase.
enum ExerciseGuideText {
    /// Rótulo do botão (SPEC RF-40).
    static let buttonTitle = "Como fazer"
    /// Símbolo do botão (SPEC RF-40: `play.circle`).
    static let buttonSymbol = "play.circle"
    /// Título da seção na folha "Informações do exercício" (SPEC RF-47).
    static let sectionTitle = "Como fazer"
    /// Pausar e continuar a animação (SPEC E7).
    static let pause = "Pausar"
    static let resume = "Continuar"
    static let stepsTitle = "Passos"
    static let mistakesTitle = "Erros comuns"
    static let close = "Fechar"

    // MARK: - E1: botão só com guia

    /// A guia do exercício, ou `nil` quando não há: exercício personalizado, slug desconhecido, exercício que sumiu
    /// do catálogo ou arquivo de guias vazio (SPEC E1, E8). Na sessão, quem chama passa o slug do exercício
    /// realizado, que é o do substituto quando houve troca.
    static func guide(forSlug slug: String?, isCustom: Bool, in catalog: ExerciseGuideCatalog) -> ExerciseGuide? {
        guard !isCustom, let slug, !slug.isEmpty else {
            return nil
        }
        return catalog.guide(forSlug: slug)
    }

    // MARK: - "Trabalha: …" (SPEC E2 e E9)

    /// O que o exercício trabalha, sem o rótulo: o `works` da guia quando existe (aeróbicos e pescoço, SPEC E2);
    /// senão os grupos primários do catálogo, "quadríceps (frente das coxas) e glúteos". Vazio sem nenhum dos dois.
    static func works(guide: ExerciseGuide, primaryMuscles: [MuscleGroup]) -> String {
        if let works = guide.works?.trimmingCharacters(in: .whitespacesAndNewlines), !works.isEmpty {
            return works
        }
        return list(primaryMuscles.map { muscleName($0) })
    }

    /// "Trabalha: peito, tríceps e ombros"; `nil` quando não há o que dizer (a linha some).
    static func worksLine(guide: ExerciseGuide, primaryMuscles: [MuscleGroup]) -> String? {
        let text = works(guide: guide, primaryMuscles: primaryMuscles)
        guard !text.isEmpty else {
            return nil
        }
        return "Trabalha: \(text)"
    }

    /// Nome do grupo no meio da frase; o termo técnico que o app mantém ganha a explicação em palavras comuns
    /// (DESIGN §7).
    static func muscleName(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: return "peito"
        case .back: return "costas"
        case .shoulders: return "ombros"
        case .biceps: return "bíceps"
        case .triceps: return "tríceps"
        case .quads: return "quadríceps (frente das coxas)"
        case .hamstrings: return "posteriores da coxa"
        case .glutes: return "glúteos"
        case .calves: return "panturrilhas"
        case .core: return "abdômen e lombar"
        }
    }

    // MARK: - Legendas e erros

    /// Legenda de um quadro para o VoiceOver da versão parada: "1, Início: Coxas paralelas ao chão".
    static func spokenCaption(number: Int, frame: GuideFrame) -> String {
        "\(number), \(frame.label.rawValue): \(frame.caption)"
    }

    /// Um erro comum no formato "o erro: o que fazer" (SPEC E2), separado para a folha mostrar o erro em
    /// semibold e a correção em regular. Sem ": ", tudo vai no erro.
    static func mistakeParts(_ text: String) -> (mistake: String, fix: String?) {
        guard let range = text.range(of: ": ") else {
            return (mistake: text, fix: nil)
        }
        let head = String(text[..<range.lowerBound]) + ":"
        let tail = String(text[range.upperBound...])
        return (mistake: head, fix: tail.isEmpty ? nil : tail)
    }

    /// Rótulo do VoiceOver do botão: "Como fazer: Agachamento livre".
    static func buttonAccessibilityLabel(exerciseName: String) -> String {
        "\(buttonTitle): \(exerciseName)"
    }

    // MARK: - Privado

    /// "a", "a e b", "a, b e c".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else {
            return ""
        }
        guard items.count > 1 else {
            return last
        }
        return items.dropLast().joined(separator: ", ") + " e " + last
    }
}
