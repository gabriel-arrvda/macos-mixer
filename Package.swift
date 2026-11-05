// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mixer",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "MixerCore", targets: ["MixerCore"]),
        .executable(name: "Mixer", targets: ["Mixer"]),
    ],
    targets: [
        // Operações atômicas sem lock pra thread de áudio (o módulo Synchronization só existe no macOS 15+).
        .target(name: "CAtomics", path: "Sources/CAtomics"),
        // Áudio e modelo, sem UI, pra poder testar.
        .target(name: "MixerCore", dependencies: ["CAtomics"], path: "Sources/MixerCore"),
        // O app de barra de menu (SwiftUI).
        .executableTarget(name: "Mixer", dependencies: ["MixerCore"], path: "Sources/Mixer"),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"], path: "Tests/MixerCoreTests"),
    ]
)
