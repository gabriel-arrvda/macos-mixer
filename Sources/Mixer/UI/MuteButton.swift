import SwiftUI

/// Botão redondo de mudo. No escuro o ícone é branco; mudo fica vermelho.
struct MuteButton: View {
    enum Kind { case speaker, microphone }

    let isMuted: Bool
    let label: String
    var kind: Kind = .speaker
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isMuted ? "Ativar som" : "Silenciar")
        .accessibilityLabel(isMuted ? "Ativar som: \(label)" : "Silenciar: \(label)")
    }

    private var symbol: String {
        switch kind {
        case .speaker: return isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .microphone: return isMuted ? "mic.slash.fill" : "mic.fill"
        }
    }

    private var foreground: Color {
        if isMuted { return scheme == .dark ? .white : Palette.clip }
        return scheme == .dark ? .white : .primary.opacity(0.75)
    }

    private var background: Color {
        if isMuted { return Palette.clip.opacity(scheme == .dark ? 0.55 : 0.16) }
        return Color.primary.opacity(hovering ? 0.16 : 0.1)
    }
}
