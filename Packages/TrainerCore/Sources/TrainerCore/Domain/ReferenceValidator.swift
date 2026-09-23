import Foundation

/// Why a `ReferenceCatalog` cannot be shown behind the "Por quê?" button (SPEC RF-32).
/// Each case names the offending reference id or topic key so a hand-edited
/// `references.v1.json` can be fixed without a debugger. Shares the file with
/// `ReferenceValidator`, as `SeedValidationError` does with `SeedValidator`
/// (docs/M2-CONTRACT.md §1 scopes both to `ReferenceValidator.swift`).
public enum ReferenceValidationError: Error, Equatable, Sendable {
    /// The catalog `version` must be ≥ 1; `ReferenceCatalog.empty` uses 0 to mean "not loaded".
    case invalidVersion(Int)
    /// Reference ids are stable kebab-case keys cited by `topics` (e.g. "schoenfeld-2017-volume").
    case invalidReferenceID(String)
    /// Two references share an id; a topic citing it would be ambiguous.
    case duplicateReferenceID(String)
    /// `authors`, `title`, `source` or `summary` is empty or only whitespace (SPEC §7.9:
    /// the sheet shows the complete reference). `field` is the JSON key.
    case missingField(referenceID: String, field: String)
    /// `year` outside `ReferenceValidator.allowedYears`, almost always a typo.
    case invalidYear(referenceID: String, year: Int)
    /// `doi` does not look like a bare DOI ("10.<registrant>/<suffix>", no URL prefix).
    case invalidDOI(referenceID: String, doi: String)
    /// `url` is present but is not an absolute http(s) URL.
    case invalidURL(referenceID: String, url: String)
    /// Neither `doi` nor `url`: the reader could not find the source.
    case missingLink(referenceID: String)
    /// A topic maps to no reference (SPEC §7.9: every rule has at least one reference).
    case emptyTopic(String)
    /// A topic cites an id that is not in `references`.
    case unknownReferenceID(String, topic: String)
    /// A topic cites the same reference twice.
    case duplicateReferenceInTopic(String, topic: String)
    /// A topic has no entry in `explanations`; the sheet would show references without context.
    case missingExplanation(topic: String)
    /// A topic's explanation is empty or only whitespace.
    case emptyExplanation(topic: String)
    /// An explanation exists for a key that is not in `topics` (typo in one of the two maps).
    case explanationWithoutTopic(String)
}

/// Structural validation of a decoded `ReferenceCatalog` (SPEC RF-32, §7.9). Pure and
/// deterministic: same catalog → same first error. Walks the references in file order,
/// then the topics and the explanations sorted by key (dictionary order is unspecified),
/// and stops at the first problem, so tests build one defect per catalog.
///
/// It checks form, not truth: whether a DOI really points to the cited paper is verified
/// by hand when the JSON is edited.
public enum ReferenceValidator {
    /// Plausible publication years; anything outside is a typo, not a real source.
    public static let allowedYears: ClosedRange<Int> = 1950...2100

    public static func validate(_ catalog: ReferenceCatalog) throws {
        guard catalog.version >= 1 else {
            throw ReferenceValidationError.invalidVersion(catalog.version)
        }
        let knownIDs = try validateReferences(catalog.references)
        try validateTopics(catalog.topics, knownIDs: knownIDs)
        try validateExplanations(catalog.explanations, topics: catalog.topics)
    }

    // MARK: - References

    /// Returns the set of reference ids for the topic checks.
    private static func validateReferences(_ references: [ScientificReference]) throws -> Set<String> {
        var seenIDs = Set<String>()
        for reference in references {
            guard isKebabCase(reference.id) else {
                throw ReferenceValidationError.invalidReferenceID(reference.id)
            }
            guard seenIDs.insert(reference.id).inserted else {
                throw ReferenceValidationError.duplicateReferenceID(reference.id)
            }
            try validateFields(of: reference)
        }
        return seenIDs
    }

    private static func validateFields(of reference: ScientificReference) throws {
        let requiredText: [(field: String, value: String)] = [
            ("authors", reference.authors),
            ("title", reference.title),
            ("source", reference.source),
            ("summary", reference.summary),
        ]
        for entry in requiredText where isBlank(entry.value) {
            throw ReferenceValidationError.missingField(referenceID: reference.id, field: entry.field)
        }
        guard allowedYears.contains(reference.year) else {
            throw ReferenceValidationError.invalidYear(referenceID: reference.id, year: reference.year)
        }
        if let doi = reference.doi {
            guard isWellFormedDOI(doi) else {
                throw ReferenceValidationError.invalidDOI(referenceID: reference.id, doi: doi)
            }
        }
        if let url = reference.url {
            guard isWebURL(url) else {
                throw ReferenceValidationError.invalidURL(referenceID: reference.id, url: url)
            }
        }
        // `ScientificReference.link` needs one of the two to open the source.
        guard reference.doi != nil || reference.url != nil else {
            throw ReferenceValidationError.missingLink(referenceID: reference.id)
        }
    }

    // MARK: - Topics and explanations

    private static func validateTopics(_ topics: [String: [String]], knownIDs: Set<String>) throws {
        for topic in topics.keys.sorted() {
            let ids = topics[topic] ?? []
            guard !ids.isEmpty else {
                throw ReferenceValidationError.emptyTopic(topic)
            }
            var seenInTopic = Set<String>()
            for id in ids {
                guard knownIDs.contains(id) else {
                    throw ReferenceValidationError.unknownReferenceID(id, topic: topic)
                }
                guard seenInTopic.insert(id).inserted else {
                    throw ReferenceValidationError.duplicateReferenceInTopic(id, topic: topic)
                }
            }
        }
    }

    private static func validateExplanations(_ explanations: [String: String], topics: [String: [String]]) throws {
        for topic in topics.keys.sorted() {
            guard let explanation = explanations[topic] else {
                throw ReferenceValidationError.missingExplanation(topic: topic)
            }
            guard !isBlank(explanation) else {
                throw ReferenceValidationError.emptyExplanation(topic: topic)
            }
        }
        for topic in explanations.keys.sorted() where topics[topic] == nil {
            throw ReferenceValidationError.explanationWithoutTopic(topic)
        }
    }

    // MARK: - Format helpers

    /// Lowercase ASCII letters and digits separated by single hyphens, e.g. `tanaka-2001-hrmax`
    /// (same rule as seed slugs).
    private static func isKebabCase(_ value: String) -> Bool {
        guard let first = value.first, let last = value.last,
              first != "-", last != "-", !value.contains("--") else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    /// Matches `^10\.\d{4,9}/\S+$`: the bare DOI form stored in the JSON, without the
    /// `https://doi.org/` prefix that `ScientificReference.link` adds. Hand-rolled instead of
    /// a regex to stay on plain Foundation on every platform that runs these tests.
    private static func isWellFormedDOI(_ doi: String) -> Bool {
        let scalars = Array(doi.unicodeScalars)
        guard scalars.count > 3, scalars[0] == "1", scalars[1] == "0", scalars[2] == "." else {
            return false
        }
        var index = 3
        var registrantDigits = 0
        while index < scalars.count, ("0"..."9").contains(scalars[index]) {
            registrantDigits += 1
            index += 1
        }
        guard (4...9).contains(registrantDigits), index < scalars.count, scalars[index] == "/" else {
            return false
        }
        let suffix = scalars[(index + 1)...]
        return !suffix.isEmpty && !suffix.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
