import SwiftUI
import TrainerCore

/// Aba Plano (SPEC RF-45; DESIGN §7, §8; mockup "Plano"), a antiga aba Programa: no topo o
/// objetivo com "Trocar objetivo"; "Sua semana" com um cartão por dia (o próximo marcado) para
/// consultar; por último, "Ajustar exercícios" (dias, exercícios e parâmetros, RF-16, RF-33,
/// RF-36) e o catálogo. Não lista programas: renomear, duplicar, apagar e trocar o objetivo de um
/// programa saíram da interface (o repositório continua com eles para o backup e o diálogo).
///
/// Nada aqui lê o `AppEnvironment` do ambiente nem escreve no `ModelContext` (AGENTS R4): os
/// serviços chegam por `init`. `now` é o único relógio real da aba (SPEC P11) e só serve para
/// perguntar ao planejador qual é o próximo dia; os parâmetros novos têm padrão para o integrador
/// poder chamar `ProgramTabView(programs:catalog:references:now:)`.
struct ProgramTabView: View {
    @State private var model: PlanTabModel
    @State private var isShowingGoalSheet = false
    /// Copiado ao abrir a folha: com sessão em andamento a troca fica bloqueada (RF-45).
    @State private var goalSheetBlocked = false
    private let programs: any ProgramRepositoring
    private let catalog: any CatalogRepositoring
    private let references: ReferenceCatalog

    /// DESIGN §9.1: a flor do topo tem cerca de 56 pt.
    private static let flowerSize: CGFloat = 56

    init(
        programs: any ProgramRepositoring,
        catalog: any CatalogRepositoring,
        references: ReferenceCatalog,
        now: @escaping () -> Date = { Date() },
        planner: (any SessionPlanning)? = nil,
        coordinator: (any SessionCoordinating)? = nil
    ) {
        self.programs = programs
        self.catalog = catalog
        self.references = references
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
                VStack(alignment: .leading, spacing: 20) {
                    content
                    links
                }
                .padding(16)
            }
            .background {
                Theme.background.ignoresSafeArea()
            }
            .navigationTitle("Plano")
            // Também dispara ao voltar de "Ajustar exercícios": a semana mostra o que foi gravado.
            .onAppear {
                model.refresh()
            }
            .sheet(isPresented: $isShowingGoalSheet, onDismiss: {
                model.refresh()
            }) {
                GoalSheet(
                    programs: programs,
                    catalog: catalog,
                    references: references,
                    mode: .change,
                    isSessionInProgress: goalSheetBlocked,
                    onFinish: { _ in
                        isShowingGoalSheet = false
                    }
                )
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
            header(for: program)
            week
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

    /// Flor, nome do objetivo, "3 dias por semana" e "Trocar objetivo".
    private func header(for program: ProgramTemplate) -> some View {
        let goal = program.effectiveGoal
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                FlowerView(activeGoal: goal, size: Self.flowerSize)
                    // O texto ao lado já diz o objetivo.
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.displayName)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Objetivo: \(goal.displayName). \(model.subtitle)."))
                Spacer(minLength: 0)
            }
            changeGoalButton(title: "Trocar objetivo")
        }
    }

    private func changeGoalButton(title: String) -> some View {
        Button {
            openGoalSheet()
        } label: {
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
        .accessibilityHint("Abre a lista de objetivos")
    }

    /// "Sua semana": um cartão por dia, com o próximo marcado.
    private var week: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sua semana")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if model.days.isEmpty {
                Text("Este plano ainda não tem dias.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.days, id: \.id) { day in
                dayCard(day)
            }
        }
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                changeGoalButton(title: "Escolher objetivo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Ajustar exercícios" (só com plano ativo) e "Catálogo de exercícios", por último.
    private var links: some View {
        VStack(spacing: 0) {
            if let program = model.activeProgram {
                NavigationLink {
                    ProgramDetailView(
                        programID: program.id,
                        programs: programs,
                        catalog: catalog,
                        references: references
                    )
                } label: {
                    linkRow("Ajustar exercícios")
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    // MARK: - Ações

    private func openGoalSheet() {
        goalSheetBlocked = model.isSessionInProgress
        isShowingGoalSheet = true
    }
}
