import SwiftData
import SwiftUI
import TrainerCore
import UniformTypeIdentifiers

/// Raiz da navegação (T1.1, M2-CONTRACT §7; SPEC F1/F4/F5; DESIGN §8): abas "Hoje" (Home),
/// "Histórico", "Programa" e "Ajustes", com a sessão ativa apresentada por cima em
/// `fullScreenCover`, o onboarding do primeiro launch em `.sheet` e o destaque do diálogo
/// (SPEC §7.11) numa folha própria. Cada aba traz a própria `NavigationStack`, então nada aqui
/// as aninha em outra.
///
/// O `AppEnvironment` chega pelo ambiente (`PersonalTrainerApp` injeta com `.environment`).
/// Como `@Environment` só é legível depois do `init`, quem guarda o `HomeViewModel` e o
/// `HealthViewModel` em `@State` é a view interna `RootTabs`, que recebe o ambiente por parâmetro.
///
/// Se o store persistente não abriu (`AppEnvironment.storeLoadError`), nenhuma aba aparece: só a
/// tela de erro, com "Tentar de novo" (`onRetryStoreLoad`, que monta o ambiente outra vez) e a
/// exportação dos arquivos de dados. Assim o app nunca parece uma instalação nova com o histórico
/// sumido, e nada é gravado sobre um store em memória que se perderia ao fechar.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    private let onRetryStoreLoad: (() -> Void)?

    init(onRetryStoreLoad: (() -> Void)? = nil) {
        self.onRetryStoreLoad = onRetryStoreLoad
    }

    var body: some View {
        if let storeLoadError = environment.storeLoadError {
            StoreLoadErrorView(
                message: storeLoadError,
                dataFiles: ModelContainerFactory.existingPersistentStoreFiles(),
                onRetry: onRetryStoreLoad
            )
        } else {
            RootTabs(environment: environment)
        }
    }
}

