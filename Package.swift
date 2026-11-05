// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mixer",
    platforms: [.macOS("14.4")],
    targets: [
        // Operações atômicas sem lock pra thread de áudio (o módulo Synchronization só existe no macOS 15+).
        .target(name: "CAtomics", path: "Sources/CAtomics"),
        // Áudio e modelo, sem UI, pra poder testar.
        .target(name: "MixerCore", dependencies: ["CAtomics"], path: "Sources/MixerCore"),
        // O app de barra de menu (SwiftUI).
        .executableTarget(name: "Mixer", dependencies: ["MixerCore"], path: "Sources/Mixer"),
        // Etapa 1: spike de áudio em CLI. Sai do pacote depois que o fluxo for validado.
        .executableTarget(name: "Spike", path: "Sources/Spike"),
        // Demo do engine em CLI, pra testar as etapas 2 a 5 sem UI. Sai quando a UI existir.
        .executableTarget(name: "EngineDemo", dependencies: ["MixerCore"], path: "Sources/EngineDemo"),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"], path: "Tests/MixerCoreTests"),
    ]
)
