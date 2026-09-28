import Foundation
import Testing
@testable import TrainerCore

// Paridade com a ferramenta de autoria (TASKS T6.4; docs/V23-CORE-CONTRACT.md §2.7). O golden é gravado por
// `merge-guides.ps1` (render-exercise-guides.ps1 -Golden) a partir do arquivo do bundle; como o Swift não roda na
// máquina de autoria, este teste é o que garante que o app desenha o que a folha de revisão mostrou.

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

private func goldenPoint(_ values: [Double]) throws -> GuidePoint {
    try #require(values.count == 2, "ponto do golden com \(values.count) números")
    return GuidePoint(x: values[0], y: values[1])
}

@Test("GuideGolden o Swift reproduz o golden da ferramenta em até 0,001 H: pontos, acessórios, moving e seta")
func guideGoldenParity() throws {
    let golden = try JSONDecoder().decode(GuideGoldenFile.self, from: Data(contentsOf: GuideTestSupport.goldenURL()))
    let catalog = try GuideTestSupport.bundleCatalog()
    #expect(golden.version == 1)
    let tolerance = golden.tolerance
    #expect(tolerance <= 0.001)
    #expect(Set(golden.guides.map(\.slug)) == Set(catalog.guides.map(\.slug)), "o golden cobre as mesmas guias do bundle")

    for entry in golden.guides {
        let guide = try #require(catalog.guide(forSlug: entry.slug), "\(entry.slug) sem guia no bundle")
        #expect(entry.samples.count == 5, "\(entry.slug)")
        for sample in entry.samples {
            let skeleton = GuideKinematics.skeleton(of: guide, at: sample.t)
            #expect(Set(skeleton.points.keys.map(\.rawValue)) == Set(sample.points.keys), "\(entry.slug) t=\(sample.t): pontos")
            for (name, values) in sample.points {
                let expected = try goldenPoint(values)
                let joint = try #require(GuideJoint(rawValue: name), "\(entry.slug): ponto desconhecido \(name)")
                let actual = try #require(skeleton.points[joint], "\(entry.slug) t=\(sample.t): sem \(name)")
                #expect(
                    abs(actual.x - expected.x) <= tolerance && abs(actual.y - expected.y) <= tolerance,
                    "\(entry.slug) t=\(sample.t) \(name): Swift \(actual) × golden \(expected)"
                )
            }
            #expect(Set(skeleton.props.keys) == Set(sample.props.keys), "\(entry.slug) t=\(sample.t): acessórios")
            for (id, values) in sample.props {
                let expected = try goldenPoint(values)
                let actual = try #require(skeleton.props[id], "\(entry.slug) t=\(sample.t): sem acessório \(id)")
                #expect(
                    abs(actual.x - expected.x) <= tolerance && abs(actual.y - expected.y) <= tolerance,
                    "\(entry.slug) t=\(sample.t) \(id): Swift \(actual) × golden \(expected)"
                )
            }
        }
        let moving = Set(GuideMotion.movingSegments(of: guide).map(\.rawValue))
        #expect(moving == Set(entry.moving), "\(entry.slug): moving Swift \(moving.sorted()) × golden \(entry.moving)")

        let path = GuideMotion.cuePath(of: guide)
        if entry.cue.isEmpty {
            #expect(path.isEmpty, "\(entry.slug): seta sem cue")
        } else {
            #expect(path.count == 41, "\(entry.slug): seta com \(path.count) pontos")
            let indices: [Int] = [0, 10, 20, 30, 40]
            #expect(entry.cue.count == indices.count, "\(entry.slug)")
            for (position, index) in indices.enumerated() where position < entry.cue.count && index < path.count {
                let expected = try goldenPoint(entry.cue[position])
                let actual = path[index]
                #expect(
                    abs(actual.x - expected.x) <= tolerance && abs(actual.y - expected.y) <= tolerance,
                    "\(entry.slug) seta[\(index)]: Swift \(actual) × golden \(expected)"
                )
            }
        }
    }
}
