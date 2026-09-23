import SwiftUI

/// Timer de descanso compacto (RF-05, TASKS T1.7): anel de progresso com o tempo restante
/// ("1:32"), rótulo "Descanso" e botões "+30 s" / "Pular". Lê tudo do `RestTimer` e some
/// sozinha quando ele não está rodando; quem a exibe não precisa condicionar nada.
///
/// Relógio: `TimelineView` periódico de 1 s. A cada `context.date` a view chama
/// `timer.tick(now:)` em `onChange` (fora do `body`, para não mutar estado durante a
/// renderização) e o `RestTimer` decide se o descanso terminou. Ao voltar do segundo plano o
/// `TimelineView` atualiza e o primeiro tick já fecha um descanso que venceu.
///
/// Haptic: `.sensoryFeedback(.success, trigger: timer.finishedCount)`, sem UIKit. O
/// modificador fica no `ZStack` externo, que continua montado (com tamanho zero) enquanto o
/// timer está parado: se ficasse no conteúdo condicional, seria removido na mesma
/// atualização em que o gatilho muda e a vibração se perderia. Por isso, mantenha a view
/// montada durante toda a sessão em vez de envolvê-la em `if timer.isRunning`.
@MainActor
struct RestTimerView: View {
    private let timer: RestTimer

    init(timer: RestTimer) {
        self.timer = timer
    }

    var body: some View {
        ZStack {
            if timer.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(now: context.date)
                        .onChange(of: context.date, initial: true) { _, now in
                            timer.tick(now: now)
                        }
                }
            }
        }
        .sensoryFeedback(.success, trigger: timer.finishedCount)
    }

    // MARK: - Conteúdo

    private func content(now: Date) -> some View {
        let remaining = timer.remainingSeconds(at: now)
        let progress = RestTimerView.progress(remaining: remaining, total: timer.totalSeconds)

        return HStack(spacing: 16) {
            ring(remaining: remaining, progress: progress)

            VStack(alignment: .leading, spacing: 2) {
                Text("Descanso")
                    .font(.headline)
                Text("Próxima série")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                timer.add(seconds: 30, now: now)
            } label: {
                Text("+30 s")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Adicionar 30 segundos de descanso")

            Button {
                timer.skip()
            } label: {
                Text("Pular")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Pular descanso")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Anel que esvazia conforme o tempo passa, com o restante em dígitos monoespaçados no centro.
    private func ring(remaining: Int, progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Text(RestTimerView.timeText(seconds: remaining))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Descanso, faltam \(remaining) segundos")
    }

    // MARK: - Formatação (estática para os testes)

    /// "1:32", "0:05", "12:00". Negativos exibem "0:00".
    static func timeText(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// Fração restante do anel em 0…1. `total <= 0` ⇒ 0.
    static func progress(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(remaining) / Double(total)))
    }
}

#Preview("Rodando") {
    let timer = RestTimer(notifications: FakeNotificationScheduler())
    timer.start(seconds: 92, now: .now)
    return RestTimerView(timer: timer)
        .padding()
}

#Preview("Parado (não renderiza nada)") {
    RestTimerView(timer: RestTimer(notifications: FakeNotificationScheduler()))
        .padding()
}
