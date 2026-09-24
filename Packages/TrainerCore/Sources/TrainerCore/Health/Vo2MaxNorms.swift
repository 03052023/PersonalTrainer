// FONTE DA TABELA (transcrita e conferida em 2026-09-23 contra o texto completo, PMC4919021):
//   Kaminsky LA, Arena R, Myers J. Reference Standards for Cardiorespiratory Fitness Measured With
//   Cardiopulmonary Exercise Testing: Data From the Fitness Registry and the Importance of Exercise
//   National Database. Mayo Clin Proc. 2015;90(11):1515–1523. doi:10.1016/j.mayocp.2015.07.026
//   Table 3, "Sex-Specific Percentiles for CRF From Treadmill Exercise Tests With Measured VO2max
//   Obtained From FRIEND…", linhas "Men from FRIEND" e "Women from FRIEND" (mL O2·kg⁻¹·min⁻¹).
//   Amostra: 7.783 testes cardiopulmonares máximos em esteira (4.611 homens, 3.172 mulheres),
//   20–79 anos, sem doença cardiovascular conhecida. As linhas "Cooper Clinic" da mesma tabela
//   (VO2max previsto pelo tempo de teste, não medido) NÃO são usadas.
//
// FAIXAS DO APP (convenção do app, NÃO é uma classificação publicada pela fonte): a tabela publica
// só os percentis 5, 10, 25, 50, 75, 90 e 95. O app usa cinco desses cortes para as seis faixas de
// `FitnessBand`:
//   veryPoor < P10 ≤ poor < P25 ≤ fair < P50 ≤ good < P75 ≤ excellent < P95 ≤ superior
// É uma aproximação das faixas de percentil usadas pelo ACSM (< 20, 20–39, 40–59, 60–79, 80–94,
// ≥ 95), cujos cortes 20/40/60/80 a FRIEND 2015 não publica. "Superior" (≥ P95) coincide; "bom"
// começa na mediana. Mudar esses cortes é mudança de regra (SPEC + teste).
//
// LIMITES: o VO2max do Apple Watch é uma estimativa submáxima, não medido com análise de gases; a
// faixa é orientação, não diagnóstico. Fora de 20–79 anos, ou com sexo `other`/desconhecido, não há
// linha na tabela e a faixa fica `nil` (não extrapolamos).
import Foundation

/// Tabela normativa de VO2max por idade e sexo (FRIEND 2015, ver comentário no topo do arquivo) e a
/// classificação em `FitnessBand` usada pelo painel de saúde (SPEC §7.10 A3).
public enum Vo2MaxNorms: Sendable {
    /// Percentis publicados na Table 3, na ordem das colunas de `percentiles(ageYears:sex:)`.
    public static let publishedPercentiles = [5, 10, 25, 50, 75, 90, 95]

    /// Idades cobertas pela tabela (décadas 20–29 a 70–79).
    public static let coveredAges = 20...79

    /// Valores de VO2max (mL/kg/min) nos percentis de `publishedPercentiles` para a década de
    /// `ageYears`, ou `nil` fora de 20–79 anos ou com sexo `other`.
    public static func percentiles(ageYears: Int, sex: BiologicalSexValue) -> [Double]? {
        guard coveredAges.contains(ageYears) else { return nil }
        let decade = (ageYears - coveredAges.lowerBound) / 10
        switch sex {
        case .male: return men[decade]
        case .female: return women[decade]
        case .other: return nil
        }
    }

    /// Faixa do VO2max `vo2Max` para a idade e o sexo. `nil` sem linha na tabela ou com valor inválido.
    public static func band(vo2Max: Double, ageYears: Int, sex: BiologicalSexValue) -> FitnessBand? {
        guard vo2Max.isFinite, vo2Max > 0,
              let row = percentiles(ageYears: ageYears, sex: sex)
        else {
            return nil
        }
        // Índices em `publishedPercentiles`: 1 = P10, 2 = P25, 3 = P50, 4 = P75, 6 = P95.
        if vo2Max >= row[6] { return .superior }
        if vo2Max >= row[4] { return .excellent }
        if vo2Max >= row[3] { return .good }
        if vo2Max >= row[2] { return .fair }
        if vo2Max >= row[1] { return .poor }
        return .veryPoor
    }

    // Colunas: P5, P10, P25, P50, P75, P90, P95. Linhas: 20–29, 30–39, 40–49, 50–59, 60–69, 70–79.
    // Transcrição literal de "Men from FRIEND" (Kaminsky 2015, Table 3).
    private static let men: [[Double]] = [
        [29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3],
        [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8],
        [24.2, 26.8, 31.9, 37.8, 45.0, 52.1, 55.6],
        [20.9, 22.8, 27.1, 32.6, 39.7, 45.6, 50.7],
        [17.4, 19.8, 23.7, 28.2, 34.5, 40.3, 43.0],
        [16.3, 17.1, 20.4, 24.4, 30.4, 36.6, 39.7],
    ]

    // Transcrição literal de "Women from FRIEND" (Kaminsky 2015, Table 3).
    private static let women: [[Double]] = [
        [21.7, 23.9, 30.5, 37.6, 44.7, 51.3, 56.0],
        [19.0, 20.9, 25.3, 30.2, 36.1, 41.4, 45.8],
        [17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7],
        [16.0, 17.3, 19.9, 23.4, 27.6, 32.0, 35.9],
        [13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4],
        [13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1],
    ]
}
