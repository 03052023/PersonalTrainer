import Foundation
import SwiftData
import TrainerCore
import os

/// Fábricas do `AppEnvironment` (T1.1). Este é o único lugar do app que lê o relógio do sistema
/// (`Date()`) e escolhe implementações concretas; o resto recebe tudo por injeção
/// (ARCHITECTURE §3, AGENTS R9).
extension AppEnvironment {
    /// Ambiente do app de verdade: store persistente, seed do bundle, notificações reais.
    ///
    /// Nunca derruba o launch por causa do store ou do seed: sem store persistente o app abre
    /// em memória (perde-se o histórico daquela execução, não o app); sem seed a Home mostra o
    /// estado vazio ("Nenhum programa ativo"). Os dois casos vão para o `os.Logger`.
    @MainActor
    static func live() -> AppEnvironment {
        let modelContainer = makeContainer(.persistent, logger: makeLogger(category: "Persistence"))
        // ARCHITECTURE §11: antes de construir o planner, que precisa do programa ativo.
        loadSeed(into: modelContainer.mainContext, now: Date(), logger: makeLogger(category: "Seed"))

        let coordinator = SessionCoordinator(
            modelContext: modelContainer.mainContext,
            appliedEvents: AppliedEventStore(userDefaults: .standard)
        )
        let planner = SessionPlanner(modelContext: modelContainer.mainContext, coordinator: coordinator)
        let notifications = LiveNotificationScheduler()

        return AppEnvironment(
            modelContainer: modelContainer,
            coordinator: coordinator,
            planner: planner,
            restTimer: RestTimer(notifications: notifications),
            notifications: notifications,
            // HealthKit real é M2 (T2.1); até lá o fake cumpre o contrato sem pedir permissão.
            healthKit: FakeHealthKitService(),
            watchSync: NoopWatchSyncService(),
            now: { Date() }
        )
    }

    /// Ambiente para `#Preview`: store em memória com o seed do bundle, fakes (AGENTS R9) e
    /// relógio fixo (SPEC P11), para que toda preview mostre o mesmo programa e as mesmas datas.
    @MainActor
    static func preview(now: Date = Date(timeIntervalSince1970: 1_758_600_000)) -> AppEnvironment {
        let fixedNow = now
        let logger = makeLogger(category: "Preview")
        let modelContainer = makeContainer(.inMemory, logger: logger)
        loadSeed(into: modelContainer.mainContext, now: fixedNow, logger: logger)

        let coordinator = SessionCoordinator(
            modelContext: modelContainer.mainContext,
            appliedEvents: AppliedEventStore.inMemory()
        )
        let planner = SessionPlanner(modelContext: modelContainer.mainContext, coordinator: coordinator)
        let notifications = FakeNotificationScheduler()

        return AppEnvironment(
            modelContainer: modelContainer,
            coordinator: coordinator,
            planner: planner,
            restTimer: RestTimer(notifications: notifications),
            notifications: notifications,
            healthKit: FakeHealthKitService(),
            watchSync: NoopWatchSyncService(),
            now: { fixedNow }
        )
    }
}

// MARK: - Passos compartilhados

private extension AppEnvironment {
    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    static func makeLogger(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: category)
    }

    /// Abre o container pedido; se falhar, cai para memória (o app abre sem histórico em vez
    /// de não abrir). Não conseguir nem o container em memória significa que o esquema
    /// compilado não carrega: é precondição de programação (AGENTS §4), não erro de runtime,
    /// e nesse caso não há `ModelContainer` possível para devolver.
    static func makeContainer(_ mode: ModelContainerFactory.Mode, logger: Logger) -> ModelContainer {
        do {
            return try ModelContainerFactory.make(mode)
        } catch {
            logger.error("Não foi possível abrir o store (\(String(describing: mode), privacy: .public)): \(String(describing: error), privacy: .public). Usando store em memória.")
        }
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
                logger.info("Seed aplicado: \(report.insertedExercises) exercícios inseridos, \(report.updatedExercises) atualizados, \(report.insertedPrograms) programa(s) inserido(s).")
            }
        } catch {
            logger.error("Falha ao carregar o seed: \(String(describing: error), privacy: .public)")
        }
    }
}
