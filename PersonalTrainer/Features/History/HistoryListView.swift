import SwiftData
import SwiftUI
import TrainerCore

/// Lista de sessões do histórico, mais recente primeiro (SPEC F5, RF-09, CA1-7), com
/// "Apagar" por deslize (TASKS T2.13, SPEC RF-19).
///
/// Só leitura: `@Query` é o único acesso a dados (ARCHITECTURE §3) e nada aqui escreve (R4).
/// Apagar passa por `onDeleteSession`, que o integrador liga a `SessionCoordinating.deleteSession(id:)`;
/// o motor recalcula as próximas cargas por derivação do histórico (ADR 003) e o `@Query`
/// tira a linha sozinho. A view já traz a própria `NavigationStack` (título "Histórico" +
/// navegação para `SessionDetailView`); quem a embute numa aba não deve aninhá-la em outra.
@MainActor
struct HistoryListView: View {
    @Query(sort: \WorkoutSessionModel.startedAt, order: .reverse)
    private var sessions: [WorkoutSessionModel]

    private let references: ReferenceCatalog
    private let onDeleteSession: (UUID) throws -> Void

    /// Sessão aguardando confirmação no `confirmationDialog`.
    @State private var pendingDeletionID: UUID?
    @State private var isConfirmingDeletion = false
    /// Mensagem pt-BR do alerta de falha ao apagar.
    @State private var deletionErrorMessage = ""
    @State private var isPresentingDeletionError = false

    init(references: ReferenceCatalog, onDeleteSession: @escaping (UUID) throws -> Void) {
        self.references = references
        self.onDeleteSession = onDeleteSession
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleSessions.isEmpty {
                    ContentUnavailableView(
                        "Nenhum treino registrado ainda",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("As sessões finalizadas ou abandonadas aparecem aqui.")
                    )
                } else {
                    List {
                        ForEach(visibleSessions, id: \.uuid) { session in
                            NavigationLink {
                                SessionDetailView(session: session, references: references)
                            } label: {
                                SessionRow(session: session)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Sem `role: .destructive` de propósito: com esse papel a lista
                                // anima a remoção da linha antes da confirmação, e a linha
                                // "volta" se o usuário cancelar.
                                Button {
                                    pendingDeletionID = session.uuid
                                    isConfirmingDeletion = true
                                } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Histórico")
            .confirmationDialog(
                "Apagar este treino?",
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: pendingDeletionID
            ) { sessionID in
                Button("Apagar", role: .destructive) {
                    deleteSession(sessionID)
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeletionID = nil
                }
            } message: { _ in
                Text("As próximas cargas serão recalculadas.")
            }
            .alert("Não foi possível apagar", isPresented: $isPresentingDeletionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionErrorMessage)
            }
        }
    }

    private var visibleSessions: [WorkoutSessionModel] {
        Self.filterVisible(sessions)
    }

    // MARK: - Apagar (T2.13)

    private func deleteSession(_ sessionID: UUID) {
        pendingDeletionID = nil
        do {
            try onDeleteSession(sessionID)
        } catch {
            deletionErrorMessage = Self.deletionMessage(for: error)
            isPresentingDeletionError = true
        }
    }

    /// Mensagem pt-BR para uma falha de `onDeleteSession`.
    static func deletionMessage(for error: any Error) -> String {
        if let coordinatorError = error as? SessionCoordinatorError {
            switch coordinatorError {
            case .sessionNotFound:
                return "Este treino já tinha sido apagado."
            case .unsupported:
                return "Apagar treinos ainda não está disponível nesta versão."
            default:
                break
            }
        }
        return "Não foi possível apagar o treino. Tente de novo."
    }

    /// Sessões `inProgress` ficam fora: a sessão ativa pertence à Home ("Retomar", SPEC S3),
    /// não ao histórico. Filtro em memória porque `#Predicate` sobre `statusRaw` não muda a
    /// query estática do `@Query` e o volume de um usuário é pequeno (ARCHITECTURE §15).
    /// A ordem de entrada (mais recente primeiro) é preservada.
    static func filterVisible(_ sessions: [WorkoutSessionModel]) -> [WorkoutSessionModel] {
        let inProgress = SessionStatus.inProgress.rawValue
        return sessions.filter { $0.statusRaw != inProgress }
    }
}

// MARK: - Preview

#if DEBUG
/// Container in-memory com sessões de exemplo para o preview da lista. Só em DEBUG e só
/// aqui: o app real nunca insere modelos a partir de `Features/` (R4).
private enum HistoryPreviewData {
    @MainActor
    static func makeContainer() -> ModelContainer? {
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

        let base = Date(timeIntervalSince1970: 1_790_000_000)

        // Mais recente: em andamento, não deve aparecer na lista.
        insertSession(
            name: "Dia A — Superior",
            status: .inProgress,
            startedAt: base,
            durationSeconds: nil,
            setCount: 2,
            load: 65,
            exercise: legPress,
            into: context
        )
        insertSession(
            name: "Dia C — Costas",
            status: .abandoned,
            startedAt: base.addingTimeInterval(-2 * 86_400),
            durationSeconds: 1_500,
            setCount: 4,
            load: 62.5,
            exercise: legPress,
            into: context
        )
        insertSession(
            name: "Dia B — Inferior",
            status: .completed,
            startedAt: base.addingTimeInterval(-4 * 86_400),
            durationSeconds: 3_900,
            setCount: 12,
            load: 60,
            exercise: legPress,
            into: context
        )
        insertSession(
            name: "Dia A — Superior",
            status: .completed,
            startedAt: base.addingTimeInterval(-6 * 86_400),
            durationSeconds: 2_700,
            setCount: 9,
            load: 57.5,
            exercise: legPress,
            into: context
        )

        return container
    }

    @MainActor
    private static func insertSession(
        name: String,
        status: SessionStatus,
        startedAt: Date,
        durationSeconds: TimeInterval?,
        setCount: Int,
        load: Double,
        exercise: ExerciseModel,
        into context: ModelContext
    ) {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: name,
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: durationSeconds.map { startedAt.addingTimeInterval($0) },
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)

        let sessionExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: load,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(sessionExercise)
        sessionExercise.exercise = exercise
        session.exercises.append(sessionExercise)

        for index in 0..<setCount {
            let completedAt = startedAt.addingTimeInterval(Double(index + 1) * 180)
            let set = SetLogModel(
                uuid: UUID(),
                index: index,
                load: load,
                reps: 10,
                rir: 2,
                isWarmup: false,
                completedAt: completedAt,
                sourceRaw: DeviceSource.iphone.rawValue,
                updatedAt: completedAt
            )
            context.insert(set)
            sessionExercise.sets.append(set)
        }
    }
}

#Preview("Com sessões") {
    if let container = HistoryPreviewData.makeContainer() {
        HistoryListView(references: .empty, onDeleteSession: { _ in })
            .modelContainer(container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}

#Preview("Vazio") {
    if let container = try? ModelContainerFactory.make(.inMemory) {
        HistoryListView(references: .empty, onDeleteSession: { _ in })
            .modelContainer(container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}
#endif
