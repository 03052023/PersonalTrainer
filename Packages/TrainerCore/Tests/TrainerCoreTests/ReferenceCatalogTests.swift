import Foundation
import Testing
@testable import TrainerCore

// MARK: - Real catalog (PersonalTrainer/Resources/Seed/references.v1.json)

@Test("RF-32 catálogo real decodifica e passa no ReferenceValidator")
func referenceCatalogFileDecodesAndValidates() throws {
    let catalog = try loadReferenceCatalogFile()

    try ReferenceValidator.validate(catalog)
    #expect(catalog.version == 1)
}

@Test("RF-32 catálogo real tem ao menos 18 referências, todas com DOI")
func referenceCatalogFileHasEnoughReferencesWithDOI() throws {
    let catalog = try loadReferenceCatalogFile()

    #expect(catalog.references.count >= 18)
    for reference in catalog.references {
        #expect(reference.doi != nil, "\(reference.id) sem DOI")
        #expect(reference.link?.hasPrefix("https://doi.org/10.") == true, "\(reference.id)")
    }
}

@Test("RF-32 todo tópico obrigatório do M2 tem referência e explicação")
func referenceCatalogFileCoversRequiredTopics() throws {
    let catalog = try loadReferenceCatalogFile()

    for topic in ReferenceFixture.requiredTopics {
        #expect(!catalog.references(for: topic).isEmpty, "tópico sem referência: \(topic)")
        let explanation = catalog.explanations[topic] ?? ""
        #expect(!explanation.isEmpty, "tópico sem explicação: \(topic)")
    }
}

@Test("RF-32 cada nota de prescrição e cada objetivo tem tópico no catálogo real")
func referenceCatalogFileCoversNotesAndGoals() throws {
    let catalog = try loadReferenceCatalogFile()
    let notes: [PrescriptionNote] = [.calibrate, .increase, .hold, .retry, .decrease, .returning, .deload]

    for note in notes {
        let topic = ReferenceCatalog.topic(for: note)
        #expect(!catalog.references(for: topic).isEmpty, "\(topic)")
    }
    for goal in ProgramGoal.allCases {
        #expect(!catalog.references(for: goal.referenceTopic).isEmpty, "\(goal.referenceTopic)")
    }
}

@Test("RF-32 toda referência do catálogo real é citada por algum tópico")
func referenceCatalogFileHasNoOrphanReferences() throws {
    let catalog = try loadReferenceCatalogFile()
    let cited = Set(catalog.topics.values.flatMap { $0 })

    for reference in catalog.references {
        #expect(cited.contains(reference.id), "referência não citada: \(reference.id)")
    }
}

@Test("RF-32 explicações do catálogo real têm de 1 a 3 frases")
func referenceCatalogFileExplanationsAreShort() throws {
    let catalog = try loadReferenceCatalogFile()

    for (topic, explanation) in catalog.explanations {
        #expect((1...3).contains(sentenceCount(explanation)), "\(topic): \(sentenceCount(explanation)) frases")
    }
}

@Test("SPEC 7.9 catálogo real usa diretrizes e sínteses antes de estudos isolados")
func referenceCatalogFilePrefersSyntheses() throws {
    let catalog = try loadReferenceCatalogFile()
    let syntheses: Set<ScientificReference.EvidenceLevel> = [.guideline, .consensus, .metaAnalysis, .systematicReview]

    let synthesisCount = catalog.references.filter { syntheses.contains($0.level) }.count
    #expect(synthesisCount * 2 > catalog.references.count)
    #expect(catalog.references.contains { $0.level == .guideline })
}

@Test("RF-32 catálogo real faz round-trip Codable")
func referenceCatalogFileCodableRoundTrip() throws {
    let catalog = try loadReferenceCatalogFile()

    let data = try JSONEncoder().encode(catalog)
    let decoded = try JSONDecoder().decode(ReferenceCatalog.self, from: data)
    #expect(decoded == catalog)
}

// MARK: - ReferenceCatalog lookups

