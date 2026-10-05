import Foundation
import TrainerCore

/// Guarda as atividades feitas fora do app (SPEC §7.17 X8, RF-53): os registros e as fixas, num JSON pequeno
/// fora do SwiftData (sem SchemaV3), como as decisões da semana leve.
///
/// Implementações (AGENTS R9): `LiveOutsideActivityStore` (arquivo em Application Support, da tarefa `data`
/// da 2.4) e `FakeOutsideActivityStore` (memória, para testes e previews). Quem escreve é o
/// `ActivitiesModel` (Features/Activities), o `CoachService` (o "Feito" do C8, X6) e o `BackupService` (a
/// importação substitui a lista). Andaime da 2.4: docs/V24-CONTRACT.md §3.2.
protocol OutsideActivityStoring: AnyObject {
    /// O que está gravado, ou `OutsideActivityLog.empty` quando não há nada ou o arquivo não pôde ser lido.
    /// Nunca lança: sem registros, o app segue como antes.
    func load() -> OutsideActivityLog

    /// Substitui o que está gravado por `log`.
    func save(_ log: OutsideActivityLog) throws
}

/// Falhas ao gravar as atividades fora do app.
enum OutsideActivityStoreError: Error, Equatable {
    /// Não há onde gravar (a pasta Application Support não pôde ser resolvida).
    case storageUnavailable
}
