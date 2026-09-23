import SwiftUI
import TrainerCore

/// Resumo exibido ao encerrar o treino (SPEC F4, RF-12; T1.8): situação, dia do programa,
/// duração, séries de trabalho, exercícios realizados e pulados, tonelagem, e o aviso de que o
/// próximo treino já foi recalculado — a Home relê o plano quando o fluxo fecha.
///
/// Só leitura: recebe a `WorkoutSessionModel` já `completed`/`abandoned` e formata; nada aqui
/// escreve no `ModelContext` (AGENTS R4). FC (média/máx) fica para o detalhe do histórico e
/// depende do HealthKit (M2).
struct SessionSummaryView: View {
    private let session: WorkoutSessionModel
    private let onClose: () -> Void

    init(session: WorkoutSessionModel, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                totals
                Text("O próximo treino já foi recalculado.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
        }
        .safeAreaInset(edge: .bottom) {
            closeButton
        }
    }

    // MARK: - Seções

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: isAbandoned ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(isAbandoned ? Color.orange : Color.green)
            Text(isAbandoned ? "Treino abandonado" : "Treino concluído")
                .font(.largeTitle.weight(.bold))
            Text(session.programDayName)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var totals: some View {
        VStack(spacing: 0) {
            summaryRow("Duração", value: DateFormatting.duration(stats.duration))
            Divider()
            summaryRow("Séries de trabalho", value: "\(stats.workingSetCount)")
            Divider()
            summaryRow("Exercícios realizados", value: "\(stats.exerciseCount) de \(orderedExercises.count)")
            Divider()
            summaryRow("Exercícios pulados", value: "\(skippedCount)")
            Divider()
            summaryRow("Tonelagem", value: tonnageText)
        }
        .padding(.horizontal, 16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Botão principal ≥ 56 pt, como o da Home (uso na academia, RNF-06).
    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Text("Fechar")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Dados derivados

    private var isAbandoned: Bool {
        session.status == .abandoned
    }

    private var orderedExercises: [SessionExerciseModel] {
        session.exercises.sorted { $0.order < $1.order }
    }

    private var skippedCount: Int {
        orderedExercises.filter { $0.wasSkipped }.count
    }

    /// Duração, séries de trabalho, exercícios realizados (≥ 1 série de trabalho) e tonelagem
    /// (RF-12); aquecimentos ficam fora (SPEC P1). Mesmo cálculo do detalhe do histórico.
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
}

// MARK: - Preview

#if DEBUG
/// Sessão encerrada montada só pelo caminho oficial de escrita (`SessionCoordinating`) sobre o
/// `AppEnvironment.preview()`: nenhum `insert`/`save` direto a partir de `Features/` (R4).
private enum SessionSummaryPreviewData {
    struct Fixture {
        let environment: AppEnvironment
        let session: WorkoutSessionModel
    }

    @MainActor
    static func make(abandoned: Bool) -> Fixture? {
        let environment = AppEnvironment.preview()
        let coordinator = environment.coordinator
        var clock = environment.now()
        guard
            let plan = try? environment.planner.nextPlan(now: clock),
            let sessionID = try? environment.planner.startSession(from: plan, now: clock)
        else {
            return nil
        }

        for (position, planned) in plan.exercises.enumerated() {
            // O último exercício fica pulado para o resumo mostrar essa contagem.
            if position == plan.exercises.count - 1 {
                try? coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: planned.id, now: clock)
                continue
            }
            for index in 0..<max(0, planned.prescription.sets) {
                clock = clock.addingTimeInterval(180)
                _ = try? coordinator.logSet(
                    sessionID: sessionID,
                    sessionExerciseID: planned.id,
                    index: index,
                    load: planned.prescription.load ?? 40,
                    reps: planned.prescription.repMax,
                    rir: 2,
                    isWarmup: false,
                    now: clock
                )
            }
        }

        clock = clock.addingTimeInterval(300)
        if abandoned {
            try? coordinator.abandonSession(sessionID: sessionID, now: clock)
        } else {
            try? coordinator.finishSession(sessionID: sessionID, now: clock)
        }
        guard let session = coordinator.session(withID: sessionID) else {
            return nil
        }
        return Fixture(environment: environment, session: session)
    }
}

#Preview("Treino concluído") {
    if let fixture = SessionSummaryPreviewData.make(abandoned: false) {
        SessionSummaryView(session: fixture.session, onClose: {})
            .modelContainer(fixture.environment.modelContainer)
    } else {
        Text("Preview indisponível")
    }
}

#Preview("Treino abandonado") {
    if let fixture = SessionSummaryPreviewData.make(abandoned: true) {
        SessionSummaryView(session: fixture.session, onClose: {})
            .modelContainer(fixture.environment.modelContainer)
    } else {
        Text("Preview indisponível")
    }
}
#endif
