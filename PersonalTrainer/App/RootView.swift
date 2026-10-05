import SwiftData
import SwiftUI
import TrainerCore
import UIKit
import UniformTypeIdentifiers

/// Raiz da navegação (T1.1, M2-CONTRACT §7; SPEC F1/F4/F5, RF-49, RF-50; DESIGN §8): abas
/// "Início" (Landing, a primeira desde a 2.3), "Hoje" (Home), "Histórico", "Plano" e "Ajustes", com
/// a abertura a frio por cima das abas, a sessão ativa apresentada por cima em `fullScreenCover`, o
/// onboarding do primeiro launch em `.sheet`, a troca de objetivo pelo topo da tela Hoje (SPEC
/// RF-45) em `.sheet` e o destaque do diálogo (SPEC §7.11) numa folha própria. Cada aba traz a
/// própria `NavigationStack`, então nada aqui as aninha em outra.
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
    /// SPEC RF-50: a abertura roda só na abertura a frio. Fica aqui, e não em `RootTabs`, para não
    /// voltar quando as abas aparecem depois de "Tentar de novo" na tela de erro do store (a
    /// abertura nunca cobre essa tela).
    @State private var isLaunchPending = true

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
            .onAppear {
                isLaunchPending = false
            }
        } else {
            RootTabs(environment: environment, isLaunchPending: $isLaunchPending)
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
    /// C6 "Ver evolução" (`ExerciseDefinition.id` e o nome para o título). A C4 ("Como renovar") saiu
    /// na 2.5 (SPEC §7.18 L4).
    case progress(exerciseID: UUID, name: String)

    var id: String {
        switch self {
        case .progress(let exerciseID, _):
            return "progress-\(exerciseID.uuidString)"
        }
    }
}

/// Abas + apresentação da sessão, do onboarding e do diálogo. Dona do `LandingViewModel`, do
/// `HomeViewModel`, do `HealthViewModel` e do `SettingsViewModel` (um de cada por processo), da aba
/// selecionada e do que está apresentado.
///
/// A abertura (SPEC RF-50) fica por cima das abas enquanto `isLaunchPending` é verdadeiro; o
/// onboarding e o destaque do diálogo esperam ela terminar (`finishLaunch`).
///
/// A exportação do backup e os alertas do Ajustes ficam aqui, na raiz, e não dentro da aba: o
/// "Fazer backup" do diálogo (SPEC §7.11 C7) abre a exportação direto, de qualquer aba (B10), e o
/// resultado aparece onde a pessoa está.
///
/// Uma folha de cada vez: o destaque do diálogo só aparece quando nada mais está na tela
/// (`blocksCoachSheet`, liberado nos `onDismiss` do onboarding, da sessão e da troca de
/// objetivo, depois que a animação de saída termina), porque o SwiftUI não abre uma folha sobre
/// outra apresentação.
@MainActor
private struct RootTabs: View {
    /// Item do `fullScreenCover(item:)`: só o `uuid` da sessão; a view do fluxo busca o resto.
    private struct PresentedSession: Identifiable {
        let id: UUID
    }

    private enum RootTab: Hashable {
        case landing
        case today
        case history
        case plan
        case settings
    }

    /// Janela de sessões passadas ao painel de saúde (SPEC A5: encaixe do aeróbico longe dos dias
    /// de inferior só olha a semana corrente e a próxima).
    private static let recentSessionWindow: TimeInterval = 14 * 86_400

    /// Rede de segurança da abertura: se por algum motivo o relógio dela não avisar o fim (0,92 s;
    /// 0,60 s com Reduzir Movimento), a raiz encerra sozinha depois disto, para o onboarding e o
    /// destaque do diálogo nunca ficarem presos atrás dela.
    private static let launchFallbackDelay: Duration = .seconds(3)

