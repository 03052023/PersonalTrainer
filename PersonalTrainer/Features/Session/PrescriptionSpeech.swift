import Foundation
import TrainerCore

/// Leitura por voz (VoiceOver) da prescrição que aparece como "3 × 8–12 · 60 kg · RIR 2 · 2 min"
/// na Home, na Sessão e no Histórico. Os símbolos "×", "–" e "·" soam mal lidos em voz alta, e
/// "RIR 2" ganha a leitura do SPEC RF-41 (d): "parar com 2 repetições de reserva".
enum PrescriptionSpeech {
    /// "3 séries de 8 a 12 repetições, 60 kg, parar com 2 repetições de reserva, descanso de
    /// 2 minutos". `loadText` `nil` é a calibração sem carga (SPEC P2); `restSeconds` `nil`
    /// omite o descanso (Sessão e Histórico não o mostram na linha da prescrição).
    static func text(
        sets: Int,
        repMin: Int,
        repMax: Int,
        measure: ExerciseMeasure,
        loadText: String?,
        targetRIR: Int,
        restSeconds: Int? = nil
    ) -> String {
        var parts = [
            MeasureText.spokenSetsAndRange(sets: sets, min: repMin, max: repMax, measure: measure),
            loadText ?? "carga a definir na primeira série",
            RIRText.spokenTarget(targetRIR),
        ]
        if let restSeconds {
            parts.append(rest(seconds: restSeconds))
        }
        return parts.joined(separator: ", ")
    }

    /// "descanso de 2 minutos", "descanso de 1 minuto e 30 segundos", "descanso de 45 segundos".
    static func rest(seconds: Int) -> String {
        guard seconds > 0 else {
            return "sem descanso"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        let minutesText = minutes == 1 ? "1 minuto" : "\(minutes) minutos"
        let secondsText = remainder == 1 ? "1 segundo" : "\(remainder) segundos"
        if minutes == 0 {
            return "descanso de \(secondsText)"
        }
        if remainder == 0 {
            return "descanso de \(minutesText)"
        }
        return "descanso de \(minutesText) e \(secondsText)"
    }
}
