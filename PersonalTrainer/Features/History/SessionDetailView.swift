import SwiftData
import SwiftUI
import TrainerCore

/// Detalhe de uma sessão do histórico (SPEC F5, RF-09, RF-12, RF-14, CA1-7, CA2-2): cabeçalho
/// com data, duração, séries de trabalho, exercícios realizados, tonelagem e FC (média/máx
/// quando há amostras), seguido de uma `SessionExerciseSection` por exercício, na ordem da
/// sessão; cada uma leva à evolução de carga do exercício (`ExerciseProgressView`, T2.10).
///
/// Só leitura: recebe o modelo por `init` e nunca toca o `ModelContext` (R4). Não lê
/// `AppEnvironment`; quem navega até aqui é `HistoryListView`. A tonelagem soma só exercícios
/// medidos em repetições (SPEC RF-12 com RF-43), com a medida lida de `\.exerciseTraits`.
///
/// Desde a 2.4 (SPEC §7.14 F7): numa sessão em que todo exercício com série é aeróbico, a seção "Coração"
/// mostra o tempo em cada intensidade pela FC do relógio e o último VO2máx, lidos de `\.cardioHeartRate`.
/// Só leitura, sem conselho; sem FC e sem VO2máx, a seção não aparece.
@MainActor
struct SessionDetailView: View {
    let session: WorkoutSessionModel
    let references: ReferenceCatalog

    @Environment(\.exerciseTraits) private var traits
    /// FC por minuto, zonas e VO2máx (SPEC F7); padrão `.none`, sem nada.
    @Environment(\.cardioHeartRate) private var cardioHeartRate
    /// A FC média de cada minuto da sessão, lida uma vez ao abrir (SPEC F7). Vazia até a leitura terminar.
    @State private var minuteHeartRates: [Double] = []

    init(session: WorkoutSessionModel, references: ReferenceCatalog) {
        self.session = session
        self.references = references
    }

