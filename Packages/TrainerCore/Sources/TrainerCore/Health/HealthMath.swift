import Foundation

/// Aritmética defensiva do painel de saúde. Dados do HealthKit podem vir vazios, zerados ou absurdos;
/// nada aqui pode travar o app (ADR 011), então conversões para `Int` nunca usam `Int(_:)` cru.
enum HealthMath {
    /// Tolerância para comparar médias de ponto flutuante com os limiares da SPEC (ex.: "≥ 10 %"),
    /// para que 45 vs. 0,9 × 50 caia do lado certo mesmo com erro de arredondamento binário.
    static let epsilon = 1e-9

    /// Arredonda para o inteiro mais próximo (meio para longe do zero). NaN vira 0 e valores fora de
    /// ±1e15 são limitados, porque `Int(Double)` trava com NaN, infinito ou estouro.
    static func roundedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let limit = 1e15
        return Int(min(max(value.rounded(), -limit), limit))
    }

    /// Média aritmética; `nil` para lista vazia. Soma em ordem crescente para que o resultado não
    /// dependa da ordem de entrada (SPEC §7.10 A6), já que a soma de `Double` não é associativa.
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted().reduce(0, +) / Double(values.count)
    }

    /// O valor só se for finito e > 0. Zero ou negativo em HRV, FC, sono ou VO2max é ausência de
    /// leitura (o HealthKit não tem "zero" legítimo para essas grandezas).
    static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
