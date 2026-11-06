import MixerCore
import SwiftUI

/// Linha do volume geral da saída ou do microfone (controles do próprio dispositivo, 0...100%).
struct SystemRow: View {
    let direction: SystemAudio.Direction
    let volume: DeviceVolume
    @ObservedObject var levels: LevelMonitor
    let isSelected: Bool
    let onVolume: (Float) -> Void
    let onToggleMute: () -> Void

    @State private var error: String?
    @Environment(\.colorScheme) private var scheme

    private var isMic: Bool { direction == .input }
    private var isMuted: Bool { volume.isMuted ?? false }
    private var tint: Color { isMic ? Palette.mic : (scheme == .dark ? .white : Color.primary.opacity(0.6)) }
    private var name: String { isMic ? "Microfone" : "Volume geral" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isMic {
                Text("MIC · \((volume.name ?? "Microfone").uppercased())")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if let level = volume.volume {
                HStack(alignment: .top, spacing: 10) {
                    MuteButton(isMuted: isMuted, label: name, kind: isMic ? .microphone : .speaker, action: onToggleMute)
                        .disabled(volume.isMuted == nil)
                        .padding(.top, isMic ? 0 : RowMetrics.controlsTop)
                    VStack(spacing: 6) {
                        if !isMic { LevelMeter(monitor: levels, key: LevelMonitor.outputKey, tint: tint, isActive: !isMuted) }
                        MixerSlider(value: level, maxValue: 1, isMuted: isMuted, isEnabled: true, tint: tint,
                                    label: name, onChange: onVolume)
                    }
                    PercentField(value: level, maxValue: 1, isMuted: isMuted, isEnabled: true, tint: tint,
                                 label: "Porcentagem: \(name)", onInput: apply, error: $error)
                        .frame(width: RowMetrics.trailing)
                        .padding(.top, isMic ? 0 : RowMetrics.controlsTop - 1)
                }
            } else {
                Text(isMic ? "Este microfone não tem controle de volume." : "Esta saída não tem controle de volume.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.clip)
                    .padding(.leading, RowMetrics.leading + 10)
            }
        }
        .modifier(RowBackground(isSelected: isSelected))
        .accessibilityElement(children: .contain)
    }

    private func apply(_ input: VolumeInput) {
        switch input {
        case .volume(let value): onVolume(value)
        case .mute: if !isMuted { onToggleMute() }
        case .invalid: break
        }
    }
}
