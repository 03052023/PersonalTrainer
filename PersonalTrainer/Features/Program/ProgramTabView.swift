import SwiftUI
import TrainerCore

/// Aba Plano (SPEC RF-45, §7.15 M4, M8, M9; DESIGN §7, §8, §13; mockup "Plano"), a antiga aba
/// Programa: no topo o objetivo (ou os dois objetivos) com "Trocar objetivo"; o plano com a semana dele
/// para consultar (um cartão por dia, o próximo marcado); por último, "Ajustar exercícios" (dias,
/// exercícios e parâmetros, RF-16, RF-33, RF-36) e o catálogo. Não lista programas: renomear, duplicar,
/// apagar e trocar o objetivo de um programa saíram da interface.
///
/// Vários planos (2.3):
/// - com um plano, "Adicionar um plano" abre a folha "Seu objetivo" no modo de adicionar (M8);
/// - com dois, "Sua semana" (a semana ideal de `weekSchedule`, Seg a Dom, com o nome do dia de cada
///   sessão e "descanso" nos livres), "Seus dias" (os dias e as duas chaves, com a conferência antes de
///   gravar, M9) e, em cada plano, "Tirar este plano" com confirmação (M8).
///
/// Atividades fora do app (2.4, SPEC RF-53, §7.17 X2, X4; DESIGN §9.3): com o `ActivitiesModel`, a seção
/// "Atividades fixas" entra depois dos planos e antes de "Ajustar exercícios", e, com dois planos, cada
/// fixa aparece no dia dela em "Sua semana", depois das sessões.
///
/// Nada aqui lê o `AppEnvironment` do ambiente nem escreve no `ModelContext` (AGENTS R4): os serviços
/// chegam por `init`. `now` é o único relógio real da aba (SPEC P11); os parâmetros novos têm padrão
/// para o integrador poder chamar `ProgramTabView(programs:catalog:references:now:)`.
struct ProgramTabView: View {
    @State private var model: PlanTabModel
    @State private var isShowingGoalSheet = false
    @State private var goalSheetMode: GoalSheet.Mode = .change
    /// Copiado ao abrir a folha: com sessão em andamento a troca fica bloqueada (RF-45).
    @State private var goalSheetBlocked = false
    /// "Seus dias" (M9), numa folha própria.
    @State private var daysFlow: PlanFitFlowModel?
    @State private var isShowingDaysFlow = false
    /// Plano esperando a confirmação de "Tirar este plano" (M8).
    @State private var planPendingRemoval: ProgramTemplate?
    private let programs: any ProgramRepositoring
    private let catalog: any CatalogRepositoring
    private let references: ReferenceCatalog
    private let planner: (any SessionPlanning)?
    private let now: () -> Date
    /// `nil`: sem a seção "Atividades fixas" (previews e testes sem atividades).
    private let activities: ActivitiesModel?

    /// DESIGN §9.1: a flor do topo tem cerca de 56 pt.
    private static let flowerSize: CGFloat = 56
    /// Flor pequena de cada plano, com dois planos.
    private static let planFlowerSize: CGFloat = 30

