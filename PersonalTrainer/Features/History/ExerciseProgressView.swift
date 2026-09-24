import Charts
import SwiftData
import SwiftUI
import TrainerCore

/// Evolução de carga de um exercício ao longo das sessões (SPEC F5 "por exercício, evolução de
/// carga", TASKS T2.10): gráfico (Swift Charts) do melhor 1RM estimado e da carga máxima de
/// trabalho por sessão, e a lista das sessões abaixo, mais recente primeiro.
///
/// Só leitura: `@Query` filtrado por `exerciseUUID` é o único acesso a dados (ARCHITECTURE §3)
/// e nada aqui escreve (R4). O histórico é por exercício (SPEC §7.1, P3): um substituto tem a
/// própria curva. FC não aparece aqui (SPEC §7.6).
///
/// Exercício medido em segundos ou passos (SPEC RF-43, lido de `\.exerciseTraits`): o 1RM
/// estimado (Epley) não faz sentido, então o gráfico mostra só a carga máxima, e a melhor série
/// sai com a unidade ("20 kg × 40 passos").
@MainActor
struct ExerciseProgressView: View {
    /// Uma sessão no gráfico: só séries de trabalho (SPEC P1) com pelo menos 1 repetição.
    struct ProgressPoint: Identifiable, Hashable {
        /// `uuid` da sessão.
        let id: UUID
        let date: Date
        let dayName: String
        /// Melhor 1RM estimado da sessão (Epley: carga × (1 + reps/30)).
        let estimatedOneRepMax: Double
        /// Maior carga de trabalho da sessão.
        let maxLoad: Double
        /// Série que deu o melhor 1RM estimado (desempate: maior carga). Em segundos ou passos
        /// (SPEC RF-43), a de maior carga e, no empate, a de maior número.
        let bestSetLoad: Double
        let bestSetReps: Int
        let workingSetCount: Int
    }

    let exerciseUUID: UUID
    let exerciseName: String

    @Query private var sessionExercises: [SessionExerciseModel]
    @Environment(\.exerciseTraits) private var traits

