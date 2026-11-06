import AppKit
import SwiftUI

@main
struct MixerApp: App {
    @StateObject private var state = MixerState.live()

    init() {
        SingleInstance.enforce()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            MenuBarLabel(attention: state.needsAttention)
                // O ícone da barra aparece logo na abertura: é quando o NSApp já existe pra receber o tema.
                .task { AppearanceMode.current.apply() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ícone template da barra de menu. Sem o asset (rodando via `swift run`), cai no SF Symbol.
private struct MenuBarLabel: View {
    let attention: Bool

    var body: some View {
        if let image = NSImage(named: attention ? "MenuBarIconAttention" : "MenuBarIcon") {
            Image(nsImage: templated(image))
        } else {
            Image(systemName: attention ? "exclamationmark.circle" : "slider.vertical.3")
        }
    }

    private func templated(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

/// Duas instâncias capturariam o áudio uma da outra (retroalimentação). Fica só a primeira.
enum SingleInstance {
    static func enforce() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { exit(0) }
    }
}
