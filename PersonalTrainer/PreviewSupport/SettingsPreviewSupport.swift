import Foundation
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Ajustes (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Settings" para não colidir com doubles de outras
// features. Planner e diálogo vêm do `AppEnvironment.preview()` (store em memória, fakes);
// os ajustes do planejamento ficam numa suite própria de `UserDefaults`.

// MARK: - Previews

#Preview("Ajustes") {
    let environment = AppEnvironment.preview()
    return SettingsView(
        backup: SettingsPreviewBackup(),
        planner: environment.planner,
        coach: environment.coach,
        health: SettingsPreviewFixture.makeHealth(),
        references: SettingsPreviewFixture.references,
        onDataChanged: {},
        now: { SettingsPreviewFixture.referenceDate },
        defaults: SettingsPreviewFixture.defaults()
    )
}

#Preview("Ajustes — sem referências") {
    let environment = AppEnvironment.preview()
    return SettingsView(
        backup: SettingsPreviewBackup(),
        planner: environment.planner,
        coach: environment.coach,
        health: SettingsPreviewFixture.makeHealth(),
        references: .empty,
        onDataChanged: {},
        now: { SettingsPreviewFixture.referenceDate },
        defaults: SettingsPreviewFixture.defaults()
    )
}

// MARK: - Fixtures

private enum SettingsPreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos.
    static let referenceDate = Date(timeIntervalSince1970: 1_758_600_000)

    static let references = ReferenceCatalog(
        version: 1,
        references: [
            ScientificReference(
                id: "schoenfeld-2017-volume",
                authors: "Schoenfeld BJ, Ogborn D, Krieger JW",
                year: 2017,
                title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass: A systematic review and meta-analysis",
                source: "Journal of Sports Sciences",
                doi: "10.1080/02640414.2016.1210197",
                level: .metaAnalysis,
                summary: "Mais séries semanais por músculo tendem a gerar mais hipertrofia."
            ),
        ],
        topics: ["topic.volume": ["schoenfeld-2017-volume"]],
        explanations: ["topic.volume": "Volume semanal é o principal ajuste de hipertrofia."]
    )

    /// Suite isolada: mexer nos ajustes do preview não muda o que o app real guardou.
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsPreview") ?? .standard
    }

    /// Saúde de mentira para o link do perfil.
    @MainActor
    static func makeHealth() -> HealthViewModel {
        let fixedNow = referenceDate
        return HealthViewModel(
            reader: FakeHealthDataReader(),
            sessionsProvider: { [] },
            now: { fixedNow },
            defaults: UserDefaults(suiteName: "SettingsPreview.health") ?? .standard
        )
    }
}

// MARK: - Doubles

/// Exporta um JSON mínimo e "importa" devolvendo contagens fixas, sem banco.
@MainActor
private final class SettingsPreviewBackup: BackupServicing {
    func exportBackup(now: Date) throws -> Data {
        Data("{\"schemaVersion\": 1}".utf8)
    }

    func importBackup(_ data: Data) throws -> BackupImportReport {
        BackupImportReport(exercises: 42, programs: 3, sessions: 27, sets: 512)
    }

    func suggestedFileName(now: Date) -> String {
        "PersonalTrainer-backup-2025-09-23.json"
    }
}