    init(exerciseUUID: UUID, exerciseName: String) {
        self.exerciseUUID = exerciseUUID
        self.exerciseName = exerciseName
        // Mesmo filtro por `exerciseUUID` que o `SessionPlanner` usa para o histórico do motor.
        let uuid = exerciseUUID
        _sessionExercises = Query(filter: #Predicate<SessionExerciseModel> { $0.exerciseUUID == uuid })
    }

    var body: some View {
        let points = Self.points(from: sessionExercises, measure: measure)
        Group {
            if points.isEmpty {
                ContentUnavailableView(
                    "Sem séries registradas",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("A evolução aparece depois do primeiro treino com séries de trabalho deste exercício.")
                )
            } else {
                List {
                    Section {
                        chart(points)
                            .frame(height: 220)
                            .padding(.vertical, 8)
                    } footer: {
                        Text(chartFooter)
                    }
                    Section("Sessões") {
                        ForEach(Array(points.reversed())) { point in
                            sessionRow(point)
                        }
                    }
                }
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Gráfico

    private func chart(_ points: [ProgressPoint]) -> some View {
        Chart {
            if showsEstimatedOneRepMax {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Data", point.date),
                        y: .value("Carga", point.estimatedOneRepMax)
                    )
                    .foregroundStyle(by: .value("Série", "1RM estimado"))
                    .symbol(by: .value("Série", "1RM estimado"))
                }
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Data", point.date),
                    y: .value("Carga", point.maxLoad)
                )
                .foregroundStyle(by: .value("Série", "Carga máxima"))
                .symbol(by: .value("Série", "Carga máxima"))
            }
        }
        // Cargas de 40–80 kg ficariam achatadas num eixo que começa em zero.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(LocalizedStringKey(unitLabel))
    }

    /// O 1RM estimado (Epley) só faz sentido para carga em kg com repetições; placas e nível de
    /// máquina não são proporcionais ao peso, e segundos ou passos não são repetições (SPEC
    /// RF-43), então nesses casos o gráfico mostra só a carga máxima.
    private var showsEstimatedOneRepMax: Bool {
        Self.estimatesOneRepMax(loadUnit: loadUnit, measure: measure)
    }

    private var chartFooter: String {
        if showsEstimatedOneRepMax {
            return "1RM estimado pela fórmula de Epley (carga × (1 + reps/30)) na melhor série de trabalho de cada sessão. Aquecimentos não entram."
        }
        return "Maior carga de trabalho de cada sessão. Aquecimentos não entram."
    }

    // MARK: - Lista

    private func sessionRow(_ point: ProgressPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(DateFormatting.shortDate(point.date))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(point.dayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(detailText(point))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailText(_ point: ProgressPoint) -> String {
        Self.detailLine(point, loadUnit: loadUnit, measure: measure)
    }

    /// "Melhor série 60 kg × 10 · 1RM est. 80 kg · 3 séries" (kg e repetições),
    /// "Melhor série 20 kg × 40 passos · 3 séries" (segundos ou passos, SPEC RF-43) ou
    /// "Carga máx. nível 7 · 3 séries" (placas/nível com repetições).
    static func detailLine(_ point: ProgressPoint, loadUnit: LoadUnit, measure: ExerciseMeasure) -> String {
        let setsText = point.workingSetCount == 1 ? "1 série" : "\(point.workingSetCount) séries"
        if estimatesOneRepMax(loadUnit: loadUnit, measure: measure) {
            let bestSet = "\(loadText(point.bestSetLoad, unit: loadUnit)) × \(point.bestSetReps)"
            let oneRepMax = loadText(roundedToTenth(point.estimatedOneRepMax), unit: loadUnit)
            return "Melhor série \(bestSet) · 1RM est. \(oneRepMax) · \(setsText)"
        }
        if measure != .reps {
            let amount = MeasureText.amount(point.bestSetReps, measure: measure)
            return "Melhor série \(loadText(point.bestSetLoad, unit: loadUnit)) × \(amount) · \(setsText)"
        }
        return "Carga máx. \(loadText(point.maxLoad, unit: loadUnit)) · \(setsText)"
    }

    static func estimatesOneRepMax(loadUnit: LoadUnit, measure: ExerciseMeasure) -> Bool {
        loadUnit == .kilograms && measure == .reps
    }

    // MARK: - Unidade

    /// Unidade do catálogo relacionado; se nenhuma relação existe mais, assume kg (mesma
    /// convenção de `SessionExerciseSection`).
    private var loadUnit: LoadUnit {
        sessionExercises.lazy.compactMap { $0.exercise?.loadUnit }.first ?? .kilograms
    }

    private var unitLabel: String {
        switch loadUnit {
        case .kilograms: return "kg"
        case .plates: return "placas"
        case .level: return "nível"
        }
    }

    /// Repetições, segundos ou passos (SPEC RF-43), pelo `slug` do catálogo relacionado; sem
    /// relação, repetições.
    private var measure: ExerciseMeasure {
        MeasureText.measure(of: sessionExercises.lazy.compactMap { $0.exercise }.first, in: traits)
    }

    static func loadText(_ load: Double, unit: LoadUnit) -> String {
        switch unit {
        case .kilograms: return LoadFormatter.kilograms(load)
        case .plates: return "\(Int(load.rounded())) placas"
        case .level: return "nível \(Int(load.rounded()))"
        }
    }

    // MARK: - Dados (funções puras, testadas em HistoryTests)

    /// 1RM estimado pela fórmula de Epley: carga × (1 + reps/30).
    static func estimatedOneRepMax(load: Double, reps: Int) -> Double {
        load * (1 + Double(reps) / 30)
    }

    static func roundedToTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// Um ponto por sessão `completed` ou `abandoned` (as que contam como histórico, SPEC P3)
    /// com ≥ 1 série de trabalho de ≥ 1 repetição, em ordem cronológica (desempate pelo id da
    /// sessão, SPEC P11). Aquecimentos ficam fora (SPEC P1). Se o exercício aparece duas vezes
    /// na mesma sessão, as séries são somadas num só ponto. `inProgress` e status desconhecido
    /// ficam fora: o histórico só mostra o que terminou.
    ///
    /// Em segundos ou passos (SPEC RF-43) a melhor série é a de maior carga e, no empate, a de
    /// maior número: Epley não vale fora das repetições, e numa prancha sem carga o 1RM estimado
    /// seria 0 em todas as séries.
    static func points(from sessionExercises: [SessionExerciseModel], measure: ExerciseMeasure = .reps) -> [ProgressPoint] {
        var sessionsByID: [UUID: WorkoutSessionModel] = [:]
        var setsBySessionID: [UUID: [SetLogModel]] = [:]

        for sessionExercise in sessionExercises {
            guard
                let session = sessionExercise.session,
                let status = session.status,
                status == .completed || status == .abandoned
            else {
                continue
            }
            let workingSets = sessionExercise.sets.filter { !$0.isWarmup && $0.reps > 0 }
            guard !workingSets.isEmpty else {
                continue
            }
            sessionsByID[session.uuid] = session
            setsBySessionID[session.uuid, default: []].append(contentsOf: workingSets)
        }

        var points: [ProgressPoint] = []
        for (sessionID, sets) in setsBySessionID {
            guard
                let session = sessionsByID[sessionID],
                let bestSet = sets.max(by: { Self.ranksBelow($0, $1, measure: measure) })
            else {
                continue
            }
            points.append(
                ProgressPoint(
                    id: sessionID,
                    date: session.startedAt,
                    dayName: session.programDayName,
                    estimatedOneRepMax: estimatedOneRepMax(load: bestSet.load, reps: bestSet.reps),
                    maxLoad: sets.map(\.load).max() ?? bestSet.load,
                    bestSetLoad: bestSet.load,
                    bestSetReps: bestSet.reps,
                    workingSetCount: sets.count
                )
            )
        }

        return points.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Ordem crescente de "qualidade" da série: 1RM estimado, depois carga. Fora das repetições
    /// (SPEC RF-43): carga, depois o número (segundos ou passos).
    private static func ranksBelow(_ lhs: SetLogModel, _ rhs: SetLogModel, measure: ExerciseMeasure) -> Bool {
        if measure != .reps {
            if lhs.load != rhs.load {
                return lhs.load < rhs.load
            }
            return lhs.reps < rhs.reps
        }
        let lhsEstimate = estimatedOneRepMax(load: lhs.load, reps: lhs.reps)
        let rhsEstimate = estimatedOneRepMax(load: rhs.load, reps: rhs.reps)
        if lhsEstimate != rhsEstimate {
            return lhsEstimate < rhsEstimate
        }
        return lhs.load < rhs.load
    }
}
