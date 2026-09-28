import SwiftUI
import TrainerCore

/// "Esta semana" (SPEC RF-49; DESIGN §9.1): 7 marcas de tinta, segunda a domingo — cheia nos dias
/// com sessão concluída com série, hoje com um fio fino em volta, os outros vazios. Só decorativa
/// (a leitura do VoiceOver é um elemento só, feita por quem chama com `LandingText`); sem números,
/// sem meta, sem cor de objetivo (DESIGN §9.6: nada de anel de progresso aqui).
struct WeekMarksView: View {
    /// Segunda (índice 0) a domingo (índice 6).
    let marks: [Bool]
    let todayIndex: Int

    private static let dotDiameter: CGFloat = 10
    private static let todayRingDiameter: CGFloat = 18

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PlanWeekday.allCases, id: \.self) { weekday in
                dot(for: weekday)
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(for weekday: PlanWeekday) -> some View {
        let index = weekday.rawValue
        let isFilled = index < marks.count && marks[index]
        let isToday = index == todayIndex
        return ZStack {
            if isToday {
                Circle()
                    .stroke(Theme.textSecondary, lineWidth: 1)
                    .frame(width: Self.todayRingDiameter, height: Self.todayRingDiameter)
            }
            Circle()
                .fill(isFilled ? Theme.inkMuted : Color.clear)
                .overlay(
                    Circle().stroke(Theme.line, lineWidth: isFilled ? 0 : 1)
                )
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
        }
        .frame(width: Self.todayRingDiameter, height: Self.todayRingDiameter)
    }
}

#Preview("WeekMarksView") {
    VStack(spacing: 24) {
        WeekMarksView(marks: [true, false, true, false, false, false, false], todayIndex: 2)
        WeekMarksView(marks: Array(repeating: false, count: 7), todayIndex: 0)
        WeekMarksView(marks: Array(repeating: true, count: 7), todayIndex: 6)
    }
    .padding()
    .background(Theme.background)
}
