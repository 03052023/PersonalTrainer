import SwiftUI
import TrainerCore

/// Destinos da `NavigationStack` própria da aba Início (SPEC RF-49 ponto 4).
private enum LandingRoute: Hashable {
    case weeklyGoals
}

/// Aba "Início" (SPEC RF-49; DESIGN §9.1; docs/V23-UI-CONTRACT.md §4.3): a flor pintada, a saudação,
/// os objetivos ativos, "Esta semana" (que abre as Metas da semana) e o caminho para o treino de
/// hoje. Sem mensagem do dia, citação ou frase de efeito (decisão 20, itens 15 e 16).
///
/// `onOpenToday` seleciona a aba "Hoje"; `onOpenSession` abre a sessão em andamento pelo mesmo
/// caminho do "Retomar" de sempre. O modelo relê em `refresh()`; o integrador chama de novo ao
/// voltar para a aba e ao voltar ao primeiro plano (docs/V23-UI-CONTRACT.md §5).
///
/// Desde a 2.4 (docs/V24-CONTRACT.md §4.5): com `activities`, as Metas da semana ganham a seção "Fora do
/// app" (RF-53); o cartão "Hoje" mostra "Também hoje: …" quando há fixa de hoje sem "Feito" (RF-49).
struct LandingView: View {
    @Bindable private var model: LandingViewModel
    private let references: ReferenceCatalog
    private let onOpenToday: () -> Void
    private let onOpenSession: (UUID) -> Void
    /// `nil` (previews, testes): as Metas ficam sem a seção "Fora do app".
    private let activities: ActivitiesModel?

    init(
        model: LandingViewModel,
        references: ReferenceCatalog,
        onOpenToday: @escaping () -> Void,
        onOpenSession: @escaping (UUID) -> Void,
        activities: ActivitiesModel? = nil
    ) {
        self.model = model
        self.references = references
        self.onOpenToday = onOpenToday
        self.onOpenSession = onOpenSession
        self.activities = activities
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    weekBlock
                    pathCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                // Atrás de tudo e rola junto com o conteúdo (DESIGN §9.1).
                .background(alignment: .topTrailing) {
                    mountainWash
                }
            }
            .paperBackground()
            .navigationTitle("Início")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LandingRoute.self) { route in
                switch route {
                case .weeklyGoals:
                    WeeklyGoalsView(model: model, references: references, activities: activities)
                }
            }
        }
        .onAppear {
            model.refresh()
        }
    }

    // MARK: - Cabeçalho: aguada, data, flor, saudação e objetivos

    /// A aguada de montanha no canto de cima, à direita (DESIGN §9.1): cerca de 55 % da largura da
    /// tela e 140 pt de altura. Decorativa; o `GeometryReader` fica num `background`, então não
    /// muda o tamanho da coluna.
    private var mountainWash: some View {
        GeometryReader { proxy in
            MountainWashView()
                .frame(width: proxy.size.width * 0.55, height: 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            Text(model.dateText)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 12)

            FlowerView(activeGoals: model.activeGoals, size: 168)
                .publishesGoalFlowerAnchor()
                // RF-49 ponto 4: a flor fica escondida do VoiceOver; os objetivos já estão em texto.
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(model.greeting)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(LandingText.activeGoalsText(model.activeGoals))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - "Esta semana": marcas + frase, abre as Metas da semana

    private var weekBlock: some View {
        NavigationLink(value: LandingRoute.weeklyGoals) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Esta semana")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                WeekMarksView(marks: model.weekMarks, todayIndex: model.todayWeekdayIndex)
                Text(model.weekReadErrorMessage ?? model.weekSentence)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            model.weekReadErrorMessage
                ?? LandingText.weekMarksAccessibilityLabel(marks: model.weekMarks)
        )
        .accessibilityHint("Abre as Metas da semana")
    }

    // MARK: - Caminho para o treino de hoje

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hoje")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            Text(pathLabel)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let subtitle = pathSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            // SPEC RF-49, §7.17 X2 (DESIGN §9.1 ponto 3): linha pequena, só o fato.
            if let alsoToday = model.alsoTodayText {
                Text(alsoToday)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(pathButtonTitle, action: performPathAction)
                .buttonStyle(.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }

    private var pathLabel: String {
        switch model.pathState {
        case .inProgress(_, let label):
            return label
        case .todaySessions(let label, _):
            return label
        case .allDone:
            return "Tudo feito por hoje."
        case .restDay:
            return "Hoje é dia de descanso."
        case .noGoal:
            return "Escolha um objetivo para ver a sua primeira sessão."
        case .unavailable:
            return "Não foi possível ler a sessão de hoje."
        }
    }

    private var pathSubtitle: String? {
        guard case .todaySessions(_, let subtitle) = model.pathState else {
            return nil
        }
        return subtitle
    }

    private var pathButtonTitle: String {
        switch model.pathState {
        case .inProgress:
            return "Retomar a sessão"
        case .todaySessions:
            return "Ver a sessão de hoje"
        case .allDone, .restDay, .unavailable:
            return "Ver o dia"
        case .noGoal:
            return "Escolher um objetivo"
        }
    }

    private func performPathAction() {
        if case .inProgress(let sessionID, _) = model.pathState {
            onOpenSession(sessionID)
        } else {
            onOpenToday()
        }
    }
}
