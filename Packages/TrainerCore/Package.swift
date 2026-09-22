// swift-tools-version: 6.0
// TrainerCore: domínio, motor de treino e DTOs de sync.
// Regra R1 (AGENTS.md): este pacote só importa Foundation.
import PackageDescription

let package = Package(
    name: "TrainerCore",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v14), // permite `swift test` em Mac sem simulador
    ],
    products: [
        .library(name: "TrainerCore", targets: ["TrainerCore"]),
    ],
    targets: [
        .target(
            name: "TrainerCore",
            path: "Sources/TrainerCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "TrainerCoreTests",
            dependencies: ["TrainerCore"],
            path: "Tests/TrainerCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