    private let environment: AppEnvironment
    private let coach: CoachService
    @State private var landingModel: LandingViewModel
    @State private var homeModel: HomeViewModel
    @State private var healthModel: HealthViewModel
    @State private var settingsModel: SettingsViewModel
    /// SPEC §7.17, RF-53 (2.4): as atividades fora do app, um modelo só para o Início (Metas da
    /// semana), a tela Hoje ("Também hoje") e a aba Plano ("Atividades fixas").
    @State private var activitiesModel: ActivitiesModel
    @State private var presentedSession: PresentedSession? = nil
    @State private var coachDestination: CoachDestination? = nil
    /// SPEC RF-49: o app abre no Início.
    @State private var selectedTab: RootTab = .landing
    /// SPEC RF-50: verdadeiro só na abertura a frio, até a abertura terminar (dono: `RootView`).
    @Binding private var isLaunchPending: Bool
    /// Verdadeiro enquanto o onboarding ou a sessão estão na tela (ou ainda não se sabe, antes do
    /// `onAppear`): o destaque do diálogo espera.
    @State private var blocksCoachSheet = true
    /// A folha do destaque está na tela: um erro de resposta dado nela só aparece depois que ela
    /// fecha (duas apresentações ao mesmo tempo não abrem).
    @State private var isHighlightOnScreen = false
    @State private var isShowingCoachError = false
    /// Folha "Seu objetivo" (SPEC RF-45) aberta pelo topo da tela Hoje ou pelo diálogo (C2).
    @State private var isShowingGoalSheet = false
    @Environment(\.scenePhase) private var scenePhase

    /// Marca gravada pelo `OnboardingView` ao tocar "Começar" ou "Pular" (UserDefaults, sem
    /// SwiftData: M2-CONTRACT §2).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Controla a `.sheet` do onboarding. Copiado da marca no `onAppear` em vez de um `Binding`
    /// derivado: a marca só vira `true` dentro do onboarding, que fecha a sheet por `onDone`.
    @State private var isShowingOnboarding = false

