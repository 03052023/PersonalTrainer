import Foundation
import HealthKit
import SwiftData
import TrainerCore
import os

/// Fábricas do `AppEnvironment` (T1.1). Este é o único lugar do app que lê o relógio do sistema
/// (`Date()`) e escolhe implementações concretas; o resto recebe tudo por injeção
/// (ARCHITECTURE §3, AGENTS R9).
extension AppEnvironment {
    /// Ambiente do app de verdade: store persistente, seed do bundle, notificações reais,
    /// HealthKit real quando o aparelho tem o app Saúde, decisões de semana leve e log do diálogo
    /// em JSON (Application Support/PersonalTrainer).
    ///
    /// Nunca derruba o launch por causa do store, do seed ou das referências, e nunca esconde os
    /// dados do usuário:
    /// - store persistente que não abre (migração, disco cheio, arquivo protegido): o ambiente sai
    ///   com `storeLoadError` preenchido e um container em memória só para as dependências
    ///   existirem. Nada de seed, gravador do Saúde ou recuperação de importação nesse modo, e o
    ///   `RootView` mostra só a tela de erro (tentar de novo / exportar os arquivos). O arquivo em
    ///   disco não é tocado;
    /// - sem seed, a Home mostra o estado vazio ("Nenhum programa ativo");
    /// - sem referências, os botões "Por quê?" somem.
    /// Os casos vão para o `os.Logger`.
    @MainActor
    static func live() -> AppEnvironment {
        let persistenceLogger = makeLogger(category: "Persistence")
        let opened = openPersistentContainer(logger: persistenceLogger)
        let modelContainer = opened.container
        let storeLoadError = opened.errorMessage
        let context = modelContainer.mainContext

        let backup: BackupService
        if storeLoadError == nil {
            backup = BackupService(
                modelContext: context,
                pendingRestoreURL: BackupService.defaultPendingRestoreURL(),
                // Um backup de uma versão anterior volta com o seed dela: o catálogo atual (os
                // exercícios de casa, RF-42) é completado logo depois da importação.
                reapplySeed: {
                    AppEnvironment.loadSeed(into: context, now: Date(), logger: AppEnvironment.makeLogger(category: "Seed"))
                }
            )
            // Antes do seed: uma importação interrompida deixa o store vazio, e o seed instalaria o
            // catálogo padrão por cima dos dados que o retrato da importação ainda guarda.
            backup.recoverInterruptedImportIfNeeded()
            // ARCHITECTURE §11: antes de construir o planner, que precisa do programa ativo.
            loadSeed(into: context, now: Date(), logger: makeLogger(category: "Seed"))
        } else {
            backup = BackupService(modelContext: context)
        }

        let coordinator = SessionCoordinator(
            modelContext: context,
            appliedEvents: AppliedEventStore(userDefaults: .standard)
        )
        // A mesma instância vai ao planner e ao ambiente: com o padrão em memória do planner,
        // "Fazer semana leve agora" e "Seguir normal" se perderiam ao relançar (contrato §2.2).
        let deloadDecisions = LiveDeloadDecisionsStore()
        // Lido uma vez: o planner (modo casa, duração estimada) e as telas (`\.exerciseTraits`)
        // usam o mesmo catálogo de medidas (SPEC RF-42, RF-43).
        let traits = ExerciseTraitsLibrary.load(bundle: .main)
        let planner = SessionPlanner(
            modelContext: context,
            coordinator: coordinator,
            deloadDecisions: deloadDecisions,
            traits: traits
        )
        let programs = ProgramRepository(modelContext: context)
        let notifications = LiveNotificationScheduler()

        // Sem app Saúde (iPad), o fake fica indisponível de propósito: com `isAvailable == true`
        // ele devolveria FC sintética, que o gravador guardaria no histórico real.
        let healthKit: any HealthKitServicing
        let liveHealthKit = LiveHealthKitService()
        if liveHealthKit.isAvailable {
            healthKit = liveHealthKit
        } else {
            healthKit = FakeHealthKitService(isAvailable: false)
        }
        // Assina `eventsApplied` já: a autorização do HealthKit só é pedida ao finalizar a
        // primeira sessão, nunca no launch (AGENTS §7). Sem store real, nenhum treino vai ao Saúde:
        // as sessões de um container em memória não existiriam no próximo launch.
        let healthRecorder: HealthKitWorkoutRecorder?
        if storeLoadError == nil {
            let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: coordinator)
            recorder.start()
            healthRecorder = recorder
        } else {
            healthRecorder = nil
        }

        // Painel de saúde (SPEC §7.10): só leitura, e a autorização só sai do botão "Conectar ao
        // Saúde" (AGENTS §7). Sem app Saúde, o fake fica indisponível pelo mesmo motivo do
        // `healthKit` acima: dados sintéticos não podem aparecer como se fossem da pessoa.
        let healthReader: any HealthDataReading
        if HKHealthStore.isHealthDataAvailable() {
            healthReader = LiveHealthDataReader()
        } else {
            healthReader = FakeHealthDataReader(isAvailable: false)
        }

        // Diálogo (SPEC §7.11): o `refresh` só acontece com as abas na tela, então no modo de
        // erro do store nada é lido nem gravado por ele. Permissão de notificação só por ação da
        // pessoa (AGENTS §7).
        let coach = CoachService(
            planner: planner,
            programs: programs,
            log: LiveCoachLogStore(),
            expiry: ProvisioningExpiryReader(bundle: .main),
            notifications: notifications,
            now: { Date() },
            calendar: .current,
            defaults: .standard,
            traits: traits
        )