@Test("RF-32 references(for:) mantém a ordem declarada e ignora ids desconhecidos")
func referenceCatalogLookupKeepsOrderAndSkipsUnknownIDs() {
    let first = ReferenceFixture.reference(id: "alpha-2020")
    let second = ReferenceFixture.reference(id: "beta-2021")
    let catalog = ReferenceCatalog(
        version: 1,
        references: [first, second],
        topics: ["topic.test": ["beta-2021", "missing-2000", "alpha-2020"]],
        explanations: ["topic.test": "Explicação."]
    )

    #expect(catalog.references(for: "topic.test").map(\.id) == ["beta-2021", "alpha-2020"])
    #expect(catalog.references(for: "topic.absent").isEmpty)
    #expect(ReferenceCatalog.empty.references(for: "topic.test").isEmpty)
}

@Test("RF-32 tópico de nota e link DOI seguem o contrato")
func referenceCatalogNoteTopicAndLink() {
    #expect(ReferenceCatalog.topic(for: .increase) == "note.increase")
    #expect(ReferenceCatalog.topic(for: .returning) == "note.returning")

    let withDOI = ReferenceFixture.reference(doi: "10.1000/xyz123", url: "https://example.org/a")
    let withURLOnly = ReferenceFixture.reference(doi: nil, url: "https://example.org/a")
    #expect(withDOI.link == "https://doi.org/10.1000/xyz123")
    #expect(withURLOnly.link == "https://example.org/a")
}

@Test("SPEC 7.9 estudo isolado aparece como evidência limitada")
func referenceStudyLevelIsFlaggedAsLimited() {
    #expect(ScientificReference.EvidenceLevel.study.displayName.contains("evidência limitada"))
}

// MARK: - ReferenceValidator, positive cases

@Test("RF-32 validador aceita catálogo mínimo válido")
func referenceValidatorAcceptsMinimalCatalog() throws {
    try ReferenceValidator.validate(ReferenceFixture.catalog())
}

@Test("RF-32 validador aceita referência só com URL e anos nos limites")
func referenceValidatorAcceptsURLOnlyAndBoundaryYears() throws {
    for year in [1950, 2100] {
        let reference = ReferenceFixture.reference(year: year, doi: nil, url: "https://www.who.int/publications")
        try ReferenceValidator.validate(ReferenceFixture.catalog(references: [reference]))
    }
}

@Test("RF-32 validador aceita DOIs reais com parênteses, pontos e prefixos longos")
func referenceValidatorAcceptsRealWorldDOIs() throws {
    let dois = [
        "10.1016/S2468-2667(21)00302-9",
        "10.1002/14651858.CD012424.pub2",
        "10.2165/11538500-000000000-00000",
        "10.123456789/x",
    ]
    for doi in dois {
        try ReferenceValidator.validate(ReferenceFixture.catalog(references: [ReferenceFixture.reference(doi: doi)]))
    }
}

// MARK: - ReferenceValidator, one defect per catalog

@Test("RF-32 validador rejeita version < 1")
func referenceValidatorRejectsInvalidVersion() {
    for version in [0, -1] {
        #expect(throws: ReferenceValidationError.invalidVersion(version)) {
            try ReferenceValidator.validate(ReferenceFixture.catalog(version: version))
        }
    }
}

@Test("RF-32 validador rejeita id fora do padrão kebab-case")
func referenceValidatorRejectsNonKebabCaseID() {
    for id in ["Schoenfeld-2017", "schoenfeld_2017", "-schoenfeld", "schoenfeld-", "schoenfeld--2017", "", "schoenfeld 2017"] {
        let catalog = ReferenceFixture.catalog(
            references: [ReferenceFixture.reference(id: id)],
            topics: ["topic.test": [id]]
        )
        #expect(throws: ReferenceValidationError.invalidReferenceID(id), "id \"\(id)\"") {
            try ReferenceValidator.validate(catalog)
        }
    }
}

@Test("RF-32 validador rejeita id de referência duplicado")
func referenceValidatorRejectsDuplicateID() {
    let catalog = ReferenceFixture.catalog(references: [
        ReferenceFixture.reference(),
        ReferenceFixture.reference(title: "Outro título"),
    ])

    #expect(throws: ReferenceValidationError.duplicateReferenceID(ReferenceFixture.referenceID)) {
        try ReferenceValidator.validate(catalog)
    }
}

