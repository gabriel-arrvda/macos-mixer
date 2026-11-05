// swift-tools-version:5.9
import PackageDescription

// Ferramentas de teste manual do áudio, fora do build padrão do app.
// Uso: cd Tools && swift build && .build/debug/Spike --list
let package = Package(
    name: "MixerTools",
    platforms: [.macOS("14.4")],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(name: "Spike", path: "Spike"),
        .executableTarget(name: "EngineDemo",
                          dependencies: [.product(name: "MixerCore", package: "Mixer")],
                          path: "EngineDemo"),
    ]
)
