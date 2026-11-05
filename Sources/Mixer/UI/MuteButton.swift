import SwiftUI

struct MuteButton: View {
    let volume: Float
    let isMuted: Bool
    let appName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isMuted ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Reativar som do \(appName)" : "Silenciar \(appName)")
    }

    private var symbol: String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case 0: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}