    init(
        programs: any ProgramRepositoring,
        catalog: any CatalogRepositoring,
        references: ReferenceCatalog,
        now: @escaping () -> Date = { Date() },
        planner: (any SessionPlanning)? = nil,
        coordinator: (any SessionCoordinating)? = nil,
        activities: ActivitiesModel? = nil
    ) {
        self.programs = programs
        self.catalog = catalog
        self.references = references
        self.planner = planner
        self.now = now
        self.activities = activities
        self._model = State(initialValue: PlanTabModel(
            programs: programs,
            catalog: catalog,
            planner: planner,
            coordinator: coordinator,
            now: now
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                    fixedActivities
                    links
                }
                .padding(16)
            }
            .paperBackground()
            .navigationTitle("Plano")
            // Também dispara ao voltar de "Ajustar exercícios": a semana mostra o que foi gravado.
            .onAppear {
                model.refresh()
            }
            // Acrescentar, editar ou apagar uma fixa muda "Sua semana" (X4): o encaixe relê as fixas gravadas.
            .onChange(of: activities?.log.fixed) { _, _ in
                model.refresh()
            }
            .sheet(isPresented: $isShowingGoalSheet, onDismiss: {
                model.refresh()
            }) {
                GoalSheet(
                    programs: programs,
                    catalog: catalog,
                    references: references,
                    mode: goalSheetMode,
                    isSessionInProgress: goalSheetBlocked,
                    planner: planner,
                    now: now,
                    onFinish: { _ in
                        isShowingGoalSheet = false
                    }
                )
            }
            .sheet(isPresented: $isShowingDaysFlow, onDismiss: {
                daysFlow = nil
                model.refresh()
            }) {
                if let daysFlow {
                    NavigationStack {
                        PlanFitFlowView(
                            model: daysFlow,
                            references: references,
                            firstPageBackTitle: "Cancelar",
                            onCancel: {
                                isShowingDaysFlow = false
                            },
                            onDone: {
                                isShowingDaysFlow = false
                            }
                        )
                    }
                    .tint(Theme.accent)
                }
            }
            .confirmationDialog(
                removalTitle,
                isPresented: Binding(
                    get: { planPendingRemoval != nil },
                    set: { isPresented in
                        if !isPresented { planPendingRemoval = nil }
                    }
                ),
                titleVisibility: .visible,
                presenting: planPendingRemoval
            ) { program in
                Button(PlanWeekText.removeConfirm) {
                    model.removePlan(programID: program.id)
                    planPendingRemoval = nil
                }
                Button("Cancelar", role: .cancel) {}
            } message: { program in
                Text(removalMessage(for: program))
            }
            .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        if let program = model.activeProgram {
            header
            if model.hasTwoPlans {
                weekSection
                ForEach(model.activePrograms, id: \.id) { plan in
                    planSection(plan)
                }
            } else {
                singleWeek(for: program)
            }
        } else if !model.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if model.didFailToLoad {
            messageCard(
                title: "Não foi possível carregar o plano",
                text: "Saia da aba e volte para tentar de novo.",
                showsChooseButton: false
            )
        } else {
            messageCard(
                title: "Escolha um objetivo",
                text: "Cada objetivo tem o seu plano, com os dias e os exercícios de cada sessão.",
                showsChooseButton: true
            )
        }
    }

    /// "Atividades fixas" (2.4, DESIGN §9.3 ponto 3): depois dos planos e antes de "Ajustar exercícios".
    /// Também sem objetivo: a fixa pode nascer nas Metas ("Toda semana") e aparece na tela Hoje, então
    /// precisa de um lugar para ser editada ou apagada.
    @ViewBuilder
    private var fixedActivities: some View {
        if let activities, model.hasLoaded {
            FixedActivitiesSection(model: activities)
        }
    }