        return AppEnvironment(
            modelContainer: modelContainer,
            coordinator: coordinator,
            planner: planner,
            programs: programs,
            catalog: CatalogRepository(modelContext: context),
            backup: backup,
            references: ReferenceLibrary.load(bundle: .main),
            restTimer: RestTimer(notifications: notifications),
            notifications: notifications,
            healthKit: healthKit,
            healthReader: healthReader,
            deloadDecisions: deloadDecisions,
            coach: coach,
            healthRecorder: healthRecorder,
            watchSync: NoopWatchSyncService(),
            now: { Date() },
            storeLoadError: storeLoadError,
            traits: traits
        )
    }

    /// Ambiente para `#Preview`: store em memória com o seed do bundle, repositórios reais sobre
    /// ele, fakes para efeitos externos (AGENTS R9) e relógio fixo (SPEC P11), para que toda
    /// preview mostre o mesmo programa e as mesmas datas. Sem gravador do Saúde: nada sai do
    /// preview. As referências vêm do bundle; se faltarem, `ReferenceLibrary` devolve `.empty`.
    /// Diálogo, decisões de semana leve e leitura do Saúde também são fakes.
    @MainActor
    static func preview(now: Date = Date(timeIntervalSince1970: 1_758_600_000)) -> AppEnvironment {
        let fixedNow = now
        let logger = makeLogger(category: "Preview")
        let modelContainer = makeInMemoryContainer(logger: logger)
        let context = modelContainer.mainContext
        loadSeed(into: context, now: fixedNow, logger: logger)

        let coordinator = SessionCoordinator(
            modelContext: context,
            appliedEvents: AppliedEventStore.inMemory()
        )
        // Decisões em memória e ajustes fixos: nenhuma preview lê nem grava o que o app real guardou.
        let deloadDecisions = FakeDeloadDecisionsStore()
        let traits = ExerciseTraitsLibrary.load(bundle: .main)
        let planner = SessionPlanner(
            modelContext: context,
            coordinator: coordinator,
            deloadDecisions: deloadDecisions,
            settings: { PlannerSettings() },
            traits: traits
        )
        let programs = ProgramRepository(modelContext: context)
        let notifications = FakeNotificationScheduler()
        let coach = CoachService(
            planner: planner,
            programs: programs,
            log: FakeCoachLogStore(),
            expiry: .unavailable,
            notifications: notifications,
            now: { fixedNow },
            calendar: .current,
            defaults: UserDefaults(suiteName: "AppEnvironment.preview") ?? .standard,
            traits: traits
        )

        return AppEnvironment(
            modelContainer: modelContainer,
            coordinator: coordinator,
            planner: planner,
            programs: programs,
            catalog: CatalogRepository(modelContext: context),
            backup: BackupService(modelContext: context),
            references: ReferenceLibrary.load(bundle: .main),
            restTimer: RestTimer(notifications: notifications),
            notifications: notifications,
            healthKit: FakeHealthKitService(),
            healthReader: FakeHealthDataReader(),
            deloadDecisions: deloadDecisions,
            coach: coach,
            healthRecorder: nil,
            watchSync: NoopWatchSyncService(),
            now: { fixedNow },
            traits: traits
        )
    }
}

// MARK: - Passos compartilhados

private extension AppEnvironment {
    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    static func makeLogger(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: category)
    }

    /// Abre o store persistente. Em falha devolve um container em memória, que só existe para as
    /// dependências poderem ser montadas, e a descrição do erro, que faz o `RootView` bloquear o
    /// app na tela de erro. O store em disco nunca é apagado nem recriado aqui.
    static func openPersistentContainer(logger: Logger) -> (container: ModelContainer, errorMessage: String?) {
        do {
            return (try ModelContainerFactory.make(.persistent), nil)
        } catch {
            let message = String(describing: error)
            logger.error("Não foi possível abrir o store persistente: \(message, privacy: .public). O app mostra a tela de erro; nada foi apagado.")
            return (makeInMemoryContainer(logger: logger), message)
        }
    }

    /// Não conseguir nem o container em memória significa que o esquema compilado não carrega: é
    /// precondição de programação (AGENTS §4), não erro de runtime, e nesse caso não há
    /// `ModelContainer` possível para devolver.
    static func makeInMemoryContainer(logger: Logger) -> ModelContainer {
        do {
            return try ModelContainerFactory.make(.inMemory)
        } catch {
            logger.fault("Não foi possível criar nem o store em memória: \(String(describing: error), privacy: .public)")
            preconditionFailure("SwiftData não conseguiu criar o ModelContainer em memória para CurrentSchema: \(error)")
        }
    }

    /// ARCHITECTURE §11: seed no primeiro launch (e reaplicação do catálogo quando a versão
    /// sobe). Falha vira log, não crash: o app abre sem programa e a Home mostra o estado vazio.
    @MainActor
    static func loadSeed(into context: ModelContext, now: Date, logger: Logger) {
        do {
            let report = try SeedLoader.loadIfNeeded(context: context, bundle: .main, now: now)
            if !report.skipped {
                logger.info("Seed aplicado: \(report.insertedExercises) exercícios inseridos, \(report.updatedExercises) atualizados, \(report.insertedPrograms) programa(s) inserido(s), \(report.skippedPrograms) já existente(s).")
            }
        } catch {
            logger.error("Falha ao carregar o seed: \(String(describing: error), privacy: .public)")
        }
    }
}
