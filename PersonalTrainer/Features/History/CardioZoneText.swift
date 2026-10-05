import Foundation
import TrainerCore

/// A conta e os textos da seção "Coração" do detalhe de uma sessão de aeróbico no Histórico (SPEC §7.14 F7;
/// DESIGN §13 "Na 2.4"; 2.4). Só leitura e só fatos: o tempo em cada intensidade pela FC ("Leve 6 min ·
/// Moderada 22 min · Forte 12 min") e o último VO2máx com a faixa ("VO2máx: 42,1 (bom)"). Nenhum conselho,
/// e a FC nunca prescreve nada (§7.6, P12).
///
/// Funções puras, testáveis sem tela; a `SessionDetailView` só desenha o que sai daqui.
enum CardioZoneText {
    /// Minutos em cada intensidade, contados pela FC média de cada minuto (SPEC §7.10 A1).
    struct ZoneMinutes: Sendable, Hashable {
        let light: Int
        let moderate: Int
        let vigorous: Int

        init(light: Int, moderate: Int, vigorous: Int) {
            self.light = light
            self.moderate = moderate
            self.vigorous = vigorous
        }

        /// Minutos com leitura válida.
        var total: Int {
            light + moderate + vigorous
        }
    }

    /// O que a seção mostra. `nil` (em `content`) = a seção não aparece.
    struct Content: Sendable, Hashable {
        /// Minutos por intensidade; `nil` sem FC ou sem zonas.
        let zones: ZoneMinutes?
        /// "VO2máx: 42,1 (bom)"; `nil` sem VO2máx.
        let vo2MaxLine: String?
    }

    /// Título da seção.
    static let title = "Coração"

    /// Uma sessão de aeróbico: todo exercício com ao menos uma série é aeróbico (padrão `cardio`, SPEC F5 e
    /// F7), e existe ao menos um. `patternsOfExercisesWithSets` = o padrão de cada exercício que tem série.
    static func isAerobicSession(_ patternsOfExercisesWithSets: [MovementPattern?]) -> Bool {
        !patternsOfExercisesWithSets.isEmpty && patternsOfExercisesWithSets.allSatisfy { $0 == .cardio }
    }

    /// Cada minuto pela `HeartRateZones.intensity(forHeartRate:)`; minuto sem leitura (0, negativo ou não
    /// finito) fica fora.
    static func zoneMinutes(heartRates: [Double], zones: HeartRateZones) -> ZoneMinutes {
        var light = 0
        var moderate = 0
        var vigorous = 0
        for heartRate in heartRates {
            guard let intensity = zones.intensity(forHeartRate: heartRate) else {
                continue
            }
            switch intensity {
            case .light:
                light += 1
            case .moderate:
                moderate += 1
            case .vigorous:
                vigorous += 1
            }
        }
        return ZoneMinutes(light: light, moderate: moderate, vigorous: vigorous)
    }

    /// "Leve 6 min · Moderada 22 min · Forte 12 min". As intensidades sem minuto ficam fora da frase
    /// ("Moderada 30 min"); sem nenhum minuto, `nil`.
    static func zonesLine(_ minutes: ZoneMinutes) -> String? {
        var parts: [String] = []
        if minutes.light > 0 {
            parts.append("Leve \(minutes.light) min")
        }
        if minutes.moderate > 0 {
            parts.append("Moderada \(minutes.moderate) min")
        }
        if minutes.vigorous > 0 {
            parts.append("Forte \(minutes.vigorous) min")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "VO2máx: 42,1 (bom)"; sem faixa (sem idade ou sexo no perfil), "VO2máx: 42,1".
    static func vo2MaxLine(_ summary: Vo2MaxSummary) -> String {
        let value = decimal(summary.latest)
        guard let band = summary.band else {
            return "VO2máx: \(value)"
        }
        return "VO2máx: \(value) (\(band.displayName.lowercased()))"
    }

    /// O conteúdo da seção (SPEC F7): com FC (`heartRates` com ao menos um minuto válido e `zones` não nulo),
    /// os minutos por intensidade; com `vo2Max`, a linha dele. Sem FC e sem VO2máx, `nil`: a seção não aparece.
    static func content(heartRates: [Double], zones: HeartRateZones?, vo2Max: Vo2MaxSummary?) -> Content? {
        var minutesByZone: ZoneMinutes? = nil
        if let zones, !heartRates.isEmpty {
            let counted = zoneMinutes(heartRates: heartRates, zones: zones)
            if counted.total > 0 {
                minutesByZone = counted
            }
        }
        let vo2Line: String? = vo2Max.map { (summary: Vo2MaxSummary) -> String in vo2MaxLine(summary) }
        guard minutesByZone != nil || vo2Line != nil else {
            return nil
        }
        return Content(zones: minutesByZone, vo2MaxLine: vo2Line)
    }

    /// Leitura do VoiceOver da barra: "Leve 6 minutos, moderada 22 minutos, forte 12 minutos".
    static func spokenZones(_ minutes: ZoneMinutes) -> String {
        var parts: [String] = []
        if minutes.light > 0 {
            parts.append("leve \(MeasureText.spokenAmount(minutes.light, measure: .minutes))")
        }
        if minutes.moderate > 0 {
            parts.append("moderada \(MeasureText.spokenAmount(minutes.moderate, measure: .minutes))")
        }
        if minutes.vigorous > 0 {
            parts.append("forte \(MeasureText.spokenAmount(minutes.vigorous, measure: .minutes))")
        }
        let joined = parts.joined(separator: ", ")
        guard let first = joined.first else {
            return ""
        }
        return first.uppercased() + String(joined.dropFirst())
    }

    /// Número pt-BR com até uma casa: 42.14 → "42,1", 44 → "44".
    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
