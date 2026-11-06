#if DEBUG
import MixerCore
import SwiftUI

/// Um preview por estado, com `MixerState` falso.
@MainActor private enum Fake {
    static func entry(_ name: String, volume: Float = 0.72, muted: Bool = false, playing: Bool = true,
                      status: SessionStatus = .active, output: String? = nil) -> AppEntry {
        AppEntry(owner: AppOwner(key: "fake.\(name)", name: name, pid: 0), volume: volume,
                 isMuted: muted, isPlaying: playing, status: status, outputUID: output)
    }
    static let devices = [
        OutputDevice(id: 1, uid: "mbp", name: "Alto-falantes do MacBook Pro", transport: .builtIn),
        OutputDevice(id: 2, uid: "airpods", name: "AirPods Pro de Gabriel", transport: .bluetooth),
        OutputDevice(id: 3, uid: "tv", name: "TV da sala", transport: .airPlay),
    ]
    static let apps = [entry("Chrome", volume: 1.65), entry("Spotify", volume: 0.64, output: "airpods"),
                       entry("Discord", volume: 0.85), entry("Mensagens", volume: 0.3, muted: true, playing: false),
                       entry("Teams", status: .connecting), entry("Zoom", status: .failed("x"))]

    static func state(entries: [AppEntry]? = nil, signal: MixerState.Signal = .unknown, onboarding: Bool = false,
                      permission: Bool = false, notice: String? = nil) -> MixerState {
        MixerState(manager: nil, defaults: UserDefaults(suiteName: "preview")!, entries: entries ?? apps,
                   output: devices[0], devices: devices,
                   systemOutput: DeviceVolume(name: devices[0].name, volume: 0.19, isMuted: false),
                   microphone: DeviceVolume(name: "Microfone do MacBook Pro", volume: 0.2, isMuted: false),
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
            MenuContent(state: Fake.state(notice: "AirPods Pro de Gabriel")).previewDisplayName("Troca de saída")
        }
    }
}
#endif
