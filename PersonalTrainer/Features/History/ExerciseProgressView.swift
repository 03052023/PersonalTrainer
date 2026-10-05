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
///
/// Desde a 2.4 (SPEC RF-46; achado A5 da 2.2): quando nenhuma série do exercício teve carga (> 0), o
/// gráfico mostra a melhor marca de cada sessão na medida dele (repetições, segundos, passos ou minutos),
/// sem "0 kg", sem 1RM estimado e sem a explicação de Epley (`usesLoad`).
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
        let hasLoad = Self.usesLoad(points)
        Group {
            if points.isEmpty {
                ContentUnavailableView(
                    "Sem séries registradas",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("A evolução aparece depois do primeiro treino com séries de trabalho deste exercício.")
                )
            } else {
                List {
                    // Papel (DESIGN §14): as linhas em `surface`, como nas outras listas da direção.
                    Group {
                        Section {
                            if hasLoad {
                                chart(points)
                                    .frame(height: 220)
                                    .padding(.vertical, 8)
                            } else {
                                amountChart(points)
                                    .frame(height: 220)
                                    .padding(.vertical, 8)
                            }
                        } footer: {
                            Text(hasLoad ? chartFooter : Self.amountFooter(measure: measure))
                        }
                        Section("Sessões") {
                            ForEach(Array(points.reversed())) { point in
                                sessionRow(point, hasLoad: hasLoad)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        // Papel (DESIGN §14): o fundo da lista (e do estado vazio) dá lugar ao papel.
        .paperBackground()
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

    /// Sem carga em nenhuma série (SPEC RF-46, 2.4): a melhor marca de cada sessão na medida do exercício,
    /// numa linha só. Nada de "0 kg" nem de 1RM.
    private func amountChart(_ points: [ProgressPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Data", point.date),
                    y: .value("Marca", point.bestSetReps)
                )
                .foregroundStyle(by: .value("Série", "Melhor série"))
                .symbol(by: .value("Série", "Melhor série"))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(LocalizedStringKey(MeasureText.pluralNoun(measure)))
    }

    /// Algum ponto teve carga (> 0). Sem nenhum, a evolução mostra a medida (SPEC RF-46, 2.4).
    static func usesLoad(_ points: [ProgressPoint]) -> Bool {
        points.contains { $0.maxLoad > 0 }
    }

    /// Legenda do gráfico sem carga: "Melhor série de cada sessão, em repetições. Aquecimentos não entram."
    static func amountFooter(measure: ExerciseMeasure) -> String {
        "Melhor série de cada sessão, em \(MeasureText.pluralNoun(measure)). Aquecimentos não entram."
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

    private func sessionRow(_ point: ProgressPoint, hasLoad: Bool) -> some View {
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
            Text(Self.detailLine(point, loadUnit: loadUnit, measure: measure, hasLoad: hasLoad))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Melhor série 60 kg × 10 · 1RM est. 80 kg · 3 séries" (kg e repetições),
    /// "Melhor série 20 kg × 40 passos · 3 séries" (segundos ou passos, SPEC RF-43) ou
    /// "Carga máx. nível 7 · 3 séries" (placas/nível com repetições). Sem carga em nenhuma sessão
    /// (`hasLoad` falso; SPEC RF-46, 2.4): "Melhor série 12 repetições · 3 séries", "Melhor série 45 segundos ·
    /// 2 séries", sem "0 kg" nem 1RM.
    static func detailLine(
        _ point: ProgressPoint,
        loadUnit: LoadUnit,
        measure: ExerciseMeasure,
        hasLoad: Bool = true
    ) -> String {
        let setsText = point.workingSetCount == 1 ? "1 série" : "\(point.workingSetCount) séries"
        guard hasLoad else {
            return "Melhor série \(TodayTargetText.amount(point.bestSetReps, measure: measure)) · \(setsText)"
        }
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

    /// Ordem crescente de "qualidade" da série: 1RM estimado, depois carga e, por fim, repetições (só
    /// desempata sem carga, quando o 1RM estimado é 0 em todas: vale a série com mais repetições; SPEC
    /// RF-46, 2.4). Fora das repetições (SPEC RF-43): carga, depois o número (segundos ou passos).
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
        if lhs.load != rhs.load {
            return lhs.load < rhs.load
        }
        return lhs.reps < rhs.reps
    }
}
