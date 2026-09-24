import SwiftUI
import TrainerCore

/// Cartão "Sessão de hoje" da Home (SPEC F1, RF-01; DESIGN §9.2): dia em destaque (menu para
/// escolher outro dia, SPEC S4 / T2.14), nome do programa, número de exercícios e duração
/// estimada ("≈ 45 min", B7), o interruptor "Em casa" (SPEC RF-42), a faixa que diz por que esta
/// sessão (`PlanBanner`, CA4-5), a faixa "Em casa" com os avisos do modo casa (§7.13 H2), selo do
/// objetivo com o símbolo dele (DESIGN §8) e "Por quê?" (SPEC §7.9, RF-32), e uma
/// `PrescriptionRow` por exercício, na ordem do plano.
///
/// View pura: a escolha de dia e o interruptor saem pelos fechamentos e quem planeja é o
/// `HomeViewModel`.
struct PlanCard: View {
    let plan: SessionPlan
    let days: [ProgramDayTemplate]
    /// `nil` = próximo da rotação; senão, o dia escolhido à mão.
    let selectedDayID: UUID?
    let goal: ProgramGoal?
    let references: ReferenceCatalog
    /// Falso com treino em andamento: o botão só retoma, então trocar o dia não teria efeito.
    let canChooseDay: Bool
    /// Estado do interruptor "Em casa": a chave gravada (SPEC RF-42), não o plano na tela.
    let isHomeModeOn: Bool
    /// Ligar ou desligar o modo casa; `nil` esconde o interruptor (previews, cartões sem ação).
    let onToggleHomeMode: ((Bool) -> Void)?
    let onSelectDay: (UUID) -> Void
    let onSelectAutomatic: () -> Void

    init(
        plan: SessionPlan,
        days: [ProgramDayTemplate],
        selectedDayID: UUID?,
        goal: ProgramGoal?,
        references: ReferenceCatalog,
        canChooseDay: Bool = true,
        isHomeModeOn: Bool = false,
        onToggleHomeMode: ((Bool) -> Void)? = nil,
        onSelectDay: @escaping (UUID) -> Void,
        onSelectAutomatic: @escaping () -> Void
    ) {
        self.plan = plan
        self.days = days
        self.selectedDayID = selectedDayID
        self.goal = goal
        self.references = references
        self.canChooseDay = canChooseDay
        self.isHomeModeOn = isHomeModeOn
        self.onToggleHomeMode = onToggleHomeMode
        self.onSelectDay = onSelectDay
        self.onSelectAutomatic = onSelectAutomatic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if onToggleHomeMode != nil {
                homeModeToggle
            }
            if let banner = PlanBanner.make(for: plan) {
                bannerView(banner)
            }
            if plan.isHomeMode {
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedDayID == nil ? "Sessão de hoje" : "Sessão escolhida")
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
            Text(Self.detailText(for: plan))
                .font(.footnote)
                .foregroundStyle(.secondary)
                // "≈" não tem leitura boa no VoiceOver; a versão falada diz "cerca de".
                .accessibilityLabel(Text(Self.detailAccessibilityText(for: plan)))
            if let goal {
                goalBadge(goal)
                    .padding(.top, 4)
            }
        }
    }

    /// Selo do objetivo do programa (SPEC §7.9) com o símbolo e a cor dele (DESIGN §4, §8: nada
    /// de `target`) e o "Por quê?" do objetivo (RF-32).
    private func goalBadge(_ goal: ProgramGoal) -> some View {
        HStack(spacing: 8) {
            Label(goal.displayName, systemImage: goal.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(goal.color.opacity(0.15), in: Capsule())
                .foregroundStyle(goal.color)
                .accessibilityLabel(Text("Objetivo: \(goal.displayName)"))
            WhyButton(topic: goal.referenceTopic, catalog: references)
        }
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
        .accessibilityHint(Text("Troca os exercícios da sessão por equivalentes que dá para fazer em casa. O programa não muda."))
    }

    /// Faixa "Em casa" (SPEC RF-42: "o cartão do dia mostra 'Em casa'") com os avisos de
    /// exercícios que saíram da sessão (§7.13 H2). Mesmo tom calmo da faixa do motivo.
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
    static let homeModeSummary = "Exercícios com o peso do corpo ou objetos de casa. O programa continua o mesmo."

    /// "1 exercício", "5 exercícios".
    static func exerciseCountText(_ count: Int) -> String {
        count == 1 ? "1 exercício" : "\(count) exercícios"
    }

    /// "≈ 45 min" (DESIGN §9.2, B7); `nil` sem estimativa (dia sem exercícios).
    static func durationText(minutes: Int) -> String? {
        minutes > 0 ? "≈ \(minutes) min" : nil
    }

    /// "Completo · 5 exercícios · ≈ 45 min".
    static func detailText(for plan: SessionPlan) -> String {
        var parts = [plan.programName, exerciseCountText(plan.exercises.count)]
        if let duration = durationText(minutes: plan.estimatedMinutes) {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }

    /// Leitura do VoiceOver: "Completo, 5 exercícios, cerca de 45 minutos".
    static func detailAccessibilityText(for plan: SessionPlan) -> String {
        var parts = [plan.programName, exerciseCountText(plan.exercises.count)]
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
                PrescriptionRow(exercise: exercise, references: references)
                    .padding(.vertical, 10)
            }
        }
    }
}
