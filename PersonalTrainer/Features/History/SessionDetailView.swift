import SwiftData
import SwiftUI
import TrainerCore

/// Detalhe de uma sessão do histórico (SPEC F5, RF-09, RF-12, RF-14, CA1-7, CA2-2): cabeçalho
/// com data, duração, séries de trabalho, exercícios realizados, tonelagem e FC (média/máx
/// quando há amostras), seguido de uma `SessionExerciseSection` por exercício, na ordem da
/// sessão; cada uma leva à evolução de carga do exercício (`ExerciseProgressView`, T2.10).
///
/// Só leitura: recebe o modelo por `init` e nunca toca o `ModelContext` (R4). Não lê
/// `AppEnvironment`; quem navega até aqui é `HistoryListView`.
@MainActor
struct SessionDetailView: View {
    let session: WorkoutSessionModel
    let references: ReferenceCatalog

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
            ForEach(orderedExercises, id: \.uuid) { sessionExercise in
                SessionExerciseSection(sessionExercise: sessionExercise, references: references)
            }
        }
        .navigationTitle(session.programDayName)
        .navigationBarTitleDisplayMode(.inline)
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

    /// "3.450 kg" (agrupamento pt-BR; até uma casa decimal para cargas de 2,5 kg).
    private var tonnageText: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: NSNumber(value: stats.tonnage)) ?? "\(stats.tonnage)"
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
