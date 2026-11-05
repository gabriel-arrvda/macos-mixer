import AppKit
import MixerCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: MixerState

    var body: some View {
        Group {
            if state.showsOnboarding {
                OnboardingView(onContinue: state.finishOnboarding)
            } else if state.showsPermissionHelp {
                PermissionView(onRetry: state.retryAfterPermission)
            } else {
                mainContent
            }
        }
        .frame(width: AppConstants.windowWidth)
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HeaderView(output: state.output, notice: state.outputNotice)
            Divider()
            if state.signal == .silent {
                SilenceBanner { state.showsPermissionHelp = true }
            }
            if state.entries.isEmpty {
                EmptyStateView()
            } else {
                AppList(entries: state.entries, state: state)
            }
            Divider()
            FooterView()
        }
    }
}

private struct AppList: View {
    let entries: [AppEntry]
    let state: MixerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    AppRow(entry: entry,
                           onVolume: { state.setVolume($0, for: entry.id) },
                           onToggleMute: { state.toggleMute(for: entry.id) })
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1, anchor: .top)))
                }
            }
            .padding(.vertical, 4)
            .animation(.easeOut(duration: 0.18), value: entries.map(\.id))
        }
        .frame(height: min(CGFloat(entries.count) * AppRow.height + 8, AppConstants.maxListHeight))
    }
}

private struct HeaderView: View {
    let output: OutputDevice?
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppConstants.name)
                .font(.system(size: 13, weight: .semibold))
            subtitle
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.init(top: 12, leading: 14, bottom: 10, trailing: 14))
        .animation(.easeInOut(duration: 0.15), value: notice)
    }

    @ViewBuilder private var subtitle: some View {
        if let notice {
            Label("Saída mudou para \(notice)", systemImage: "arrow.triangle.swap")
                .foregroundStyle(Color.accentColor)
                .transition(.opacity)
        } else if let output {
            Label("Saída: \(output.name)", systemImage: DeviceSymbol.name(for: output))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        } else {
            Text("Sem saída de áudio").foregroundStyle(.secondary)
        }
    }
}

/// Símbolo do cabeçalho conforme o tipo de saída.
enum DeviceSymbol {
    static func name(for device: OutputDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        switch device.transport {
        case .bluetooth: return "headphones"
        case .builtIn: return "laptopcomputer"
        case .usb: return "hifispeaker"
        case .hdmi: return "tv"
        case .other: return "speaker.wave.2"
        }
    }
}

private struct SilenceBanner: View {
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Não está chegando som. Verifique a permissão.")
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Verificar", action: onCheck)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
        .padding(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
        .padding(8)
        .accessibilityElement(children: .combine)
    }
}

private struct FooterView: View {
    var body: some View {
        HStack {
            FooterButton(title: "Ajustes de Som…") { Settings.open(AppConstants.soundSettingsURL, fallback: AppConstants.securitySettingsURL) }
            Spacer()
            FooterButton(title: "Sair") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(hovering ? .primary : .secondary)
            .onHover { hovering = $0 }
    }
}

enum Settings {
    /// Abre o painel direto; se o link falhar, abre só os Ajustes do Sistema.
    static func open(_ url: URL, fallback: URL) {
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(fallback) }
    }
}
