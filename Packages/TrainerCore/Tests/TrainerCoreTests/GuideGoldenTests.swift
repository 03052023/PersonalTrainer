import Foundation
import Testing
@testable import TrainerCore

// Paridade com a ferramenta de autoria (TASKS T6.4; docs/V23-CORE-CONTRACT.md §2.7). Os goldens são gravados por
// `merge-guides.ps1` (render-exercise-guides.ps1 -Golden): um do arquivo do bundle e um do vocabulário, que usa
// todos os recursos do formato (farArm, legDepth, âncora na mão e "none", peito, acessório em segmento…). Como o
// Swift não roda na máquina de autoria, estes testes garantem que o app desenha o que a folha de revisão mostrou.

private struct GuideGoldenFile: Decodable {
    let version: Int
    let tolerance: Double
    let guides: [GuideGoldenEntry]
}

private struct GuideGoldenEntry: Decodable {
    let slug: String
    let samples: [GuideGoldenSample]
    let moving: [String]
    let cue: [[Double]]
}

private struct GuideGoldenSample: Decodable {
    let t: Double
    let points: [String: [Double]]
    let props: [String: [Double]]
}

private func goldenFixtureURL(_ fileName: String) -> URL {
    GuideTestSupport.goldenURL().deletingLastPathComponent().appendingPathComponent(fileName, isDirectory: false)
}

private func vocabularyURL() -> URL {
    GuideTestSupport.repositoryURL()
        .appendingPathComponent("docs", isDirectory: true)
        .appendingPathComponent("design", isDirectory: true)
        .appendingPathComponent("exercise-guides", isDirectory: true)
        .appendingPathComponent("vocabulary.sample.json", isDirectory: false)
}

private func goldenPoint(_ values: [Double]) throws -> GuidePoint {
    try #require(values.count == 2, "ponto do golden com \(values.count) números")
    return GuidePoint(x: values[0], y: values[1])
}

private func isWithin(_ actual: GuidePoint, _ expected: GuidePoint, _ tolerance: Double) -> Bool {
    abs(actual.x - expected.x) <= tolerance && abs(actual.y - expected.y) <= tolerance
}

/// Compara cada guia do catálogo com o golden: pontos e acessórios nos 5 instantes, `moving` e 5 pontos da seta.
private func expectParity(of catalog: ExerciseGuideCatalog, withGoldenAt url: URL) throws {
    let golden = try JSONDecoder().decode(GuideGoldenFile.self, from: Data(contentsOf: url))
    #expect(golden.version == 1)
    let tolerance = golden.tolerance
    #expect(tolerance <= 0.001)
    let goldenSlugs = Set(golden.guides.map(\.slug))
    let catalogSlugs = Set(catalog.guides.map(\.slug))
    #expect(goldenSlugs == catalogSlugs, "o golden cobre as mesmas guias do arquivo")

    for entry in golden.guides {
        let guide = try #require(catalog.guide(forSlug: entry.slug), "\(entry.slug) sem guia no arquivo")
        #expect(entry.samples.count == 5, "\(entry.slug)")
        for sample in entry.samples {
            let skeleton = GuideKinematics.skeleton(of: guide, at: sample.t)
            let names = Set(skeleton.points.keys.map(\.rawValue))
            #expect(names == Set(sample.points.keys), "\(entry.slug) t=\(sample.t): pontos")
            for (name, values) in sample.points {
                let expected = try goldenPoint(values)
                let joint = try #require(GuideJoint(rawValue: name), "\(entry.slug): ponto desconhecido \(name)")
                let actual = try #require(skeleton.points[joint], "\(entry.slug) t=\(sample.t): sem \(name)")
                #expect(isWithin(actual, expected, tolerance), "\(entry.slug) t=\(sample.t) \(name): Swift \(actual) × golden \(expected)")
            }
            let propIDs = Set(skeleton.props.keys)
            #expect(propIDs == Set(sample.props.keys), "\(entry.slug) t=\(sample.t): acessórios")
            for (id, values) in sample.props {
                let expected = try goldenPoint(values)
                let actual = try #require(skeleton.props[id], "\(entry.slug) t=\(sample.t): sem acessório \(id)")
                #expect(isWithin(actual, expected, tolerance), "\(entry.slug) t=\(sample.t) \(id): Swift \(actual) × golden \(expected)")
            }
        }
        let moving = Set(GuideMotion.movingSegments(of: guide).map(\.rawValue))
        #expect(moving == Set(entry.moving), "\(entry.slug): moving Swift \(moving.sorted()) × golden \(entry.moving)")

        let path = GuideMotion.cuePath(of: guide)
        if entry.cue.isEmpty {
            #expect(path.isEmpty, "\(entry.slug): seta sem cue")
            continue
        }
        #expect(path.count == 41, "\(entry.slug): seta com \(path.count) pontos")
        let indices: [Int] = [0, 10, 20, 30, 40]
        #expect(entry.cue.count == indices.count, "\(entry.slug)")
        for (position, index) in indices.enumerated() where position < entry.cue.count && index < path.count {
            let expected = try goldenPoint(entry.cue[position])
            let actual = path[index]
            #expect(isWithin(actual, expected, tolerance), "\(entry.slug) seta[\(index)]: Swift \(actual) × golden \(expected)")
        }
    }
}

@Test("GuideGolden o Swift reproduz o golden do arquivo do bundle em até 0,001 H: pontos, acessórios, moving e seta")
func guideGoldenParityWithBundle() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    try expectParity(of: catalog, withGoldenAt: GuideTestSupport.goldenURL())
}

@Test("GuideGolden o vocabulário (todos os recursos do formato) passa no validador e reproduz o golden da ferramenta")
func guideGoldenParityWithVocabulary() throws {
    let catalog = try ExerciseGuideCatalog.decode(Data(contentsOf: vocabularyURL()))
    #expect(catalog.guides.count >= 15)
    // o -Check da ferramenta roda o vocabulário com o catálogo desligado; o Swift tem de concordar
    let problems = ExerciseGuideValidator.problems(in: catalog, exercises: [], checkingCatalog: false)
    #expect(problems.isEmpty, "\(problems)")
    try expectParity(of: catalog, withGoldenAt: goldenFixtureURL("exercise-guides-vocabulary-golden.v1.json"))
}
