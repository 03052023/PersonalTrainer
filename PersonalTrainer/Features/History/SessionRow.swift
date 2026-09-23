import SwiftUI
import TrainerCore

/// Linha da lista de histórico: dia do programa, data, duração e séries de trabalho (CA1-7).
///
/// Só leitura: recebe o modelo e formata; nada aqui escreve no `ModelContext` (R4).
@MainActor
struct SessionRow: View {
    let session: WorkoutSessionModel

    init(session: WorkoutSessionModel) {
        self.session = session
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.programDayName)
                    .font(.headline)
                Spacer()
                if isAbandoned {
                    Text("Abandonado")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }
            Text(DateFormatting.shortDate(session.startedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var isAbandoned: Bool {
        session.statusRaw == SessionStatus.abandoned.rawValue
    }

    /// "1 h 05 min · 12 séries". Conta só séries de trabalho (SPEC P1, RF-12).
    private var summaryText: String {
        let stats = SessionStats.compute(
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exerciseSets: session.exercises
                .sorted { $0.order < $1.order }
                .map { exercise in
                    exercise.sets
                        .sorted { $0.index < $1.index }
                        .map { HistoryMapper.setResult(from: $0) }
                }
        )
        let count = stats.workingSetCount
        let setsText = count == 1 ? "1 série" : "\(count) séries"
        return "\(DateFormatting.duration(stats.duration)) · \(setsText)"
    }
}
