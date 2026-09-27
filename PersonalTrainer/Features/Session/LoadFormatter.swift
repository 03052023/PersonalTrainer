import Foundation

/// Formatação pt-BR de cargas, compartilhada por Home, sessão, histórico e programa.
///
/// Veio de `SetDraft.swift` na versão 2.2, quando o rascunho da série saiu da sessão
/// (docs/V22-CONTRACT.md §2.4): assinatura e texto de saída continuam os mesmos.
enum LoadFormatter {
    /// "60 kg", "62,5 kg". Sem casas decimais quando inteiro.
    static func kilograms(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) kg"
    }

    /// Carga opcional: `nil` vira "—" (prescrição de calibração, SPEC P2).
    static func kilograms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return kilograms(value)
    }
}
