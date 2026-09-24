import SwiftData
import SwiftUI
import TrainerCore

/// Card "Esta semana" da Home (SPEC §7.4, RF-17, CA2-6; TASKS T2.7): quantas sessões
/// concluídas trabalharam cada grupo muscular como primário na semana, contra a meta, em
/// chips compactos ("Peito 1/2"), com o "Por quê?" da frequência (RF-32).
///
/// Só leitura: `@Query` é o único acesso a dados (ARCHITECTURE §3) e nada aqui escreve (R4).
/// A conta é de `WeeklyFrequency.report` (TrainerCore); aqui só se escolhe a semana e formata.
@MainActor
struct WeeklyFrequencyCard: View {
    @Query(sort: \WorkoutSessionModel.startedAt, order: .reverse)
    private var sessions: [WorkoutSessionModel]
    /// Metas por grupo e início da semana gravados pelo usuário (SPEC §7.4: "configurável").
    /// Linha única (ARCHITECTURE §5); se houver mais de uma, a escolha é determinística.
    @Query private var settingsRows: [UserSettingsModel]

    private let references: ReferenceCatalog

    init(references: ReferenceCatalog) {
        self.references = references
    }

    var body: some View {
        // `Date()` e `Calendar.current` aqui são aceitáveis: é só exibição, e "esta semana" é a
        // do relógio e do fuso do aparelho (SPEC §7.4). As regras de determinismo (SPEC P11,
        // AGENTS R3) valem para o motor e os serviços, que continuam recebendo `now`.
        let settings = settingsRows.min { $0.uuid.uuidString < $1.uuid.uuidString }
        let report = Self.report(
            sessions: sessions,
            now: Date(),
            calendar: Calendar.current,
            targets: settings?.weeklyTargets ?? [:],
            weekStartsOnMonday: settings?.weekStartsOnMonday ?? true
        )
        let entries = Self.visibleEntries(report)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Esta semana")
                        .font(.headline)
                    Text(Self.weekRangeText(report, calendar: Calendar.current))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                WhyButton(topic: "topic.frequency", catalog: references)
            }

            if entries.isEmpty {
                Text("Nenhum grupo muscular com meta semanal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(entries, id: \.muscle) { entry in
                        chip(entry)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Chip

    private func chip(_ entry: WeeklyFrequencyEntry) -> some View {
        let isMet = entry.completed >= entry.target
        return HStack(spacing: 6) {
            Text(Self.muscleName(entry.muscle))
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("\(entry.completed)/\(entry.target)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isMet ? Color.green : Color.primary)
        .background(
            (isMet ? Color.green : Color.secondary).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.accessibilityText(entry)))
    }

    // MARK: - Dados (funções puras, testadas em HomeViewModelTests)

    /// Relatório da semana que contém `now`. Só as sessões da semana passam pelo mapper, para
    /// não percorrer as séries do histórico inteiro a cada redesenho; a regra (concluída, ≥ 1
    /// série de trabalho, grupo primário, uma vez por sessão) continua em `WeeklyFrequency`.
    /// Metas: as de `UserSettingsModel.weeklyTargets` (meta 0 esconde o grupo) e, para os grupos
    /// sem meta gravada, o padrão 2×/semana (SPEC §7.4). A semana começa na segunda por padrão.
    static func report(
        sessions: [WorkoutSessionModel],
        now: Date,
        calendar: Calendar,
        targets: [MuscleGroup: Int] = [:],
        weekStartsOnMonday: Bool = true
    ) -> WeeklyFrequencyReport {
        let week = WeeklyFrequency.weekInterval(containing: now, weekStartsOnMonday: weekStartsOnMonday, calendar: calendar)
        let summaries = sessions
            .filter { $0.startedAt >= week.start && $0.startedAt < week.end }
            // `statusRaw` desconhecido (store corrompido) só deixa de contar; o painel é exibição.
            .compactMap { try? SessionSummaryMapper.summary(from: $0) }
        return WeeklyFrequency.report(
            sessions: summaries,
            targets: targets,
            defaultTarget: WeeklyFrequency.defaultTarget,
            now: now,
            weekStartsOnMonday: weekStartsOnMonday,
            calendar: calendar
        )
    }

    /// Só grupos com meta > 0, na ordem fixa de `MuscleGroup.allCases` (SPEC §7.4).
    static func visibleEntries(_ report: WeeklyFrequencyReport) -> [WeeklyFrequencyEntry] {
        report.entries.filter { $0.target > 0 }
    }

    /// "Peito 1/2" (CA2-6).
    static func chipText(_ entry: WeeklyFrequencyEntry) -> String {
        "\(muscleName(entry.muscle)) \(entry.completed)/\(entry.target)"
    }

    static func accessibilityText(_ entry: WeeklyFrequencyEntry) -> String {
        let sessionsText = entry.target == 1 ? "sessão" : "sessões"
        return "\(muscleName(entry.muscle)): \(entry.completed) de \(entry.target) \(sessionsText)"
    }

    /// Nomes dos grupos da SPEC §7.4 em pt-BR.
    static func muscleName(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: return "Peito"
        case .back: return "Costas"
        case .shoulders: return "Ombros"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .quads: return "Quadríceps"
        case .hamstrings: return "Posteriores"
        case .glutes: return "Glúteos"
        case .calves: return "Panturrilhas"
        case .core: return "Core"
        }
    }

    /// "22 set. – 28 set.". `weekEnd` é exclusivo (TASKS T2.3): o último dia exibido é
    /// `weekEnd − 1 dia`.
    static func weekRangeText(_ report: WeeklyFrequencyReport, calendar: Calendar) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: report.weekEnd)
            ?? report.weekEnd.addingTimeInterval(-86_400)
        let style = Date.FormatStyle(locale: Locale(identifier: "pt_BR"), calendar: calendar, timeZone: calendar.timeZone)
            .day()
            .month(.abbreviated)
        return "\(report.weekStart.formatted(style)) – \(lastDay.formatted(style))"
    }
}
