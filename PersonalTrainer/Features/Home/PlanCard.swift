import SwiftUI
import TrainerCore

/// Cartão "Hoje" da Home (SPEC RF-01, RF-45, RF-46; DESIGN §9.2; docs/V22-CONTRACT.md §3.3): o
/// rótulo pequeno "Hoje" ("Sessão escolhida" quando o dia foi escolhido à mão), o dia em destaque
/// (menu para escolher outro, SPEC S4), "5 exercícios · ≈ 55 min" com a chave "Em casa" na mesma
/// linha (`ViewThatFits`, para caber em Dynamic Type grande), a faixa que diz por que esta sessão
/// (`PlanBanner`, CA4-5) e a faixa "Em casa" só quando há avisos (§7.13 H2), e uma
/// `PrescriptionRow` por exercício, na ordem do plano.
///
/// Sem selo do objetivo nem nome do programa: o objetivo já está no topo da Home (SPEC RF-45), e
/// só cada tela responde a uma pergunta (DESIGN §9).
///
/// View pura: a escolha de dia, o interruptor e a linha tocada saem pelos fechamentos; quem
/// planeja é o `HomeViewModel`.
struct PlanCard: View {
    let plan: SessionPlan
    let days: [ProgramDayTemplate]
    /// `nil` = próximo da rotação; senão, o dia escolhido à mão.
    let selectedDayID: UUID?
    let references: ReferenceCatalog
    /// Falso com treino em andamento: o botão só retoma, então trocar o dia não teria efeito.
    let canChooseDay: Bool
    /// Estado do interruptor "Em casa": a chave gravada (SPEC RF-42), não o plano na tela.
    let isHomeModeOn: Bool
    /// Ligar ou desligar o modo casa; `nil` esconde o interruptor (previews, cartões sem ação).
    let onToggleHomeMode: ((Bool) -> Void)?
    let onSelectDay: (UUID) -> Void
    let onSelectAutomatic: () -> Void
    /// Tocar no nome ou na meta de um exercício (SPEC RF-47): abre "Informações do exercício".
    let onSelectExercise: (PlannedExercise) -> Void
    /// Com dois planos (SPEC §7.15 M6), o rótulo pequeno do cartão diz de qual plano ele é
    /// ("Cardio"); `nil` = "Hoje" / "Sessão escolhida", como na 2.2.
    let customTitle: String?
    /// Com dois planos, o detalhe do cardio ("30 min", `TodayPlansText`); `nil` = o de sempre.
    let customDetail: String?
    let customDetailSpoken: String?

    init(
        plan: SessionPlan,
        days: [ProgramDayTemplate],
        selectedDayID: UUID?,
        references: ReferenceCatalog,
        canChooseDay: Bool = true,
        isHomeModeOn: Bool = false,
        onToggleHomeMode: ((Bool) -> Void)? = nil,
        onSelectDay: @escaping (UUID) -> Void,
        onSelectAutomatic: @escaping () -> Void,
        onSelectExercise: @escaping (PlannedExercise) -> Void = { _ in },
        customTitle: String? = nil,
        customDetail: String? = nil,
        customDetailSpoken: String? = nil
    ) {
        self.plan = plan
        self.days = days
        self.selectedDayID = selectedDayID
        self.references = references
        self.canChooseDay = canChooseDay
        self.isHomeModeOn = isHomeModeOn
        self.onToggleHomeMode = onToggleHomeMode
        self.onSelectDay = onSelectDay
        self.onSelectAutomatic = onSelectAutomatic
        self.onSelectExercise = onSelectExercise
        self.customTitle = customTitle
        self.customDetail = customDetail
        self.customDetailSpoken = customDetailSpoken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let banner = PlanBanner.make(for: plan) {
                bannerView(banner)
            }
            if !plan.homeNotices.isEmpty {
                homeModeBand
            }
            if plan.exercises.isEmpty {
                Text(HomeViewModel.emptyDayMessage(for: plan))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                exerciseList
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }

    /// "Hoje", "Sessão escolhida" ou, com dois planos, o objetivo do cartão.
    private var titleText: String {
        if let customTitle {
            return customTitle
        }
        return selectedDayID == nil ? "Hoje" : "Sessão escolhida"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            DayPickerMenu(
                dayName: plan.programDayName,
                days: days,
                selectedDayID: selectedDayID,
                isEnabled: canChooseDay,
                onSelectDay: onSelectDay,
                onSelectAutomatic: onSelectAutomatic
            )
            detailLine
        }
    }

