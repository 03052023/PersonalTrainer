import Foundation
import Observation
import SwiftData
import TrainerCore

/// Contêiner de dependências do app (ARCHITECTURE §3): um por processo, injetado nas views com
/// `.environment(appEnvironment)` e lido com `@Environment(AppEnvironment.self)`.
/// Sem singletons: tudo chega por aqui. As fábricas `live()` e `preview()` ficam em
/// `AppEnvironment+Factories.swift` (T1.1), depois que os serviços concretos existem.
@Observable
@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let coordinator: any SessionCoordinating
    let planner: any SessionPlanning
    let restTimer: RestTimer
    let notifications: any NotificationScheduling
    let healthKit: any HealthKitServicing
    let watchSync: any WatchSyncServicing
    /// Relógio injetável: `{ Date() }` no app, data fixa em previews e testes (SPEC P11).
    let now: () -> Date

    init(
        modelContainer: ModelContainer,
        coordinator: any SessionCoordinating,
        planner: any SessionPlanning,
        restTimer: RestTimer,
        notifications: any NotificationScheduling,
        healthKit: any HealthKitServicing,
        watchSync: any WatchSyncServicing,
        now: @escaping () -> Date = { Date() }
    ) {
        self.modelContainer = modelContainer
        self.coordinator = coordinator
        self.planner = planner
        self.restTimer = restTimer
        self.notifications = notifications
        self.healthKit = healthKit
        self.watchSync = watchSync
        self.now = now
    }
}