/// Tela bloqueante quando os dados não abriram (B1). Diz que nada foi apagado, pede para não
/// desinstalar, oferece tentar de novo e exportar os arquivos do store (o SQLite e a cópia feita
/// antes da migração) pelo compartilhamento do sistema, para guardar em Arquivos ou num computador.
private struct StoreLoadErrorView: View {
    let message: String
    let dataFiles: [URL]
    let onRetry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Não foi possível abrir seus dados", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Nada foi apagado: seus treinos continuam guardados neste iPhone. Não desinstale o app. Tente abrir de novo ou exporte os arquivos de dados para guardar uma cópia.")
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            if let onRetry {
                Button("Tentar de novo") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
            if !dataFiles.isEmpty {
                ShareLink(items: dataFiles) {
                    Label("Exportar arquivos de dados", systemImage: "square.and.arrow.up")
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// Destinos pedidos pelas respostas do diálogo (SPEC §7.11), numa folha só. Fora de `RootTabs`
/// para a conformidade a `Identifiable` não depender do isolamento da view.
private enum CoachDestination: Identifiable {
    /// C4 "Como renovar".
    case renewalHelp
    /// C6 "Ver evolução" (`ExerciseDefinition.id` e o nome para o título).
    case progress(exerciseID: UUID, name: String)

    var id: String {
        switch self {
        case .renewalHelp:
            return "renewalHelp"
        case .progress(let exerciseID, _):
            return "progress-\(exerciseID.uuidString)"
        }
    }
}

/// Abas + apresentação da sessão, do onboarding e do diálogo. Dona do `HomeViewModel`, do
/// `HealthViewModel` e do `SettingsViewModel` (um de cada por processo), da aba selecionada e do
/// que está apresentado.
///
/// A exportação do backup e os alertas do Ajustes ficam aqui, na raiz, e não dentro da aba: o
/// "Fazer backup" do diálogo (SPEC §7.11 C7) abre a exportação direto, de qualquer aba (B10), e o
/// resultado aparece onde a pessoa está.
///
/// Uma folha de cada vez: o destaque do diálogo só aparece quando nada mais está na tela
/// (`blocksCoachSheet`, liberado nos `onDismiss` do onboarding e da sessão, depois que a
/// animação de saída termina), porque o SwiftUI não abre uma folha sobre outra apresentação.
@MainActor
private struct RootTabs: View {
    /// Item do `fullScreenCover(item:)`: só o `uuid` da sessão; a view do fluxo busca o resto.
    private struct PresentedSession: Identifiable {
        let id: UUID
    }

    private enum RootTab: Hashable {
        case today
        case history
        case program
        case settings
    }

    /// Janela de sessões passadas ao painel de saúde (SPEC A5: encaixe do aeróbico longe dos dias
    /// de inferior só olha a semana corrente e a próxima).
    private static let recentSessionWindow: TimeInterval = 14 * 86_400

    private let environment: AppEnvironment
    private let coach: CoachService
    @State private var homeModel: HomeViewModel
    @State private var healthModel: HealthViewModel
    @State private var settingsModel: SettingsViewModel
    @State private var presentedSession: PresentedSession? = nil
    @State private var coachDestination: CoachDestination? = nil
    @State private var selectedTab: RootTab = .today
    /// Verdadeiro enquanto o onboarding ou a sessão estão na tela (ou ainda não se sabe, antes do
    /// `onAppear`): o destaque do diálogo espera.
    @State private var blocksCoachSheet = true
    /// A folha do destaque está na tela: um erro de resposta dado nela só aparece depois que ela
    /// fecha (duas apresentações ao mesmo tempo não abrem).
    @State private var isHighlightOnScreen = false
    @State private var isShowingCoachError = false
    @Environment(\.scenePhase) private var scenePhase

    /// Marca gravada pelo `OnboardingView` ao tocar "Começar" ou "Pular" (UserDefaults, sem
    /// SwiftData: M2-CONTRACT §2).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Controla a `.sheet` do onboarding. Copiado da marca no `onAppear` em vez de um `Binding`
    /// derivado: a marca só vira `true` dentro do onboarding, que fecha a sheet por `onDone`.
    @State private var isShowingOnboarding = false

    init(environment: AppEnvironment) {
        self.environment = environment
        self.coach = environment.coach
        let home = HomeViewModel(
            planner: environment.planner,
            coordinator: environment.coordinator,
            now: environment.now
        )
        self._homeModel = State(initialValue: home)
        // Depois de importar um backup, pedir uma semana leve ou mudar o modo casa, o plano mudou:
        // a Home relê. O diálogo relê ao voltar para "Hoje", longe dos alertas do Ajustes.
        self._settingsModel = State(initialValue: SettingsViewModel(
            backup: environment.backup,
            planner: environment.planner,
            now: environment.now,
            appVersion: SettingsViewModel.bundleVersion(.main),
            onDataChanged: { [home] in
                home.refresh()
            }
        ))
        self._healthModel = State(initialValue: HealthViewModel(
            reader: environment.healthReader,
            sessionsProvider: { [environment] in
                RootTabs.recentSessions(from: environment)
            },
            now: environment.now
        ))
    }

    var body: some View {
        // Leituras explícitas no corpo: a view passa a depender do destaque e do erro do diálogo
        // (Observation), e as folhas abaixo são recalculadas quando eles mudam.
        let highlight = coach.highlight
        let coachError = coach.errorMessage

        tabs
        // DESIGN §3: `accent` é o tint global (não há AccentColor no catálogo de imagens).
        .tint(Theme.accent)
        // Programa ativo, dias, objetivo e ajustes podem ter mudado nas outras abas: ao voltar
        // para "Hoje", a Home e o diálogo releem (além do próprio `onAppear` da Home).
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .today {
                homeModel.refresh()
                refreshCoach()
            }
        }
        // A Home não recebe `onAppear` ao dispensar um cover: relê aqui para mostrar a próxima
        // sessão recalculada (SPEC F4) e trocar Retomar → Começar. O diálogo relê ao fechar a
        // sessão (marcos pessoais, C6).
        .fullScreenCover(item: $presentedSession, onDismiss: {
            blocksCoachSheet = false
            homeModel.refresh()
            refreshCoach()
        }) { presented in
            SessionFlowView(sessionID: presented.id, environment: environment, onClose: {
                presentedSession = nil
            })
        }
        // Primeiro launch (T2.21, RF-35): escolher objetivo e programa. O onboarding desliga o
        // gesto de dispensa; toda saída passa por "Começar" ou "Pular", que gravam a marca.
        .sheet(isPresented: $isShowingOnboarding, onDismiss: {
            blocksCoachSheet = false
            refreshCoach()
        }) {
            OnboardingView(programs: environment.programs, references: environment.references, onDone: {
                isShowingOnboarding = false
                homeModel.refresh()
            })
        }
        // SPEC §7.11: destaque na abertura quando há algo novo e importante (C4, C1, C5, C2).
        // `highlightDidDismiss` no `onDismiss` é obrigatório: é ele que faz a navegação pedida na
        // folha ("Como renovar", "Começar", escolher programa) depois que ela fecha.
        .sheet(item: highlightBinding(highlight), onDismiss: {
            isHighlightOnScreen = false
            coach.highlightDidDismiss()
            if coach.errorMessage != nil {
                isShowingCoachError = true
            }
        }) { message in
            CoachHighlightSheet(
                message: message,
                references: environment.references,
                onAction: { action in
                    coach.handle(action, on: message)
                    homeModel.didHandleCoachAction(action)
                },
                applyDetail: coach.applySummary(for: message)
            )
            .onAppear {
                isHighlightOnScreen = true
            }
        }
        .sheet(item: $coachDestination) { destination in
            coachDestinationView(destination)
        }
        // Falha ao aplicar uma resposta do diálogo (feed ou destaque): a mensagem fica e o motivo
        // aparece aqui, num nó visível mesmo depois que a folha do destaque fecha.
        .alert("Não foi possível continuar", isPresented: $isShowingCoachError) {
            Button("OK", role: .cancel) {
                coach.isPresentingError = false
            }
        } message: {
            Text(coachError ?? "")
        }
        .onChange(of: coachError) { _, newValue in
            if newValue != nil && !isHighlightOnScreen {
                isShowingCoachError = true
            }
        }
        // Sugestões de saúde (C3) e tendências de recuperação (R6) chegam com a leitura do Saúde,
        // que termina depois da abertura.
        .onChange(of: healthModel.report) { _, _ in
            refreshCoach()
        }
        .onAppear {
            connectCoachNavigation()
            if hasCompletedOnboarding {
                blocksCoachSheet = false
            } else {
                isShowingOnboarding = true
            }
        }
        // Ao abrir e a cada volta ao primeiro plano. Nada aqui pede autorização (AGENTS §7).
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            let now = environment.now()
            // RF-13/RF-14 (CA2-1, CA2-2): o gravador revisita as sessões recentes: o treino do app
            // Exercício e as amostras de FC do relógio costumam chegar ao Saúde depois do
            // "Finalizar".
            if let recorder = environment.healthRecorder {
                Task {
                    await recorder.reconcileRecentSessions(now: now)
                }
            }
            // O diálogo espera a leitura do Saúde (se a pessoa conectou) para a revisão periódica
            // já sair com as tendências de recuperação (SPEC R6). Sem conexão, volta na hora.
            // É o único refresh que pode abrir um destaque novo (SPEC §7.11: "na abertura").
            let health = healthModel
            let coachService = coach
            Task { @MainActor in
                await health.loadIfStale()
                RootTabs.refresh(coach: coachService, health: health, allowsHighlight: true)
            }
        }
    }

    /// As quatro abas (DESIGN §8).
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            // Começar e Retomar chegam pelo mesmo caminho: `HomeViewModel.startSession()`
            // devolve o id da sessão nova ou o da que já estava em andamento (SPEC S3, RF-02),
            // inclusive após relançar o app com uma sessão aberta (CA1-4).
            HomeView(
                model: homeModel,
                coach: coach,
                health: healthModel,
                references: environment.references,
                onOpenSession: { sessionID in
                    openSession(sessionID)
                }
            )
            .tabItem {
                Label("Hoje", systemImage: "sun.max")
            }
            .tag(RootTab.today)

            // Apagar passa pelo coordinator (único caminho de escrita de sessão, AGENTS R4); a
            // Home relê porque a rotação e as cargas derivam do histórico (T2.13, ADR 003).
            HistoryListView(references: environment.references, onDeleteSession: { sessionID in
                try environment.coordinator.deleteSession(id: sessionID)
                homeModel.refresh()
            })
            .tabItem {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
            }
            .tag(RootTab.history)

            ProgramTabView(
                programs: environment.programs,
                catalog: environment.catalog,
                references: environment.references,
                now: environment.now
            )
            .tabItem {
                Label("Programa", systemImage: "list.bullet.rectangle")
            }
            .tag(RootTab.program)

            // O modelo é daqui (a Home relê pelo `onDataChanged` dele); a exportação e os alertas
            // do Ajustes são apresentados logo abaixo, na raiz.
            SettingsView(
                model: settingsModel,
                coach: coach,
                health: healthModel,
                references: environment.references
            )
            .tabItem {
                Label("Ajustes", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        // B10: o mesmo `fileExporter` serve ao botão "Exportar backup" do Ajustes e ao "Fazer
        // backup" do diálogo (C7). Rótulo `onCompletion:` explícito, como no Ajustes. O
        // `fileImporter` continua dentro da aba, em outro nível da hierarquia.
        .fileExporter(
            isPresented: $settingsModel.isExporterPresented,
            document: settingsModel.exportDocument,
            contentType: .json,
            defaultFilename: settingsModel.exportFileName,
            onCompletion: { result in
                settingsModel.handleExportResult(result)
            }
        )
        // Resultado de exportar, importar ou pedir semana leve, visível em qualquer aba.
        .alert(
            Text(settingsModel.alert?.title ?? ""),
            isPresented: $settingsModel.isAlertPresented,
            presenting: settingsModel.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    /// Item da folha do destaque: nada enquanto outra apresentação está na tela (onboarding,
    /// sessão, "Como renovar"), para o SwiftUI não tentar abrir uma folha sobre outra; o destaque
    /// continua guardado no `CoachService` e aparece quando ela fecha. Fechar a folha pelo gesto
    /// só dispensa o destaque: a mensagem continua na Home.
    private func highlightBinding(_ highlight: CoachMessage?) -> Binding<CoachMessage?> {
        let isBlocked = blocksCoachSheet || coachDestination != nil
        let service = coach
        return Binding<CoachMessage?>(
            get: {
                isBlocked ? nil : highlight
            },
            set: { newValue in
                if newValue == nil {
                    service.dismissHighlight()
                }
            }
        )
    }

    // MARK: - Sessão

    /// Abre o fluxo da sessão por cima das abas; o destaque do diálogo espera ele fechar.
    private func openSession(_ sessionID: UUID) {
        blocksCoachSheet = true
        presentedSession = PresentedSession(id: sessionID)
    }

    // MARK: - Diálogo

    /// Refresh depois de uma mudança na tela: atualiza o feed sem abrir destaque novo.
    private func refreshCoach() {
        RootTabs.refresh(coach: coach, health: healthModel, allowsHighlight: false)
    }

    /// SPEC §7.11: sugestões de saúde de hoje (C3), menos as dispensadas no detalhe do Saúde, e
    /// as tendências agregadas de recuperação para a revisão (R6). Sem relatório, `[]` e
    /// `.unknown`.
    static func refresh(coach: CoachService, health: HealthViewModel, allowsHighlight: Bool) {
        coach.refresh(
            healthSuggestions: health.visibleSuggestions,
            recovery: RecoveryContext.derived(from: health.report),
            allowsHighlight: allowsHighlight
        )
    }

    /// Sessões concluídas recentes para o painel de saúde (SPEC A5). Uma falha de leitura só
    /// deixa o encaixe do aeróbico sem essa informação.
    static func recentSessions(from environment: AppEnvironment) -> [SessionSummary] {
        let cutoff = environment.now().addingTimeInterval(-recentSessionWindow)
        let sessions = (try? environment.planner.completedSessionSummaries()) ?? []
        return sessions.filter { $0.startedAt >= cutoff }
    }

    /// Navegação pedida pelas respostas do diálogo. Fechamentos literais sobre `Binding`s e
    /// classes @MainActor: nenhum deles guarda a struct da view.
    private func connectCoachNavigation() {
        let tab = $selectedTab
        let destination = $coachDestination
        let session = $presentedSession
        let blocks = $blocksCoachSheet
        let home = homeModel
        let settings = settingsModel
        let catalog = environment.catalog

        // C7 "Fazer backup" (B10): abre a exportação direto, sem trocar de aba; o `fileExporter`
        // e o alerta do resultado estão na raiz. Do destaque, o `CoachService` só chama isto
        // depois que a folha fecha.
        coach.onBackupRequested = {
            settings.prepareExport()
        }
        // C4 "Como renovar".
        coach.onRenewalHelpRequested = {
            destination.wrappedValue = .renewalHelp
        }
        // C5 "Começar": o mesmo caminho do botão da Home.
        coach.onStartRequested = {
            tab.wrappedValue = .today
            if let sessionID = home.startSession() {
                blocks.wrappedValue = true
                session.wrappedValue = PresentedSession(id: sessionID)
            }
        }
        // C6 "Ver evolução".
        coach.onProgressRequested = { exerciseID in
            let name = (try? catalog.exercise(id: exerciseID))?.name ?? "Evolução"
            destination.wrappedValue = .progress(exerciseID: exerciseID, name: name)
        }
        // C2 "Trocar de programa" sem outro do mesmo objetivo: a pessoa escolhe.
        coach.onChooseProgramRequested = {
            tab.wrappedValue = .program
        }
    }

    @ViewBuilder
    private func coachDestinationView(_ destination: CoachDestination) -> some View {
        switch destination {
        case .renewalHelp:
            // A view já traz a própria `NavigationStack` e o botão "Fechar".
            RenewalHelpView(
                expiry: coach.provisioningExpiry,
                isReminderEnabled: coach.isExpiryReminderEnabled,
                onReminderChange: { enabled in
                    coach.setExpiryReminderEnabled(enabled)
                }
            )
        case .progress(let exerciseID, let name):
            NavigationStack {
                ExerciseProgressView(exerciseUUID: exerciseID, exerciseName: name)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fechar") {
                                coachDestination = nil
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return RootView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