    init(environment: AppEnvironment, isLaunchPending: Binding<Bool>) {
        self.environment = environment
        self.coach = environment.coach
        self._isLaunchPending = isLaunchPending
        let home = HomeViewModel(
            planner: environment.planner,
            coordinator: environment.coordinator,
            now: environment.now
        )
        self._homeModel = State(initialValue: home)
        // A4/B8: o mesmo log do diálogo do `CoachService`. "Ok, entendi" no detalhe do Saúde e
        // "Entendi" no feed gravam e leem a mesma resposta, nos dois sentidos.
        // SPEC §7.16 W7 (item 18 do dono): passos só com um plano ativo de Longevidade ou Cardio,
        // no cartão, no detalhe e na sugestão de passos baixos (que também sai do feed do diálogo).
        let health = HealthViewModel(
            reader: environment.healthReader,
            sessionsProvider: { [environment] in
                RootTabs.recentSessions(from: environment)
            },
            now: environment.now,
            logStore: environment.coach.logStore,
            showsSteps: { [environment] in
                WeeklyGoals.showsSteps(activeGoals: (try? environment.planner.activeProgramGoals()) ?? [])
            },
            // SPEC §7.17 X3 e X5: os registros aeróbicos entram nos minutos e os de inferior no
            // encaixe do aeróbico (A5), sem reler o HealthKit nem pedir nada.
            activityLog: { [environment] in
                environment.activities.load()
            }
        )
        self._healthModel = State(initialValue: health)
        // SPEC RF-49/RF-52: o Início e as Metas da semana. O relatório do Saúde é o mesmo do cartão
        // da tela Hoje; `loadIfStale` só lê o que já foi autorizado (nunca pede, AGENTS §7). Do log do
        // diálogo (C8), só os "Feito" de antes da 2.4 valem 1 (W2.6); os de depois contam pelo registro.
        let coachService = environment.coach
        let landing = LandingViewModel(
            planner: environment.planner,
            coordinator: environment.coordinator,
            now: environment.now,
            healthReport: { [health] in
                health.report
            },
            loadHealth: { [health] in
                await health.loadIfStale()
            },
            longevityDone: { [coachService, environment] in
                coachService.legacyLongevityMarks(in: coachService.logStore.load(), now: environment.now())
            },
            // SPEC §7.16 W2.3, W2.6 e §7.17 X3, X6: o aeróbico das atividades sem o Saúde e as vezes
            // de equilíbrio e mobilidade registradas.
            activityLog: { [environment] in
                environment.activities.load()
            }
        )
        self._landingModel = State(initialValue: landing)
        // SPEC RF-53: depois de cada gravação das atividades, o relatório de saúde é refeito com a
        // última leitura (sem reler o HealthKit), e o Início e a tela Hoje releem, nesta ordem, para
        // as Metas lerem o relatório já recalculado. O diálogo também relê: equilíbrio ou mobilidade
        // registrados tiram o lembrete do C8 da semana (X6).
        let activities = ActivitiesModel(
            store: environment.activities,
            now: environment.now,
            calendar: .autoupdatingCurrent,
            onChange: { [health, landing, home, coachService] in
                health.activitiesDidChange()
                landing.refresh()
                home.refresh()
                RootTabs.refresh(coach: coachService, health: health, allowsHighlight: false)
            }
        )
        self._activitiesModel = State(initialValue: activities)
        // Depois de importar um backup, pedir uma semana leve ou mudar o modo casa, o plano mudou:
        // o Início e a Home releem. O diálogo relê ao voltar para "Hoje", longe dos alertas do
        // Ajustes; depois de uma importação ele também esquece a revisão guardada em memória (A5).
        self._settingsModel = State(initialValue: SettingsViewModel(
            backup: environment.backup,
            planner: environment.planner,
            now: environment.now,
            appVersion: SettingsViewModel.bundleVersion(.main),
            onImported: { [coachService] in
                coachService.resetAfterImport()
            },
            onDataChanged: { [home, landing, activities, health] in
                // SPEC §7.17 X8: a importação também troca as atividades; o relatório de saúde é
                // refeito com elas antes de o Início reler.
                activities.refresh()
                health.activitiesDidChange()
                home.refresh()
                landing.refresh()
            }
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
        // SPEC RF-50: a abertura a frio por cima das abas, com os objetivos ativos (o principal
        // primeiro, M2) para corar a pétala dele. O Início já está montado e aceitando toques
        // desde o primeiro quadro; o fim libera o onboarding e o destaque do diálogo.
        .launchOverlay(goals: landingModel.activeGoals, isEnabled: isLaunchPending, onFinished: {
            finishLaunch()
        })
        // Programa ativo, dias, objetivo e ajustes podem ter mudado nas outras abas: ao voltar
        // para "Início" ou "Hoje", a tela relê (além do próprio `onAppear` dela); em "Hoje", o
        // diálogo também.
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .landing:
                // O "Feito" do C8 (diálogo) também grava uma atividade (X6): o modelo relê.
                activitiesModel.refresh()
                landingModel.refresh()
            case .today:
                activitiesModel.refresh()
                homeModel.refresh()
                refreshCoach()
            case .plan:
                activitiesModel.refresh()
            case .history, .settings:
                break
            }
        }
        // A Home não recebe `onAppear` ao dispensar um cover: relê aqui para mostrar a próxima
        // sessão recalculada (SPEC F4) e trocar Retomar → Começar (no Início, "Retomar a sessão"
        // → "Ver a sessão de hoje"). O diálogo relê ao fechar a sessão (marcos pessoais, C6).
        .fullScreenCover(item: $presentedSession, onDismiss: {
            // RF-44 g: a ficha liga a tela acesa e desliga ao sumir; isto só garante que ela
            // nunca fica ligada fora da sessão, mesmo se o `onDisappear` da ficha não vier.
            UIApplication.shared.isIdleTimerDisabled = false
            blocksCoachSheet = false
            refreshScreens()
            refreshCoach()
        }) { presented in
            SessionFlowView(sessionID: presented.id, environment: environment, onClose: {
                presentedSession = nil
            })
        }
        // Primeiro launch (RF-45): um passo só, escolher o objetivo. O onboarding desliga o
        // gesto de dispensa; toda saída passa por "Começar" ou "Pular", que gravam a marca.
        .sheet(isPresented: $isShowingOnboarding, onDismiss: {
            blocksCoachSheet = false
            refreshCoach()
        }) {
            OnboardingView(
                programs: environment.programs,
                references: environment.references,
                catalog: environment.catalog,
                onDone: {
                    isShowingOnboarding = false
                    refreshScreens()
                }
            )
        }
        // RF-45: trocar de objetivo pelo topo da tela Hoje, pelo "Escolher um objetivo" do Início
        // ou pelo diálogo (C2). A folha só chama `onFinish`; quem fecha é daqui. Com sessão em
        // andamento, "Trocar" fica bloqueado dentro da folha. O destaque do diálogo espera ela
        // fechar. Com o planejador, a folha também oferece "Adicionar X ao seu plano" (SPEC
        // §7.15 M8): o encaixe na semana e as preferências passam por ele.
        .sheet(isPresented: $isShowingGoalSheet, onDismiss: {
            blocksCoachSheet = false
        }) {
            GoalSheet(
                programs: environment.programs,
                catalog: environment.catalog,
                references: environment.references,
                mode: .change,
                // Direto do coordinator: o espelho da Home só existe depois que a aba Hoje aparece,
                // e a folha também abre do Início e do diálogo (C2) logo na abertura.
                isSessionInProgress: environment.coordinator.activeSession != nil,
                planner: environment.planner,
                now: environment.now,
                onFinish: { didChange in
                    isShowingGoalSheet = false
                    if didChange {
                        refreshScreens()
                        refreshCoach()
                    }
                }
            )
        }
        // SPEC §7.11: destaque na abertura quando há algo novo e importante (C1, C5, C2).
        // `highlightDidDismiss` no `onDismiss` é obrigatório: é ele que faz a navegação pedida na
        // folha ("Começar", escolher programa) depois que ela fecha.
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
                    // O destaque costuma aparecer sobre o Início (é a aba da abertura): uma
                    // resposta que muda o plano (semana leve, troca de programa) aparece nele. O
                    // "Feito" do C8 grava uma atividade (X6): o modelo delas relê antes.
                    activitiesModel.refresh()
                    landingModel.refresh()
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
        // que termina depois da abertura. As Metas da semana (aeróbico, passos, sono) também.
        .onChange(of: healthModel.report) { _, _ in
            refreshCoach()
            landingModel.refresh()
        }
        // A4/B8: "Ok, entendi" no detalhe do Saúde (empilhado na aba Hoje) grava no log do
        // diálogo; o feed da Home relê na hora, sem esperar a volta ao primeiro plano. O sentido
        // inverso não precisa disto: o detalhe lê o log sempre que aparece.
        .onChange(of: healthModel.visibleSuggestions.map(\.kind)) { _, _ in
            refreshCoach()
        }
        .onAppear {
            connectCoachNavigation()
            // SPEC RF-50: com a abertura na tela, o onboarding e o destaque esperam o fim dela.
            if !isLaunchPending {
                releaseAfterLaunch()
            }
        }
        // Rede de segurança da abertura (`launchFallbackDelay`). O `try?` cobre o cancelamento
        // da tarefa quando a raiz some; aí nada mais é feito.
        .task {
            try? await Task.sleep(for: RootTabs.launchFallbackDelay)
            guard !Task.isCancelled, isLaunchPending else {
                return
            }
            finishLaunch()
        }
        // Ao abrir e a cada volta ao primeiro plano. Nada aqui pede autorização (AGENTS §7).
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            // SPEC RF-49: o Início relê ao voltar ao primeiro plano (a data, a saudação e a
            // semana podem ter mudado com o app em segundo plano). As atividades também (RF-53):
            // o dia de hoje e a semana delas saem do relógio.
            activitiesModel.refresh()
            landingModel.refresh()
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

    /// As cinco abas (DESIGN §8).
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            // SPEC RF-49: o Início, a primeira aba, aberta no lançamento. "Ver a sessão de hoje" e
            // "Ver o dia" levam à aba Hoje; "Escolher um objetivo" também abre lá a folha "Seu
            // objetivo"; "Retomar a sessão" usa o mesmo caminho do "Retomar" da tela Hoje.
            LandingView(
                model: landingModel,
                references: environment.references,
                onOpenToday: {
                    openToday()
                },
                onOpenSession: { sessionID in
                    openSession(sessionID)
                },
                activities: activitiesModel
            )
            .tabItem {
                Label("Início", systemImage: "house")
            }
            .tag(RootTab.landing)

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
                },
                onChangeGoal: {
                    openGoalSheet()
                },
                activities: activitiesModel
            )
            .tabItem {
                Label("Hoje", systemImage: "sun.max")
            }
            .tag(RootTab.today)

            // Apagar passa pelo coordinator (único caminho de escrita de sessão, AGENTS R4); a
            // Home relê porque a rotação e as cargas derivam do histórico (T2.13, ADR 003).
            HistoryListView(references: environment.references, onDeleteSession: { sessionID in
                try environment.coordinator.deleteSession(id: sessionID)
                refreshScreens()
            })
            .tabItem {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
            }
            .tag(RootTab.history)

            // RF-45: a aba "Plano" mostra o plano do objetivo; o planner marca a "próxima" e o
            // coordinator bloqueia a troca com sessão em andamento.
            ProgramTabView(
                programs: environment.programs,
                catalog: environment.catalog,
                references: environment.references,
                now: environment.now,
                planner: environment.planner,
                coordinator: environment.coordinator,
                activities: activitiesModel
            )
            .tabItem {
                Label("Plano", systemImage: "list.bullet.rectangle")
            }
            .tag(RootTab.plan)

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
        // SPEC §7.14 F7 (2.4): a seção "Coração" do detalhe de uma sessão de aeróbico no Histórico.
        // Só leitura, com as permissões que o app já tem; nada é pedido aqui (AGENTS §7).
        .environment(\.cardioHeartRate, cardioHeartRateLookup)
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

    /// SPEC §7.14 F7: a FC por minuto vem do HealthKit (sem dado ou sem Saúde, lista vazia, e a
    /// seção não aparece); as zonas e o VO2máx vêm do mesmo relatório do painel de saúde (A1, A3),
    /// com a fisiologia e a FC de repouso de 7 dias da última leitura. Fechos sobre tipos `Sendable`
    /// (o serviço do HealthKit e as classes isoladas no `MainActor`).
    private var cardioHeartRateLookup: CardioHeartRateLookup {
        let healthKit = environment.healthKit
        let health = healthModel
        let appEnvironment = environment
        return CardioHeartRateLookup(
            minuteHeartRates: { start, end in
                (try? await healthKit.heartRateMinutes(start: start, end: end)) ?? []
            },
            zones: {
                guard let physiology = health.physiology else {
                    return nil
                }
                return HeartRateZones.make(
                    physiology: physiology,
                    restingHeartRate: health.report?.recovery.restingHR7,
                    now: appEnvironment.now(),
                    calendar: health.calendar
                )
            },
            latestVo2Max: {
                health.report?.vo2Max
            }
        )
    }

    /// Item da folha do destaque: nada enquanto outra apresentação está na tela (onboarding,
    /// sessão, "Ver evolução"), para o SwiftUI não tentar abrir uma folha sobre outra; o destaque
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

    // MARK: - Abertura

    /// Fim da abertura (SPEC RF-50), pelo relógio dela, por um toque que a adiantou ou pela rede
    /// de segurança: tira a camada e libera o onboarding e o destaque do diálogo. Uma vez só.
    private func finishLaunch() {
        guard isLaunchPending else {
            return
        }
        isLaunchPending = false
        releaseAfterLaunch()
    }

    /// Primeiro launch: o onboarding (RF-45). Senão, o destaque do diálogo já pode aparecer, a
    /// menos que um toque durante a abertura já tenha aberto a sessão ou a folha "Seu objetivo"
    /// (aí o `onDismiss` delas é que libera).
    private func releaseAfterLaunch() {
        if !hasCompletedOnboarding {
            isShowingOnboarding = true
        } else if presentedSession == nil && !isShowingGoalSheet {
            blocksCoachSheet = false
        }
    }

    // MARK: - Início e Hoje

    /// O caminho do Início para a tela Hoje (SPEC RF-49). Sem objetivo, o botão é "Escolher um
    /// objetivo": além de ir para "Hoje", abre lá a folha "Seu objetivo", a mesma do "Escolher"
    /// do topo da tela Hoje.
    private func openToday() {
        selectedTab = .today
        if landingModel.pathState == .noGoal {
            openGoalSheet()
        }
    }

    /// O plano, o histórico ou o objetivo mudaram: o Início e a Home releem.
    private func refreshScreens() {
        homeModel.refresh()
        landingModel.refresh()
    }

    // MARK: - Sessão

    /// Abre o fluxo da sessão por cima das abas; o destaque do diálogo espera ele fechar.
    private func openSession(_ sessionID: UUID) {
        blocksCoachSheet = true
        presentedSession = PresentedSession(id: sessionID)
    }

    // MARK: - Objetivo

    /// Abre "Seu objetivo" (RF-45) por cima das abas; o destaque do diálogo espera ela fechar.
    private func openGoalSheet() {
        blocksCoachSheet = true
        isShowingGoalSheet = true
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
        let goalSheet = $isShowingGoalSheet
        let home = homeModel
        let settings = settingsModel
        let catalog = environment.catalog

        // C7 "Fazer backup" (B10): abre a exportação direto, sem trocar de aba; o `fileExporter`
        // e o alerta do resultado estão na raiz. Do destaque, o `CoachService` só chama isto
        // depois que a folha fecha.
        coach.onBackupRequested = {
            settings.prepareExport()
        }
        // C5 "Começar": o mesmo caminho do botão da Home, com a sessão que a mensagem nomeia (a
        // próxima do principal, M2). Desde a 2.3 o app abre no Início e a Home só relê ao aparecer:
        // na abertura a frio ela ainda não leu o plano nem a sessão em andamento, então relê antes.
        coach.onStartRequested = {
            tab.wrappedValue = .today
            home.refresh()
            if let sessionID = home.startPrincipalSession() {
                blocks.wrappedValue = true
                session.wrappedValue = PresentedSession(id: sessionID)
            }
        }
        // C6 "Ver evolução".
        coach.onProgressRequested = { exerciseID in
            let name = (try? catalog.exercise(id: exerciseID))?.name ?? "Evolução"
            destination.wrappedValue = .progress(exerciseID: exerciseID, name: name)
        }
        // C2 "Trocar de programa" sem outro do mesmo objetivo: a pessoa escolhe na mesma folha
        // "Seu objetivo" do topo da tela Hoje (RF-45). Do destaque, o `CoachService` só chama
        // isto depois que a folha dele fecha.
        coach.onChooseProgramRequested = {
            blocks.wrappedValue = true
            goalSheet.wrappedValue = true
        }
    }

    @ViewBuilder
    private func coachDestinationView(_ destination: CoachDestination) -> some View {
        switch destination {
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