    /// "5 exercícios · ≈ 55 min" e "Em casa" na mesma linha (DESIGN §9.2); em Dynamic Type
    /// grande, a chave desce para a linha de baixo (`ViewThatFits`, docs/V22-CONTRACT.md §3.3).
    @ViewBuilder
    private var detailLine: some View {
        if onToggleHomeMode != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    detailText
                    Spacer(minLength: 8)
                    homeModeToggle
                }
                VStack(alignment: .leading, spacing: 6) {
                    detailText
                    homeModeToggle
                }
            }
        } else {
            detailText
        }
    }

    private var detailText: some View {
        Text(customDetail ?? Self.detailText(for: plan))
            .font(.footnote)
            .foregroundStyle(.secondary)
            // "≈" não tem leitura boa no VoiceOver; a versão falada diz "cerca de".
            .accessibilityLabel(Text(customDetailSpoken ?? Self.detailAccessibilityText(for: plan)))
    }

    /// Faixa calma em `accentSoft` (DESIGN §3, §9.3): semana leve e frequência fazem parte do
    /// plano, então nada de vermelho nem de tom de alerta.
    private func bannerView(_ banner: PlanBanner) -> some View {
        Label(banner.text, systemImage: banner.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Interruptor "Em casa" (SPEC RF-42). Os fechamentos leem as propriedades do cartão, sem
    /// capturar nada além dele. Com uma sessão em andamento fica desabilitado, como a escolha do
    /// dia: "Retomar" abre a sessão como ela começou, e trocar aqui só mudaria o cartão.
    private var homeModeToggle: some View {
        Toggle(
            isOn: Binding<Bool>(
                get: { isHomeModeOn },
                set: { enabled in
                    onToggleHomeMode?(enabled)
                }
            )
        ) {
            Label("Em casa", systemImage: "house")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Theme.accent)
        .disabled(!canChooseDay)
        .fixedSize()
        .accessibilityHint(Text("Troca os exercícios da sessão por equivalentes que dá para fazer em casa. O programa não muda."))
    }

    /// Faixa "Em casa" (SPEC RF-42) com os avisos de exercícios que saíram da sessão (§7.13 H2).
    /// Só aparece quando há aviso: o interruptor já mostra o modo ligado na linha de cima.
    private var homeModeBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Em casa", systemImage: "house")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(Self.homeModeSummary)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
            ForEach(Array(plan.homeNotices.enumerated()), id: \.offset) { _, notice in
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Textos (pt-BR)

    /// Explicação curta da faixa "Em casa" (DESIGN §6: frase curta, o porquê e a autonomia).
    static let homeModeSummary = "Exercícios com o peso do corpo ou objetos de casa. O plano continua o mesmo."

    // Funções puras, `nonisolated`: a `TodayPlansText` (fora do `MainActor`) e o Início usam o mesmo detalhe
    // do cartão (RF-49, B8), sem o aviso de isolamento do Swift 6.

    /// "1 exercício", "5 exercícios".
    nonisolated static func exerciseCountText(_ count: Int) -> String {
        count == 1 ? "1 exercício" : "\(count) exercícios"
    }

    /// "≈ 45 min" (DESIGN §9.2, B7); `nil` sem estimativa (dia sem exercícios).
    nonisolated static func durationText(minutes: Int) -> String? {
        minutes > 0 ? "≈ \(minutes) min" : nil
    }

    /// "5 exercícios · ≈ 55 min", sem o nome do programa (SPEC RF-45: o objetivo já é o plano).
    nonisolated static func detailText(for plan: SessionPlan) -> String {
        var parts = [exerciseCountText(plan.exercises.count)]
        if let duration = durationText(minutes: plan.estimatedMinutes) {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }

    /// Leitura do VoiceOver: "5 exercícios, cerca de 55 minutos".
    nonisolated static func detailAccessibilityText(for plan: SessionPlan) -> String {
        var parts = [exerciseCountText(plan.exercises.count)]
        if plan.estimatedMinutes == 1 {
            parts.append("cerca de 1 minuto")
        } else if plan.estimatedMinutes > 1 {
            parts.append("cerca de \(plan.estimatedMinutes) minutos")
        }
        return parts.joined(separator: ", ")
    }

    private var exerciseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                if index > 0 {
                    Divider()
                }
                PrescriptionRow(
                    index: index,
                    exercise: exercise,
                    references: references,
                    onSelect: { onSelectExercise(exercise) }
                )
                .padding(.vertical, 10)
            }
        }
    }
}
