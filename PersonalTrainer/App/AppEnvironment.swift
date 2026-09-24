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
    /// Escrita de programas (AGENTS R4: catálogo/programa só via `*Repository`).
    let programs: any ProgramRepositoring
    /// Escrita do catálogo de exercícios (AGENTS R4).
    let catalog: any CatalogRepositoring
    /// Exportar/importar backup JSON (SPEC RF-18).
    let backup: any BackupServicing
    /// Referências científicas do "Por quê?" (SPEC RF-32), lidas do bundle a cada launch.
    let references: ReferenceCatalog
    let restTimer: RestTimer
    let notifications: any NotificationScheduling
    let healthKit: any HealthKitServicing
    /// Leva sessões finalizadas ao app Saúde (RF-13/RF-14). `nil` em previews e testes: sem
    /// observador, nenhum treino é gravado no Saúde. Mantido aqui para viver pelo processo.
    let healthRecorder: HealthKitWorkoutRecorder?
    let watchSync: any WatchSyncServicing
    /// Relógio injetável: `{ Date() }` no app, data fixa em previews e testes (SPEC P11).
    let now: () -> Date

    init(
        modelContainer: ModelContainer,
        coordinator: any SessionCoordinating,
        planner: any SessionPlanning,
        programs: any ProgramRepositoring,
        catalog: any CatalogRepositoring,
        backup: any BackupServicing,
        references: ReferenceCatalog,
        restTimer: RestTimer,
        notifications: any NotificationScheduling,
        healthKit: any HealthKitServicing,
        healthRecorder: HealthKitWorkoutRecorder?,
        watchSync: any WatchSyncServicing,
        now: @escaping () -> Date = { Date() }
    ) {
        self.modelContainer = modelContainer
        self.coordinator = coordinator
        self.planner = planner
        self.programs = programs
        self.catalog = catalog
        self.backup = backup
        self.references = references
        self.restTimer = restTimer
        self.notifications = notifications
        self.healthKit = healthKit
        self.healthRecorder = healthRecorder
        self.watchSync = watchSync
        self.now = now
    }
}