    var body: some View {
        List {
            Section("Resumo") {
                LabeledContent("Data", value: DateFormatting.shortDate(session.startedAt))
                LabeledContent("Duração", value: DateFormatting.duration(stats.duration))
                LabeledContent("Séries de trabalho", value: "\(stats.workingSetCount)")
                LabeledContent("Exercícios realizados", value: "\(stats.exerciseCount)")
                LabeledContent("Tonelagem", value: tonnageText)
                LabeledContent(
                    "FC média / máx",
                    value: Self.heartRateText(average: session.avgHeartRate, maximum: session.maxHeartRate)
                )
                if let statusText {
                    LabeledContent("Situação", value: statusText)
                }
            }
            .listRowBackground(Theme.surface)
            if let heart = heartContent {
                heartSection(heart)
            }
            ForEach(orderedExercises, id: \.uuid) { sessionExercise in
                SessionExerciseSection(sessionExercise: sessionExercise, references: references)
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle(session.programDayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.uuid) {
            await loadMinuteHeartRates()
        }
    }

    // MARK: - Coração (SPEC §7.14 F7)

    /// "Coração": a barra fina em três tons de `health` com "Leve 6 min · Moderada 22 min · Forte 12 min" e,
    /// quando há, "VO2máx: 42,1 (bom)", em `textSecondary` (DESIGN §13, "Na 2.4"). Sem conselho.
    private func heartSection(_ content: CardioZoneText.Content) -> some View {
        Section(CardioZoneText.title) {
            if let minutes = content.zones, let line = CardioZoneText.zonesLine(minutes) {
                VStack(alignment: .leading, spacing: 8) {
                    CardioZoneBar(minutes: minutes)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(CardioZoneText.spokenZones(minutes)))
            }
            if let vo2MaxLine = content.vo2MaxLine {
                Text(vo2MaxLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// O que a seção "Coração" mostra; `nil` fora de uma sessão de aeróbico ou sem FC e sem VO2máx.
    private var heartContent: CardioZoneText.Content? {
        guard isAerobicSession else {
            return nil
        }
        return CardioZoneText.content(
            heartRates: minuteHeartRates,
            zones: cardioHeartRate.zones(),
            vo2Max: cardioHeartRate.latestVo2Max()
        )
    }

    /// Todo exercício com ao menos uma série é aeróbico (SPEC F5, F7).
    private var isAerobicSession: Bool {
        let patterns: [MovementPattern?] = orderedExercises
            .filter { !$0.sets.isEmpty }
            .map { $0.exercise?.movementPattern }
        return CardioZoneText.isAerobicSession(patterns)
    }

    /// Lê a FC de cada minuto entre o começo e o fim da sessão, só numa sessão de aeróbico que terminou.
    /// Sem leitura (sem relógio, sem permissão), a lista fica vazia e a parte das zonas não aparece.
    private func loadMinuteHeartRates() async {
        guard isAerobicSession, let end = session.endedAt, end > session.startedAt else {
            return
        }
        let rates = await cardioHeartRate.minuteHeartRates(session.startedAt, end)
        minuteHeartRates = rates
    }

    // MARK: - Dados derivados

    private var orderedExercises: [SessionExerciseModel] {
        session.exercises.sorted { $0.order < $1.order }
    }

    /// Duração, séries de trabalho e tonelagem (SPEC RF-12) a partir das séries gravadas;
    /// aquecimentos ficam fora (SPEC P1).
    private var stats: SessionStats {
        SessionStats.compute(
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exerciseSets: orderedExercises.map { exercise in
                exercise.sets
                    .sorted { $0.index < $1.index }
                    .map { HistoryMapper.setResult(from: $0) }
            }
        )
    }

    /// "3.450 kg" (agrupamento pt-BR; até uma casa decimal para cargas de 2,5 kg). Segundos e
    /// passos ficam fora (SPEC RF-43): carga × passos não é tonelagem.
    private var tonnageText: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let tonnage = MeasureText.tonnage(of: orderedExercises, traits: traits)
        let number = formatter.string(from: NSNumber(value: tonnage)) ?? "\(tonnage)"
        return "\(number) kg"
    }

    /// FC só é exibida (SPEC §7.6); sem amostras, sem autorização ou com valor não positivo
    /// (nenhuma leitura real), "FC indisponível" (CA2-2; ARCHITECTURE §15, HealthKit).
    static func heartRateText(average: Double?, maximum: Double?) -> String {
        guard let average, average.isFinite, average > 0 else {
            return "FC indisponível"
        }
        let averageText = "\(Int(average.rounded()))"
        guard let maximum, maximum.isFinite, maximum > 0 else {
            return "\(averageText) / — bpm"
        }
        return "\(averageText) / \(Int(maximum.rounded())) bpm"
    }

    /// Só aparece quando a sessão não foi concluída normalmente.
    private var statusText: String? {
        switch session.status {
        case .abandoned: return "Abandonada"
        case .inProgress: return "Em andamento"
        case .completed, nil: return nil
        }
    }
}

/// Barra de tinta fina da seção "Coração" (SPEC F7; DESIGN §13 "Na 2.4"): um traço por intensidade, do leve
/// ao forte, na largura dos minutos, em três tons de `health` (nunca vermelho). As intensidades sem minuto
/// não aparecem. Decorativa: o VoiceOver lê a frase da seção.
private struct CardioZoneBar: View {
    private struct Segment: Hashable {
        let id: Int
        let minutes: Int
        let opacity: Double
    }

    let minutes: CardioZoneText.ZoneMinutes

    private static let gap: CGFloat = 2
    private static let height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: Self.gap) {
                ForEach(segments, id: \.id) { segment in
                    Capsule()
                        .fill(Theme.health.opacity(segment.opacity))
                        .frame(width: width(of: segment, totalWidth: proxy.size.width))
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    /// Leve, moderada e forte, cada vez mais escura; só as que têm minutos.
    private var segments: [Segment] {
        let all = [
            Segment(id: 0, minutes: minutes.light, opacity: 0.35),
            Segment(id: 1, minutes: minutes.moderate, opacity: 0.65),
            Segment(id: 2, minutes: minutes.vigorous, opacity: 1),
        ]
        return all.filter { $0.minutes > 0 }
    }

    private func width(of segment: Segment, totalWidth: CGFloat) -> CGFloat {
        let total = max(1, minutes.total)
        let gaps = Self.gap * CGFloat(max(0, segments.count - 1))
        let available = max(0, totalWidth - gaps)
        return available * CGFloat(segment.minutes) / CGFloat(total)
    }
}

// MARK: - Preview

#if DEBUG
/// Container in-memory com uma sessão de exemplo para o preview do detalhe. Só em DEBUG e
/// só aqui: o app real nunca insere modelos a partir de `Features/` (R4).
private enum SessionDetailPreviewData {
    struct Fixture {
        let container: ModelContainer
        let session: WorkoutSessionModel
    }

    @MainActor
    static func make() -> Fixture? {
        guard let container = try? ModelContainerFactory.make(.inMemory) else {
            return nil
        }
        let context = container.mainContext

        let legPress = ExerciseModel(
            uuid: UUID(),
            slug: "leg-press-45",
            name: "Leg press 45°",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads, .glutes]),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups([.hamstrings]),
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(legPress)

        let legCurl = ExerciseModel(
            uuid: UUID(),
            slug: "leg-curl",
            name: "Mesa flexora",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.hamstrings]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(legCurl)

        let startedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia B — Inferior",
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_900),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: 121,
            maxHeartRate: 158,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)

        let firstExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: legPress.uuid,
            exerciseName: legPress.name,
            prescribedLoad: 60,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.increase.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(firstExercise)
        firstExercise.exercise = legPress
        session.exercises.append(firstExercise)

        let sets: [(index: Int, load: Double, reps: Int, rir: Int?, isWarmup: Bool)] = [
            (0, 40, 12, nil, true),
            (1, 60, 10, 2, false),
            (2, 60, 9, 1, false),
            (3, 60, 8, 1, false),
        ]
        for set in sets {
            let completedAt = startedAt.addingTimeInterval(Double(set.index + 1) * 180)
            let setModel = SetLogModel(
                uuid: UUID(),
                index: set.index,
                load: set.load,
                reps: set.reps,
                rir: set.rir,
                isWarmup: set.isWarmup,
                completedAt: completedAt,
                sourceRaw: DeviceSource.iphone.rawValue,
                updatedAt: completedAt
            )
            context.insert(setModel)
            firstExercise.sets.append(setModel)
        }

        let skippedExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 1,
            exerciseUUID: legCurl.uuid,
            exerciseName: legCurl.name,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRepMin: 10,
            prescribedRepMax: 15,
            prescribedRIR: 2,
            restSeconds: 90,
            noteRaw: PrescriptionNote.calibrate.rawValue,
            wasSkipped: true,
            substitutedFromUUID: nil
        )
        context.insert(skippedExercise)
        skippedExercise.exercise = legCurl
        session.exercises.append(skippedExercise)

        return Fixture(container: container, session: session)
    }
}

#Preview("Sessão concluída") {
    if let fixture = SessionDetailPreviewData.make() {
        NavigationStack {
            SessionDetailView(session: fixture.session, references: .empty)
        }
        .modelContainer(fixture.container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}
#endif
