#if DEBUG
import MixerCore
import SwiftUI

/// Um preview por estado da SPEC, com `MixerState` falso.
@MainActor private enum Fake {
    static func entry(_ name: String, volume: Float = 0.72, muted: Bool = false, status: SessionStatus = .active) -> AppEntry {
        AppEntry(owner: AppOwner(key: "fake.\(name)", name: name, pid: 0), volume: volume,
                 isMuted: muted, isPlaying: true, status: status)
    }
    static let output = OutputDevice(id: 1, uid: "x", name: "AirPods de Gabriel", transport: .bluetooth)
    static let apps = [entry("Chrome", volume: 1), entry("Discord", volume: 0.3), entry("Safari", muted: true),
                       entry("Spotify", volume: 0), entry("Teams", status: .connecting), entry("Zoom", status: .failed("x"))]

    static func state(entries: [AppEntry] = apps, signal: MixerState.Signal = .unknown, onboarding: Bool = false,
                      permission: Bool = false, notice: String? = nil) -> MixerState {
        MixerState(manager: nil, defaults: UserDefaults(suiteName: "preview")!, entries: entries, output: output,
                   signal: signal, showsOnboarding: onboarding, showsPermissionHelp: permission, outputNotice: notice)
    }
}

struct MenuContent_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            MenuContent(state: Fake.state()).previewDisplayName("Lista")
            MenuContent(state: Fake.state(entries: [])).previewDisplayName("Vazio")
            MenuContent(state: Fake.state(onboarding: true)).previewDisplayName("Primeira execução")
            MenuContent(state: Fake.state(permission: true)).previewDisplayName("Permissão faltando")
            MenuContent(state: Fake.state(signal: .silent)).previewDisplayName("Sem som chegando")
            MenuContent(state: Fake.state(notice: "MacBook Air Alto-falantes")).previewDisplayName("Troca de saída")
        }
    }
}
#endif
