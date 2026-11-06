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
                MixerPanel(state: state)
            }
        }
        .frame(width: AppConstants.windowWidth)
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
        .onAppear { AppearanceMode.current.apply() }
    }
}

/// Painel principal. Teclado: ↑↓ escolhem o canal, ←→ mudam 5% (Shift: 10%), M silencia, S escolhe a saída.
private struct MixerPanel: View {
    @ObservedObject var state: MixerState
    @State private var selection: String?
    @FocusState private var panelFocused: Bool

    private static let outputID = "__saida__", micID = "__mic__"

    private var channelIDs: [String] {
        var ids = [Self.outputID]
        if state.microphone.name != nil { ids.append(Self.micID) }
        return ids + state.entries.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceHeader(output: state.output, microphone: state.microphone.name, notice: state.outputNotice,
                         action: showSystemOutputMenu)
            SystemRow(direction: .output, volume: state.systemOutput, levels: state.levels,
                      isSelected: selection == Self.outputID,
                      onVolume: { state.setSystemVolume($0, .output) },
                      onToggleMute: { state.toggleSystemMute(.output) })
                .simultaneousGesture(TapGesture().onEnded { selection = Self.outputID })
            if state.microphone.name != nil {
                SystemRow(direction: .input, volume: state.microphone, levels: state.levels,
                          isSelected: selection == Self.micID,
                          onVolume: { state.setSystemVolume($0, .input) },
                          onToggleMute: { state.toggleSystemMute(.input) })
                    .simultaneousGesture(TapGesture().onEnded { selection = Self.micID })
            }
            divider
            if state.signal == .silent {
                SilenceBanner { state.showsPermissionHelp = true }
            }
            SectionTitle(text: "APPS", count: state.entries.count)
            if state.entries.isEmpty {
                EmptyStateView()
            } else {
                AppList(state: state, selection: $selection, onRoute: showRouteMenu)
            }
            divider
            FooterView()
        }
        .padding(8)
        .focusable()
        .focusEffectDisabled()
        .focused($panelFocused)
        .onAppear {
            panelFocused = true
            state.levels.start()
        }
        .onDisappear { state.levels.stop() }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            moveSelection(press.key == .downArrow ? 1 : -1)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard let selection else { return .ignored }
            let step: Float = press.modifiers.contains(.shift) ? 0.1 : 0.05
            nudge(selection, by: press.key == .rightArrow ? step : -step)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "mMsS")) { press in
            guard let selection else { return .ignored }
            if press.characters.lowercased() == "m" { toggleMute(selection) } else { openRoute(selection) }
            return .handled
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5).padding(.horizontal, 8).padding(.vertical, 6)
    }

    // MARK: - Teclado

    private func moveSelection(_ delta: Int) {
        let ids = channelIDs
        guard !ids.isEmpty else { return }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = ids.first
            return
        }
        selection = ids[(index + delta + ids.count) % ids.count]
    }

    private func nudge(_ id: String, by step: Float) {
        switch id {
        case Self.outputID: state.setSystemVolume((state.systemOutput.volume ?? 0) + step, .output)
        case Self.micID: state.setSystemVolume((state.microphone.volume ?? 0) + step, .input)
        default:
            guard let entry = state.entries.first(where: { $0.id == id }), entry.status == .active else { return }
            state.setVolume(min(max(entry.volume + step, 0), AppVolume.maxVolume), for: id)
        }
    }

    private func toggleMute(_ id: String) {
        switch id {
        case Self.outputID: state.toggleSystemMute(.output)
        case Self.micID: state.toggleSystemMute(.input)
        default: state.toggleMute(for: id)
        }
    }

    private func openRoute(_ id: String) {
        if id == Self.outputID || id == Self.micID { showSystemOutputMenu(); return }
        if let entry = state.entries.first(where: { $0.id == id }) { showRouteMenu(entry) }
    }

    // MARK: - Menus de saída

    private func showSystemOutputMenu() {
        var items: [PopupMenu.Item] = [.header("Saída do sistema")]
        items += state.devices.map { device in
            .action(title: device.name, symbol: DeviceSymbol.name(for: device), checked: device.uid == state.output?.uid) {
                state.setSystemOutput(device)
            }
        }
        PopupMenu.show(items)
    }

    private func showRouteMenu(_ entry: AppEntry) {
        let defaultName = state.output?.name ?? "saída padrão"
        var items: [PopupMenu.Item] = [
            .header("Tocar \(entry.owner.name) em"),
            .action(title: "Padrão do sistema (\(defaultName))", symbol: "arrow.triangle.branch",
                    checked: entry.outputUID == nil) { state.setOutput(nil, for: entry.id) },
            .separator,
        ]
        items += state.devices.map { device in
            .action(title: device.name, symbol: DeviceSymbol.name(for: device), checked: entry.outputUID == device.uid) {
                state.setOutput(device.uid, for: entry.id)
            }
        }
        PopupMenu.show(items)
    }
}

