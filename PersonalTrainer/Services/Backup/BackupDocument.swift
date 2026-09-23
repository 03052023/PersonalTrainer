import Foundation
import TrainerCore

/// Conteúdo do arquivo de backup (T2.4, SPEC RF-18/RNF-04, ARCHITECTURE §12): TODO o store do
/// iPhone num JSON legível e determinístico.
///
/// Reusa os DTOs de domínio (`ExerciseDefinition`, `ProgramTemplate`) e acrescenta só o que eles
/// não carregam (`isArchived`, `createdAt`); sessões e séries têm registros próprios porque são
/// snapshots com campos que o domínio não modela (`notes`, FC, `sourceRaw`, `updatedAt`).
/// Campos `*Raw` viajam como a string gravada no store, sem conversão: o round-trip é exato e um
/// valor desconhecido não impede exportar.
///
/// Formato versionado por `schemaVersion`. Mudança incompatível = nova versão + leitura da antiga.
struct BackupDocument: Codable, Sendable, Hashable {
    /// Versão do formato que este app grava e lê.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    /// `CFBundleShortVersionString (CFBundleVersion)` do app que exportou; só informativo.
    var appVersion: String
    var exercises: [ExerciseRecord]
    var programs: [ProgramRecord]
    var sessions: [SessionRecord]
    /// `nil` só se o store ainda não tinha a linha de configuração (antes do primeiro seed).
    var settings: SettingsRecord?

    init(
        schemaVersion: Int = BackupDocument.currentSchemaVersion,
        exportedAt: Date,
        appVersion: String,
        exercises: [ExerciseRecord],
        programs: [ProgramRecord],
        sessions: [SessionRecord],
        settings: SettingsRecord?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.exercises = exercises
        self.programs = programs
        self.sessions = sessions
        self.settings = settings
    }

    // MARK: - Registros

    /// Exercício do catálogo. `isArchived` fica fora de `ExerciseDefinition` porque é estado do
    /// usuário, não dado de catálogo (o seed nunca o toca).
    struct ExerciseRecord: Codable, Sendable, Hashable {
        var definition: ExerciseDefinition
        var isArchived: Bool
    }

    /// Programa com dias e alvos. `createdAt` desempata programas ativos no planner.
    struct ProgramRecord: Codable, Sendable, Hashable {
        var template: ProgramTemplate
        var createdAt: Date
    }

    /// Espelho de `WorkoutSessionModel` com os exercícios aninhados.
    struct SessionRecord: Codable, Sendable, Hashable {
        var uuid: UUID
        var programDayUUID: UUID
        var programDayName: String
        var statusRaw: String
        var startedAt: Date
        var endedAt: Date?
        var notes: String
        var hkWorkoutUUID: UUID?
        var avgHeartRate: Double?
        var maxHeartRate: Double?
        var isDeload: Bool
        var sourceRaw: String
        var exercises: [SessionExerciseRecord]
    }

    /// Espelho de `SessionExerciseModel` (snapshot da prescrição) com as séries aninhadas.
    /// A relação com o catálogo não é gravada: na importação é religada por `exerciseUUID`.
    struct SessionExerciseRecord: Codable, Sendable, Hashable {
        var uuid: UUID
        var order: Int
        var exerciseUUID: UUID
        var exerciseName: String
        var prescribedLoad: Double?
        var prescribedSets: Int
        var prescribedRepMin: Int
        var prescribedRepMax: Int
        /// 0 = desconhecido (sessões gravadas antes do SchemaV2).
        var prescribedTargetReps: Int
        var prescribedRIR: Int
        var restSeconds: Int
        var noteRaw: String
        var wasSkipped: Bool
        var substitutedFromUUID: UUID?
        var sets: [SetRecord]
    }

    /// Espelho de `SetLogModel`.
    struct SetRecord: Codable, Sendable, Hashable {
        var uuid: UUID
        var index: Int
        var load: Double
        var reps: Int
        var rir: Int?
        var isWarmup: Bool
        var completedAt: Date
        var sourceRaw: String
        var updatedAt: Date
    }

    /// Espelho de `UserSettingsModel`.
    struct SettingsRecord: Codable, Sendable, Hashable {
        var uuid: UUID
        var weekStartsOnMonday: Bool
        var weeklyTargetsRaw: String
        var healthKitEnabled: Bool
        var defaultRestSeconds: Int
        var schemaSeedVersion: Int
    }

    // MARK: - Contagens

    var setCount: Int {
        sessions.reduce(0) { total, session in
            total + session.exercises.reduce(0) { $0 + $1.sets.count }
        }
    }
}

// MARK: - Codificação

