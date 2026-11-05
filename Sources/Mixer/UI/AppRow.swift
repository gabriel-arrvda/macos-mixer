import AppKit
import MixerCore
import SwiftUI

struct AppRow: View {
    static let height: CGFloat = 44

    let entry: AppEntry
    let onVolume: (Float) -> Void
    let onToggleMute: () -> Void

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(owner: entry.owner).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.owner.name)
                        .font(.system(size: 13))
                        .foregroundStyle(entry.isMuted ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    trailing
                }
                bottom
            }
            MuteButton(volume: entry.volume, isMuted: entry.isMuted, appName: entry.owner.name, action: onToggleMute)
                .disabled(!isReady)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var isReady: Bool { entry.status == .active }

    @ViewBuilder private var trailing: some View {
        switch entry.status {
        case .connecting:
            ProgressView().controlSize(.mini)
        case .failed:
            EmptyView()
        case .active:
            Text(entry.isMuted ? "Mudo" : "\(Int((entry.volume * 100).rounded()))%")
                .font(.system(size: 11, weight: dragging ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(dragging && !entry.isMuted ? .primary : .secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    @ViewBuilder private var bottom: some View {
        if case .failed = entry.status {
            Label("Não deu pra controlar este app", systemImage: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(height: 20, alignment: .leading)
        } else {
            MixerSlider(value: entry.volume, isMuted: entry.isMuted, isEnabled: isReady,
                        label: "Volume do \(entry.owner.name)") { newValue in
                dragging = true
                onVolume(newValue)
                scheduleDragEnd()
            }
        }
    }

    @State private var dragEnd: DispatchWorkItem?

    private func scheduleDragEnd() {
        dragEnd?.cancel()
        let work = DispatchWorkItem { dragging = false }
        dragEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

private struct AppIconView: View {
    let owner: AppOwner

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: owner.pid)?.icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.dashed").font(.system(size: 20)).foregroundStyle(.tertiary)
        }
    }
}
