import AppKit
import MixerCore
import SwiftUI

/// Colunas comuns a todas as linhas, pra os faders terem a mesma largura e o olho não saltar.
enum RowMetrics {
    static let leading: CGFloat = 28
    static let trailing: CGFloat = 54
    static let controlsTop: CGFloat = 14
}

/// Fundo da linha: destaque leve ao passar o mouse e contorno quando é a linha escolhida pelo teclado.
struct RowBackground: ViewModifier {
    let isSelected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isSelected || hovering ? 0.055 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(isSelected ? 0.1 : 0), lineWidth: 1))
            .onHover { hovering = $0 }
    }
}

/// Linha de um app: ícone, nome, porcentagem; embaixo mudo, medidor com fader e o botão de saída.
struct AppRow: View {
    let entry: AppEntry
    let devices: [OutputDevice]
    let systemOutput: OutputDevice?
    @ObservedObject var levels: LevelMonitor
    let isSelected: Bool
    let onVolume: (Float) -> Void
    let onMute: (Bool) -> Void
    let onToggleMute: () -> Void
    let onRoute: () -> Void

    @State private var error: String?
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { IconPalette.color(for: entry.owner, scheme: scheme) }
    private var isReady: Bool { entry.status == .active }
    private var routed: OutputDevice? { entry.outputUID.flatMap { uid in devices.first { $0.uid == uid } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AppIconView(owner: entry.owner)
                    .frame(width: RowMetrics.leading, height: RowMetrics.leading)
                    .saturation(entry.isMuted ? 0 : 1)
                    .opacity(entry.isMuted ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.owner.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(entry.isMuted ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.tail)
                    subtitle
                }
                Spacer(minLength: 4)
                if entry.status == .connecting { ProgressView().controlSize(.mini) }
                PercentField(value: entry.volume, maxValue: AppVolume.maxVolume, isMuted: entry.isMuted,
                             isEnabled: isReady, tint: tint, label: "Porcentagem: \(entry.owner.name)",
                             onInput: apply, error: $error)
            }
            if case .failed = entry.status {
                Label("Não deu pra controlar este app", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.leading, RowMetrics.leading + 10)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    MuteButton(isMuted: entry.isMuted, label: entry.owner.name, action: onToggleMute)
                        .disabled(!isReady)
                        .padding(.top, RowMetrics.controlsTop)
                    VStack(spacing: 6) {
                        LevelMeter(monitor: levels, key: entry.id, tint: tint, isActive: !entry.isMuted)
                        MixerSlider(value: entry.volume, maxValue: AppVolume.maxVolume, isMuted: entry.isMuted,
                                    isEnabled: isReady, tint: tint, label: "Volume: \(entry.owner.name)", onChange: onVolume)
                    }
                    RouteButton(device: routed, tint: tint, appName: entry.owner.name, action: onRoute)
                        .frame(width: RowMetrics.trailing)
                        .padding(.top, RowMetrics.controlsTop - 2)
                }
            }
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.clip)
                    .padding(.leading, RowMetrics.leading + 10)
                    .transition(.opacity)
            }
        }
        .modifier(RowBackground(isSelected: isSelected))
        .animation(.easeOut(duration: 0.15), value: error)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: some View {
        HStack(spacing: 0) {
            Text(entry.isPlaying ? "Tocando" : "Sem som agora")
            if let routed {
                Text(" · ")
                Label(routed.name, systemImage: "arrow.turn.down.right").labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .lineLimit(1).truncationMode(.middle)
    }

    private func apply(_ input: VolumeInput) {
        switch input {
        case .volume(let value): onVolume(value)
        case .mute: onMute(true)
        case .invalid: break
        }
    }
}

/// Escolhe em qual saída o app toca. Neutro quando segue o padrão; na cor do app, com o ícone
/// do dispositivo, quando o som foi mandado pra outro lugar.
struct RouteButton: View {
    let device: OutputDevice?
    let tint: Color
    let appName: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: device.map(DeviceSymbol.name(for:)) ?? "arrow.triangle.branch")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(device != nil ? tint : (hovering ? Color.primary : Color.secondary))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(device != nil ? tint.opacity(0.18) : Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(device != nil ? tint.opacity(0.7) : Color.primary.opacity(hovering ? 0.2 : 0.08), lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(device.map { "Tocando em \($0.name)" } ?? "Escolher saída")
        .accessibilityLabel("Saída de \(appName): \(device?.name ?? "padrão do sistema")")
    }
}

struct AppIconView: View {
    let owner: AppOwner

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: owner.pid)?.icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.dashed").font(.system(size: 20)).foregroundStyle(.tertiary)
        }
    }
}
