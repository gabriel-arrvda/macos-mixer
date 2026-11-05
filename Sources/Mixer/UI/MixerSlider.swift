import AppKit
import SwiftUI

/// Slider próprio porque o `Slider` nativo não deixa trocar o knob pelo marcador vazado do mudo.
/// Teclado: ←/→ mudam 5%, ⌥←/⌥→ mudam 1%.
struct MixerSlider: View {
    let value: Float
    let isMuted: Bool
    let isEnabled: Bool
    let label: String
    let onChange: (Float) -> Void

    private let knob: CGFloat = 12
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - knob, 1)
            let x = CGFloat(value) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18)).frame(height: trackHeight)
                Capsule().fill(Color.accentColor).frame(width: x + knob / 2, height: trackHeight)
                    .opacity(isMuted ? 0 : 1)
                marker.offset(x: x)
            }
            .opacity(isMuted ? 0.35 : 1)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled else { return }
                onChange(Float(min(max((drag.location.x - knob / 2) / travel, 0), 1)))
            })
        }
        .frame(height: 20)
        .opacity(isEnabled ? 1 : 0.4)
        .focusable(isEnabled)
        .onMoveCommand { direction in
            let step: Float = NSEvent.modifierFlags.contains(.option) ? 0.01 : 0.05
            switch direction {
            case .left, .down: onChange(max(value - step, 0))
            case .right, .up: onChange(min(value + step, 1))
            default: break
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isMuted ? "Mudo" : "\(Int((value * 100).rounded())) por cento")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.05, 1))
            case .decrement: onChange(max(value - 0.05, 0))
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var marker: some View {
        if isMuted {
            // Fader-fantasma: mostra pra onde o volume volta ao reativar.
            Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: knob, height: knob)
        } else {
            Circle().fill(.white).frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
        }
    }
}