private struct AppList: View {
    @ObservedObject var state: MixerState
    @Binding var selection: String?
    let onRoute: (AppEntry) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Altura aproximada de uma linha de app, pra decidir quando a lista precisa rolar.
    private static let rowHeight: CGFloat = 112

    var body: some View {
        let list = LazyVStack(spacing: 2) {
            ForEach(state.entries) { entry in
                AppRow(entry: entry, devices: state.devices, systemOutput: state.output, levels: state.levels,
                       isSelected: selection == entry.id,
                       onVolume: { state.setVolume($0, for: entry.id) },
                       onMute: { state.setMuted($0, for: entry.id) },
                       onToggleMute: { state.toggleMute(for: entry.id) },
                       onRoute: { onRoute(entry) })
                    .simultaneousGesture(TapGesture().onEnded { selection = entry.id })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.entries.map(\.id))

        if CGFloat(state.entries.count) * Self.rowHeight > AppConstants.maxListHeight {
            ScrollView { list }.frame(height: AppConstants.maxListHeight)
        } else {
            list
        }
    }
}

/// Cartão do dispositivo de saída. Clicar abre a lista de saídas do sistema.
private struct DeviceHeader: View {
    let output: OutputDevice?
    let microphone: String?
    let notice: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: output.map(DeviceSymbol.name(for:)) ?? "speaker.slash")
                    .font(.system(size: 17))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(output?.name ?? "Sem saída de áudio")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                    subtitle
                        .font(.system(size: 11))
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: notice)
        .accessibilityLabel("Saída: \(output?.name ?? "nenhuma"). Escolher saída")
    }

    @ViewBuilder private var subtitle: some View {
        if let notice {
            Label("Saída mudou para \(notice)", systemImage: "arrow.triangle.swap")
                .foregroundStyle(Color.accentColor)
                .transition(.opacity)
        } else {
            let parts = [output.map { "Saída · \(DeviceSymbol.kind(of: $0))" }, microphone.map { "Mic: \($0)" }]
            Text(parts.compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.tertiary)
                .transition(.opacity)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
            if count > 0 {
                Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

private struct SilenceBanner: View {
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Não está chegando som. Verifique a permissão ou se o conteúdo é protegido.")
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Verificar", action: onCheck)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
        .padding(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Rodapé: Ajustes (tema e atalho pros Ajustes de Som), dicas de teclado e Sair.
private struct FooterView: View {
    var body: some View {
        HStack(spacing: 8) {
            FooterButton(action: showSettingsMenu) {
                Label("Ajustes", systemImage: "gearshape")
            }
            Text("↑↓ canal · ←→ vol · M mudo · S saída")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity)
            FooterButton(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 4) {
                    Text("Sair")
                    Text("⌘Q").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 2)
        .frame(height: 30)
    }

    @MainActor private func showSettingsMenu() {
        let current = AppearanceMode.current
        var items: [PopupMenu.Item] = [.header("Aparência")]
        items += AppearanceMode.allCases.map { mode in
            .action(title: mode.title, symbol: mode.symbol, checked: mode == current) { AppearanceMode.select(mode) }
        }
        items += [
            .separator,
            .action(title: "Abrir Ajustes de Som do Mac…", symbol: "gearshape") {
                Settings.open(AppConstants.soundSettingsURL, fallback: AppConstants.securitySettingsURL)
            },
        ]
        PopupMenu.show(items)
    }
}

private struct FooterButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(hovering ? .primary : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .onHover { hovering = $0 }
    }
}

enum Settings {
    /// Abre o painel direto; se o link falhar, abre só os Ajustes do Sistema.
    static func open(_ url: URL, fallback: URL) {
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(fallback) }
    }
}