@Test("RF-32 validador rejeita autores, título, fonte ou resumo vazios")
func referenceValidatorRejectsBlankFields() {
    let cases: [(field: String, reference: ScientificReference)] = [
        ("authors", ReferenceFixture.reference(authors: "")),
        ("title", ReferenceFixture.reference(title: "   ")),
        ("source", ReferenceFixture.reference(source: "\n")),
        ("summary", ReferenceFixture.reference(summary: "")),
    ]
    for entry in cases {
        let catalog = ReferenceFixture.catalog(references: [entry.reference])
        #expect(
            throws: ReferenceValidationError.missingField(referenceID: ReferenceFixture.referenceID, field: entry.field)
        ) {
            try ReferenceValidator.validate(catalog)
        }
    }
}

@Test("RF-32 validador rejeita ano fora de 1950...2100")
func referenceValidatorRejectsInvalidYear() {
    for year in [1949, 2101, 0] {
        let catalog = ReferenceFixture.catalog(references: [ReferenceFixture.reference(year: year)])
        #expect(throws: ReferenceValidationError.invalidYear(referenceID: ReferenceFixture.referenceID, year: year)) {
            try ReferenceValidator.validate(catalog)
        }
    }
}

@Test("RF-32 validador rejeita DOI malformado")
func referenceValidatorRejectsMalformedDOI() {
    let malformed = [
        "https://doi.org/10.1080/02640414.2016.1210197",
        "doi:10.1080/02640414.2016.1210197",
        "10.108/02640414",
        "10.1234567890/abc",
        "10.1080",
        "10.1080/",
        "10.1080/abc def",
        "11.1080/abc",
        "",
    ]
    for doi in malformed {
        let catalog = ReferenceFixture.catalog(references: [ReferenceFixture.reference(doi: doi)])
        #expect(
            throws: ReferenceValidationError.invalidDOI(referenceID: ReferenceFixture.referenceID, doi: doi),
            "DOI \"\(doi)\""
        ) {
            try ReferenceValidator.validate(catalog)
        }
    }
}

@Test("RF-32 validador rejeita URL que não é http(s) absoluta")
func referenceValidatorRejectsInvalidURL() {
    for url in ["www.who.int", "ftp://example.org/file", "not a url", ""] {
        let catalog = ReferenceFixture.catalog(references: [ReferenceFixture.reference(doi: nil, url: url)])
        #expect(
            throws: ReferenceValidationError.invalidURL(referenceID: ReferenceFixture.referenceID, url: url),
            "URL \"\(url)\""
        ) {
            try ReferenceValidator.validate(catalog)
        }
    }
}

@Test("RF-32 validador rejeita referência sem DOI e sem URL")
func referenceValidatorRejectsMissingLink() {
    let catalog = ReferenceFixture.catalog(references: [ReferenceFixture.reference(doi: nil, url: nil)])

    #expect(throws: ReferenceValidationError.missingLink(referenceID: ReferenceFixture.referenceID)) {
        try ReferenceValidator.validate(catalog)
    }
}

@Test("RF-32 validador rejeita tópico vazio")
func referenceValidatorRejectsEmptyTopic() {
    let catalog = ReferenceFixture.catalog(topics: ["topic.test": []])

    #expect(throws: ReferenceValidationError.emptyTopic("topic.test")) {
        try ReferenceValidator.validate(catalog)
    }
}

@Test("RF-32 validador rejeita tópico que cita id inexistente")
func referenceValidatorRejectsUnknownReferenceID() {
    let catalog = ReferenceFixture.catalog(topics: ["topic.test": [ReferenceFixture.referenceID, "missing-2000"]])

    #expect(throws: ReferenceValidationError.unknownReferenceID("missing-2000", topic: "topic.test")) {
        try ReferenceValidator.validate(catalog)
    }
}

@Test("RF-32 validador rejeita referência repetida no mesmo tópico")
func referenceValidatorRejectsDuplicateReferenceInTopic() {
    let id = ReferenceFixture.referenceID
    let catalog = ReferenceFixture.catalog(topics: ["topic.test": [id, id]])

    #expect(throws: ReferenceValidationError.duplicateReferenceInTopic(id, topic: "topic.test")) {
        try ReferenceValidator.validate(catalog)
    }
}