    /// Flor, nome do objetivo (ou "Hipertrofia + Cardio"), a linha de baixo e os botões da folha.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                FlowerView(activeGoals: model.activeGoals, size: Self.flowerSize)
                    // O texto ao lado já diz o objetivo.
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.titleText)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.hasTwoPlans {
                        Text(model.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(headerAccessibilityText))
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    headerButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    headerButtons
                }
            }
        }
    }

    @ViewBuilder
    private var headerButtons: some View {
        pillButton(title: "Trocar objetivo", hint: "Abre a lista de objetivos") {
            openGoalSheet(mode: .change)
        }
        if model.canAddPlan {
            pillButton(title: PlanWeekText.addPlanButton, hint: "Mostra o que muda e confere os seus dias") {
                openGoalSheet(mode: .add)
            }
        }
    }

    private var headerAccessibilityText: String {
        if model.hasTwoPlans {
            return "Objetivos: \(model.activeGoals.spokenDisplayName)."
        }
        return "Objetivo: \(model.titleText). \(model.spokenSubtitle)."
    }

    private func pillButton(title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accentSoft, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(hint))
    }

    /// Um plano só: "Sua semana" com um cartão por dia, como na 2.2.
    private func singleWeek(for program: ProgramTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(PlanWeekText.yourWeekTitle)
            dayCards(for: program)
        }
    }

    /// Com dois planos: "Sua semana" (M4), os avisos e "Seus dias" (M9).
    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(PlanWeekText.yourWeekTitle)
            if !model.weekRows.isEmpty {
                WeekScheduleView(rows: model.weekRows, notes: model.weekNotes)
                    .padding(14)
                    .inkCard()
            } else if model.showsNotFit {
                Text(PlanWeekText.notFitInPlanTab)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if model.didFailToLoadWeek {
                Text(PlanWeekText.checkFailed)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.canEditDays {
                pillButton(title: PlanWeekText.yourDaysTitle, hint: "Muda os dias em que você pode treinar") {
                    openDaysFlow()
                }
            }
        }
    }

    /// Com dois planos: a flor pequena, o nome, os dias do plano e "Tirar este plano".
    private func planSection(_ program: ProgramTemplate) -> some View {
        let goal = program.effectiveGoal
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                FlowerView(activeGoal: goal, size: Self.planFlowerSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.displayName)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.planSubtitle(for: program))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Plano de \(goal.displayName). \(model.spokenPlanSubtitle(for: program))."))
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            dayCards(for: program)
            Button {
                planPendingRemoval = program
            } label: {
                Text(PlanWeekText.removePlanButton)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canRemovePlans)
            .opacity(model.canRemovePlans ? 1 : 0.5)
            .accessibilityHint(Text("Pede confirmação. O outro plano continua."))
        }
    }

    @ViewBuilder
    private func dayCards(for program: ProgramTemplate) -> some View {
        let days = model.orderedDays(of: program)
        if days.isEmpty {
            Text("Este plano ainda não tem dias.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        ForEach(days, id: \.id) { day in
            dayCard(day)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func dayCard(_ day: ProgramDayTemplate) -> some View {
        let exercises = model.exerciseList(for: day)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.isNext(day) {
                    Text("próxima")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.accentSoft, in: Capsule())
                }
            }
            if !exercises.isEmpty {
                Text(exercises)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard(cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.accessibilityText(for: day)))
    }

    /// Sem plano ativo (ou falha de leitura): texto e, quando dá, o botão que abre a folha.
    private func messageCard(title: String, text: String, showsChooseButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                FlowerView(activeGoal: nil, size: Self.flowerSize)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsChooseButton {
                pillButton(title: "Escolher objetivo", hint: "Abre a lista de objetivos") {
                    openGoalSheet(mode: .change)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Ajustar exercícios" (um por plano ativo) e "Catálogo de exercícios", por último.
    private var links: some View {
        VStack(spacing: 0) {
            ForEach(model.activePrograms, id: \.id) { program in
                NavigationLink {
                    ProgramDetailView(
                        programID: program.id,
                        programs: programs,
                        catalog: catalog,
                        references: references
                    )
                } label: {
                    linkRow(adjustTitle(for: program))
                }
                .buttonStyle(.plain)
                Divider()
                    .padding(.leading, 14)
            }
            NavigationLink {
                CatalogListView(catalog: catalog)
            } label: {
                linkRow("Catálogo de exercícios")
            }
            .buttonStyle(.plain)
        }
        .inkCard(cornerRadius: 12)
    }

    /// "Ajustar exercícios"; com dois planos, "Ajustar exercícios · Cardio".
    private func adjustTitle(for program: ProgramTemplate) -> String {
        model.hasTwoPlans
            ? "Ajustar exercícios · \(program.effectiveGoal.displayName)"
            : "Ajustar exercícios"
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    // MARK: - Tirar este plano (M8)

    private var removalTitle: String {
        guard let program = planPendingRemoval else {
            return PlanWeekText.removePlanButton
        }
        return PlanWeekText.removeQuestion(program.effectiveGoal)
    }

    private func removalMessage(for program: ProgramTemplate) -> String {
        guard let kept = model.remainingProgram(after: program) else {
            return ""
        }
        return PlanWeekText.removeMessage(kept: kept.effectiveGoal)
    }

    // MARK: - Ações

    private func openGoalSheet(mode: GoalSheet.Mode) {
        goalSheetMode = mode
        goalSheetBlocked = model.isSessionInProgress
        isShowingGoalSheet = true
    }

    private func openDaysFlow() {
        guard let flow = model.makeDaysFlow() else { return }
        daysFlow = flow
        isShowingDaysFlow = true
    }
}