extension BackupDocument {
    /// JSON UTF-8 legível e determinístico: chaves ordenadas, indentado, datas ISO 8601 em UTC
    /// com milissegundos (o `.iso8601` puro trunca para segundos e o round-trip deixaria de ser
    /// exato para datas gravadas pelo relógio do sistema).
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, dateEncoder in
            var container = dateEncoder.singleValueContainer()
            try container.encode(BackupDocument.iso8601String(from: date))
        }
        return try encoder.encode(self)
    }

    /// Decodifica sem validar a consistência (ver `validate()`).
    ///
    /// - Throws: `BackupError.unsupportedVersion` se `schemaVersion` não é a atual (lida antes do
    ///   resto, para que um formato futuro não apareça como "arquivo corrompido");
    ///   `BackupError.corrupted` para qualquer outro problema de leitura.
    static func decode(from data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dateDecoder in
            let container = try dateDecoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = BackupDocument.date(fromISO8601: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Data fora do formato ISO 8601: \(text)"
                )
            }
            return date
        }

        let header: VersionHeader
        do {
            header = try decoder.decode(VersionHeader.self, from: data)
        } catch {
            throw BackupError.corrupted
        }
        guard header.schemaVersion == currentSchemaVersion else {
            throw BackupError.unsupportedVersion(header.schemaVersion)
        }

        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.corrupted
        }
    }

    /// Só o número da versão, lido antes do documento inteiro.
    private struct VersionHeader: Decodable {
        let schemaVersion: Int
    }

    // Formatadores criados por chamada: `ISO8601DateFormatter` não é `Sendable` e as closures de
    // estratégia de data são `@Sendable`. O custo é irrelevante para um backup manual.

    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Aceita com e sem fração de segundo (arquivo editado à mão ou gerado por outra ferramenta).
    static func date(fromISO8601 text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

// MARK: - Validação

extension BackupDocument {
    /// Confere o arquivo inteiro antes de qualquer escrita no banco (SPEC RNF-04: importável em
    /// instalação limpa, ou não importa nada).
    ///
    /// - Versão igual a `currentSchemaVersion`.
    /// - Ids únicos por tipo (os `.unique` do esquema e os que o app usa como chave: dia do
    ///   programa, alvo, exercício da sessão) e `slug` único no catálogo.
    /// - Todo alvo de programa aponta para um exercício do próprio backup.
    /// - No máximo um programa ativo (SPEC S1) e uma sessão em andamento (RF-02).
    /// - `statusRaw` conhecido: os mappers do planner falham com status desconhecido.
    ///
    /// Exercícios de sessão podem apontar para fora do catálogo: o snapshot guarda nome e
    /// prescrição, e o histórico filtra por `exerciseUUID` (ARCHITECTURE §5, decisão 3).
    ///
    /// - Throws: `BackupError.unsupportedVersion` ou `BackupError.referentialIntegrity` com o
    ///   motivo em pt-BR.
    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BackupError.unsupportedVersion(schemaVersion)
        }

        var exerciseIDs: Set<UUID> = []
        var slugs: Set<String> = []
        for record in exercises {
            let definition = record.definition
            guard exerciseIDs.insert(definition.id).inserted else {
                throw BackupError.referentialIntegrity("Exercício repetido (\(definition.id.uuidString)).")
            }
            guard slugs.insert(definition.slug).inserted else {
                throw BackupError.referentialIntegrity("Dois exercícios com o mesmo identificador \"\(definition.slug)\".")
            }
        }

        var programIDs: Set<UUID> = []
        var dayIDs: Set<UUID> = []
        var targetIDs: Set<UUID> = []
        var activePrograms = 0
        for record in programs {
            let program = record.template
            guard programIDs.insert(program.id).inserted else {
                throw BackupError.referentialIntegrity("Programa repetido (\(program.id.uuidString)).")
            }
            if program.isActive {
                activePrograms += 1
            }
            for day in program.days {
                guard dayIDs.insert(day.id).inserted else {
                    throw BackupError.referentialIntegrity("Dia de programa repetido (\(day.id.uuidString)).")
                }
                for target in day.exercises {
                    guard targetIDs.insert(target.id).inserted else {
                        throw BackupError.referentialIntegrity("Exercício de programa repetido (\(target.id.uuidString)).")
                    }
                    guard exerciseIDs.contains(target.exerciseID) else {
                        throw BackupError.referentialIntegrity(
                            "O programa \"\(program.name)\" usa um exercício que não está no backup (\(target.exerciseID.uuidString))."
                        )
                    }
                }
            }
        }
        guard activePrograms <= 1 else {
            throw BackupError.referentialIntegrity("Há mais de um programa ativo.")
        }

        var sessionIDs: Set<UUID> = []
        var sessionExerciseIDs: Set<UUID> = []
        var setIDs: Set<UUID> = []
        var sessionsInProgress = 0
        for session in sessions {
            guard sessionIDs.insert(session.uuid).inserted else {
                throw BackupError.referentialIntegrity("Sessão repetida (\(session.uuid.uuidString)).")
            }
            guard let status = SessionStatus(rawValue: session.statusRaw) else {
                throw BackupError.referentialIntegrity("Sessão com status desconhecido \"\(session.statusRaw)\".")
            }
            if status == .inProgress {
                sessionsInProgress += 1
            }
            for exercise in session.exercises {
                guard sessionExerciseIDs.insert(exercise.uuid).inserted else {
                    throw BackupError.referentialIntegrity("Exercício de sessão repetido (\(exercise.uuid.uuidString)).")
                }
                for set in exercise.sets {
                    guard setIDs.insert(set.uuid).inserted else {
                        throw BackupError.referentialIntegrity("Série repetida (\(set.uuid.uuidString)).")
                    }
                }
            }
        }
        guard sessionsInProgress <= 1 else {
            throw BackupError.referentialIntegrity("Há mais de uma sessão em andamento.")
        }
    }
}
