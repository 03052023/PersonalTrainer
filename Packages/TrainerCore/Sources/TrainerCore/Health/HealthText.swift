import Foundation

/// Números dentro dos textos das sugestões de saúde (SPEC §7.10 A6: "sugestões trazem o motivo e os
/// números"). A formatação é feita à mão, em pt-BR fixo, em vez de `NumberFormatter`/`String(format:)`,
/// para que o texto seja idêntico no iPhone, no Linux do CI e nos testes, qualquer que seja o locale
/// do sistema (SPEC P11).
enum HealthText {
    /// Inteiro com separador de milhar pt-BR: 7000 → "7.000", -12500 → "-12.500".
    static func integer(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return (value < 0 ? "-" : "") + groups.joined(separator: ".")
    }

    /// No máximo uma casa decimal, com vírgula, sem ",0" no fim: 6.25 → "6,3", 7 → "7", 42.04 → "42",
    /// 1234.5 → "1.234,5". Arredonda meio para longe do zero.
    static func decimal(_ value: Double) -> String {
        let tenths = HealthMath.roundedInt(value * 10)
        let magnitude = tenths.magnitude
        let sign = tenths < 0 ? "-" : ""
        let whole = integer(Int(magnitude / 10))
        let fraction = magnitude % 10
        return fraction == 0 ? "\(sign)\(whole)" : "\(sign)\(whole),\(fraction)"
    }

    /// "1 dia" / "3 dias", para concordância simples no texto.
    static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(integer(value)) \(value == 1 ? singular : plural)"
    }
}
