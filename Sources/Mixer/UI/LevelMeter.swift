import SwiftUI

/// Medidor de LEDs em uma linha. A escala é em dB (−54 a 0 dBFS), como numa mesa de som:
/// a cor do canal até −6 dB, laranja até −1,5 dB e vermelho perto do limite.
struct LevelMeter: View {
    @ObservedObject var monitor: LevelMonitor
    let key: String
    let tint: Color
    var isActive = true
    @Environment(\.colorScheme) private var scheme

    static let segments = 28

    var body: some View {
        let lit = isActive ? Self.litSegments(for: monitor.level(key)) : 0
        Canvas { context, size in
            let gap: CGFloat = 2
            let width = (size.width - gap * CGFloat(Self.segments - 1)) / CGFloat(Self.segments)
            for index in 0..<Self.segments {
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
                let color: Color = index < lit ? Self.color(index, tint: tint) : .primary.opacity(0.08)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
            }
        }
        .frame(height: 7)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(scheme == .dark ? 0.3 : 0.06)))
        .accessibilityHidden(true)
    }

    static func litSegments(for amplitude: Float) -> Int {
        guard amplitude > 0 else { return 0 }
        let db = 20 * log10(max(amplitude, 0.00001))
        let fraction = min(max((db + 54) / 54, 0), 1)
        return Int((fraction * Float(segments)).rounded())
    }

    private static func color(_ index: Int, tint: Color) -> Color {
        let fraction = Float(index + 1) / Float(segments)
        if fraction > 0.97 { return Palette.clip }
        if fraction > 0.89 { return Palette.boost }
        return tint
    }
}
