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
    /// Leitura do app Saúde para o painel de saúde (SPEC §7.10): `LiveHealthDataReader` no
    /// aparelho com o app Saúde, `FakeHealthDataReader` nos demais casos, em previews e testes.
    let healthReader: any HealthDataReading
    /// Decisões de semana leve ("Fazer semana leve agora", "Seguir normal"), a mesma instância
    /// injetada no `SessionPlanner` (SPEC §7.5; contrato V2-FINAL §2.2).
    let deloadDecisions: any DeloadDecisionsStoring
    /// O diálogo do app (SPEC §7.11 C1–C8): feed da Home, destaque na abertura, lembrete da
    /// validade da instalação.
    let coach: CoachService
    /// Leva sessões finalizadas ao app Saúde (RF-13/RF-14). `nil` em previews e testes: sem
    /// observador, nenhum treino é gravado no Saúde. Mantido aqui para viver pelo processo.
    let healthRecorder: HealthKitWorkoutRecorder?
    let watchSync: any WatchSyncServicing
    /// Relógio injetável: `{ Date() }` no app, data fixa em previews e testes (SPEC P11).
    let now: () -> Date
    /// Descrição do erro quando o store persistente não abriu (migração, disco cheio, arquivo
    /// protegido). Com valor, `RootView` mostra só a tela de erro (tentar de novo / exportar os
    /// arquivos de dados) em vez das abas: o app nunca abre vazio em memória fingindo ser uma
    /// instalação nova, e nada é gravado, semeado ou exportado por cima dos dados reais, que
    /// continuam intactos no disco.
    let storeLoadError: String?
    /// Medida e marca "de casa" por `slug`, do catálogo do bundle (SPEC RF-42, RF-43). Também vai
    /// para o ambiente do SwiftUI (`\.exerciseTraits`) na raiz.
    let traits: ExerciseTraitsCatalog

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
        healthReader: any HealthDataReading,
        deloadDecisions: any DeloadDecisionsStoring,
        coach: CoachService,
        healthRecorder: HealthKitWorkoutRecorder?,
        watchSync: any WatchSyncServicing,
        now: @escaping () -> Date = { Date() },
        storeLoadError: String? = nil,
        traits: ExerciseTraitsCatalog = .empty
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
        self.healthReader = healthReader
        self.deloadDecisions = deloadDecisions
        self.coach = coach
        self.healthRecorder = healthRecorder
        self.watchSync = watchSync
        self.now = now
        self.storeLoadError = storeLoadError
        self.traits = traits
    }
}
