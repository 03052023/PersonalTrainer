import SwiftUI

/// Descanso compacto, preso no topo da ficha (SPEC RF-05, RF-44 f; DESIGN §13 e §14): o ensō de 48 pt
/// que se pinta conforme o descanso passa, com o tempo restante no centro ("2:41"), "Descanso" (nos
/// intervalos do aeróbico, "Recuperação andando", SPEC §7.14 F1), "A seguir: …" e as pílulas "+30 s" e
/// "Pular". Lê tudo do `RestTimer` e some sozinha quando ele não está rodando; quem a exibe não precisa
/// condicionar nada.
///
/// Relógio: `TimelineView` periódico de 1 s. A cada `context.date` a view chama
/// `timer.tick(now:)` em `onChange` (fora do `body`, para não mutar estado durante a
/// renderização) e o `RestTimer` decide se o descanso terminou. Ao voltar do segundo plano o
/// `TimelineView` atualiza e o primeiro tick já fecha um descanso que venceu. O ensō avança no mesmo
/// ritmo de 1 s (docs/V23-UI-CONTRACT.md §3.2).
///
/// Haptic: `.sensoryFeedback(.success, trigger: timer.finishedCount)`, sem UIKit. O
/// modificador fica no `ZStack` externo, que continua montado (com tamanho zero) enquanto o
/// timer está parado: se ficasse no conteúdo condicional, seria removido na mesma
/// atualização em que o gatilho muda e a vibração se perderia. Por isso, mantenha a view
/// montada durante toda a sessão em vez de envolvê-la em `if timer.isRunning`.
@MainActor
struct RestTimerView: View {
    private let timer: RestTimer
    private let nextUp: String?
    private let title: String

    init(timer: RestTimer, nextUp: String? = nil, title: String = "Descanso") {
        self.timer = timer
        self.nextUp = nextUp
        self.title = title
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
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
                // Fundo opaco: a ficha rola por baixo do descanso sem aparecer através dele.
                .background(Theme.background)
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.success, trigger: timer.finishedCount)
    }

    // MARK: - Conteúdo

    private func content(now: Date) -> some View {
        let remaining = timer.remainingSeconds(at: now)
        let elapsed = RestTimerView.elapsedProgress(remaining: remaining, total: timer.totalSeconds)

        // Com Dynamic Type grande, as pílulas descem para uma segunda linha.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ring(remaining: remaining, elapsed: elapsed)
                labels
                Spacer(minLength: 4)
                buttons(now: now)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ring(remaining: remaining, elapsed: elapsed)
                    labels
                    Spacer(minLength: 0)
                }
                buttons(now: now)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .inkCard(cornerRadius: 14)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if let nextUp {
                Text(nextUp)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func buttons(now: Date) -> some View {
        HStack(spacing: 8) {
            Button {
                timer.add(seconds: 30, now: now)
            } label: {
                Text("+30 s")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adicionar 30 segundos de descanso")

            Button {
                timer.skip()
            } label: {
                Text("Pular")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pular descanso")
        }
    }

    /// O ensō pintado até a fração do descanso que já passou, com o restante em dígitos
    /// monoespaçados no centro.
    private func ring(remaining: Int, elapsed: Double) -> some View {
        ZStack {
            EnsoRingView(progress: elapsed, diameter: 48)
            Text(RestTimerView.timeText(seconds: remaining))
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
        }
        .frame(width: 48, height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), faltam \(remaining) segundos")
    }

    // MARK: - Formatação (estática para os testes)

    /// "1:32", "0:05", "12:00". Negativos exibem "0:00".
    static func timeText(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// Fração restante do descanso em 0…1. `total <= 0` ⇒ 0.
    static func progress(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(remaining) / Double(total)))
    }

    /// Fração do descanso que já passou, o quanto o ensō está pintado, em 0…1. `total <= 0` ⇒ 0.
    static func elapsedProgress(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return 1 - progress(remaining: remaining, total: total)
    }
}

#Preview("Rodando") {
    let timer = RestTimer(notifications: FakeNotificationScheduler())
    timer.start(seconds: 161, now: .now)
    return RestTimerView(timer: timer, nextUp: "A seguir: série 3 de Agachamento livre")
        .paperBackground()
}

#Preview("Recuperação andando · Dynamic Type AX3") {
    let timer = RestTimer(notifications: FakeNotificationScheduler())
    timer.start(seconds: 180, now: .now)
    return RestTimerView(timer: timer, nextUp: "A seguir: série 3", title: "Recuperação andando")
        .dynamicTypeSize(.accessibility3)
}

#Preview("Parado (não renderiza nada)") {
    RestTimerView(timer: RestTimer(notifications: FakeNotificationScheduler()))
        .padding()
}