@Test("RF-32 validador rejeita tópico sem explicação ou com explicação vazia")
func referenceValidatorRejectsMissingOrBlankExplanation() {
    let missing = ReferenceFixture.catalog(explanations: [:])
    let blank = ReferenceFixture.catalog(explanations: ["topic.test": "  "])

    #expect(throws: ReferenceValidationError.missingExplanation(topic: "topic.test")) {
        try ReferenceValidator.validate(missing)
    }
    #expect(throws: ReferenceValidationError.emptyExplanation(topic: "topic.test")) {
        try ReferenceValidator.validate(blank)
    }
}

@Test("RF-32 validador rejeita explicação de tópico inexistente")
func referenceValidatorRejectsExplanationWithoutTopic() {
    let catalog = ReferenceFixture.catalog(explanations: [
        "topic.test": "Explicação.",
        "topic.typo": "Explicação órfã.",
    ])

    #expect(throws: ReferenceValidationError.explanationWithoutTopic("topic.typo")) {
        try ReferenceValidator.validate(catalog)
    }
}

@Test("RF-32 validador relata o primeiro tópico em ordem alfabética")
func referenceValidatorIsDeterministicAcrossTopics() {
    let catalog = ReferenceFixture.catalog(
        topics: ["topic.b": [], "topic.a": []],
        explanations: ["topic.a": "A.", "topic.b": "B."]
    )

    for _ in 0..<5 {
        #expect(throws: ReferenceValidationError.emptyTopic("topic.a")) {
            try ReferenceValidator.validate(catalog)
        }
    }
}

// MARK: - Helpers

/// Repository root derived from this file's location (five components below it), as
/// in `SeedBundleTests`; `URL(fileURLWithPath:)` normalizes Windows separators.
private func referenceRepositoryRootURL() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
    }
    return url
}

private func loadReferenceCatalogFile() throws -> ReferenceCatalog {
    let url = referenceRepositoryRootURL()
        .appendingPathComponent("PersonalTrainer", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Seed", isDirectory: true)
        .appendingPathComponent("references.v1.json", isDirectory: false)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ReferenceCatalog.self, from: data)
}

/// Sentences end in ". " or at the final period; the catalog avoids abbreviations with dots.
private func sentenceCount(_ text: String) -> Int {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }
    let inner = trimmed.components(separatedBy: ". ").count - 1
    return inner + 1
}

/// In-memory catalogs for the validator. Defaults produce a valid catalog with one
/// reference and one topic; each negative test changes one thing.
private enum ReferenceFixture {
    static let referenceID = "author-2020-topic"

    /// Topic keys the M2 UI asks for (docs/M2-CONTRACT.md, `ReferenceCatalog` doc comment).
    static let requiredTopics = [
        "rule.P2", "rule.P4", "rule.P5", "rule.P6", "rule.P9", "rule.S2", "rule.D",
        "note.calibrate", "note.increase", "note.hold", "note.retry", "note.decrease", "note.returning", "note.deload",
        "goal.hypertrophy", "goal.strength", "goal.endurance", "goal.longevity", "goal.combat",
        "topic.rir", "topic.volume", "topic.frequency", "topic.maintenance", "topic.substitution",
        "topic.rest", "topic.concurrent", "topic.hrv", "topic.aerobic", "topic.vo2max",
    ]

    static func reference(
        id: String = referenceID,
        authors: String = "Author AB, Other C",
        year: Int = 2020,
        title: String = "A title",
        source: String = "A journal",
        doi: String? = "10.1000/test.2020.1",
        url: String? = nil,
        level: ScientificReference.EvidenceLevel = .metaAnalysis,
        summary: String = "Uma frase."
    ) -> ScientificReference {
        ScientificReference(
            id: id,
            authors: authors,
            year: year,
            title: title,
            source: source,
            doi: doi,
            url: url,
            level: level,
            summary: summary
        )
    }

    static func catalog(
        version: Int = 1,
        references: [ScientificReference] = [reference()],
        topics: [String: [String]] = ["topic.test": [referenceID]],
        explanations: [String: String] = ["topic.test": "Explicação."]
    ) -> ReferenceCatalog {
        ReferenceCatalog(version: version, references: references, topics: topics, explanations: explanations)
    }
}
