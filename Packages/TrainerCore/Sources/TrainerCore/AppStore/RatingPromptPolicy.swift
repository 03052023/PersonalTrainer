import Foundation

/// Decide se o app pede avaliação na App Store (SPEC §7.18 L3, decisão do dono: "do jeito menos invasivo
/// possível e só depois do cara usar o app por uma semana"). Função pura: datas, contagens, versões e "veio
/// da loja" chegam por parâmetro, sem `Date()` e sem calendário (AGENTS R3, SPEC §7.7). Só diz se pode
/// pedir; quem mostra a caixa do sistema e grava o pedido é o app.
public enum RatingPromptPolicy {
    /// L3 (a): uma semana desde a primeira sessão concluída.
    public static let minimumDaysSinceFirstSession: Int = 7
    /// L3 (b): pelo menos 3 sessões concluídas, contando a que acabou de terminar.
    public static let minimumCompletedSessions: Int = 3
    /// L3 (d): pelo menos 120 dias desde o último pedido.
    public static let minimumDaysBetweenRequests: Int = 120
    /// Os dias da L3 são períodos de 24 h, sem calendário: horário de verão e fuso não mudam a conta.
    public static let secondsPerDay: TimeInterval = 86_400

    /// `true` só quando valem todas as condições da L3:
    /// - o app veio da loja (no build de desenvolvimento o iOS mostraria a caixa sempre);
    /// - a sessão que acabou de terminar foi concluída, sem erro de gravação nem do Saúde (c);
    /// - há pelo menos `minimumCompletedSessions` sessões concluídas (b);
    /// - passaram pelo menos `minimumDaysSinceFirstSession` × 24 h desde o início da primeira (a);
    /// - a versão atual não é vazia e o app ainda não pediu nela (d);
    /// - nunca pediu, ou passaram pelo menos `minimumDaysBetweenRequests` × 24 h desde o último pedido (d).
    ///   Um último pedido no futuro (relógio do aparelho mudado) dá intervalo negativo e não pede.
    public static func shouldRequest(_ input: RatingPromptInput, now: Date) -> Bool {
        guard input.isStoreInstall, input.sessionEnding == .completed else {
            return false
        }
        guard input.completedSessionCount >= minimumCompletedSessions else {
            return false
        }
        guard let first = input.firstCompletedSessionStart,
              now.timeIntervalSince(first) >= TimeInterval(minimumDaysSinceFirstSession) * secondsPerDay
        else {
            return false
        }
        let version = input.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty, input.lastRequestVersion != input.currentVersion else {
            return false
        }
        if let lastRequestAt = input.lastRequestAt {
            guard now.timeIntervalSince(lastRequestAt) >= TimeInterval(minimumDaysBetweenRequests) * secondsPerDay else {
                return false
            }
        }
        return true
    }

    /// "Concluída" do L3: `status == .completed` e `workingSetCount > 0` (a mesma conta das Metas, W2).
    /// Abandonada, em andamento ou concluída sem nenhuma série de trabalho não conta.
    public static func countsAsCompleted(_ session: SessionSummary) -> Bool {
        session.status == .completed && session.workingSetCount > 0
    }

    /// Início da primeira sessão concluída (L3 a), qualquer que seja a ordem da lista; `nil` sem nenhuma.
    public static func firstCompletedSessionStart(in sessions: [SessionSummary]) -> Date? {
        sessions.filter { countsAsCompleted($0) }.map(\.startedAt).min()
    }

    /// Quantas sessões da lista contam como concluídas (L3 b).
    public static func completedSessionCount(in sessions: [SessionSummary]) -> Int {
        sessions.filter { countsAsCompleted($0) }.count
    }
}
