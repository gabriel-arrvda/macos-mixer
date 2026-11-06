import AppKit
import SwiftUI

/// Escala do fader. Até 100% é linear; com ganho extra (até 400%), o 100% ("U") fica em 62,5% do trilho
/// e o resto do trilho cobre 100%...400%, pra o ajuste fino do volume normal não ficar espremido.
struct FaderScale {
    let maxValue: Float
    static let unityPosition: CGFloat = 0.625

    var unity: CGFloat { maxValue > 1 ? Self.unityPosition : 1 }

    func position(of value: Float) -> CGFloat {
        let value = min(max(value, 0), maxValue)
        guard maxValue > 1 else { return CGFloat(value) }
        if value <= 1 { return CGFloat(value) * unity }
        return unity + CGFloat((value - 1) / (maxValue - 1)) * (1 - unity)
    }

    func value(at position: CGFloat) -> Float {
        let position = min(max(position, 0), 1)
        guard maxValue > 1 else { return Float(position) }
        if position <= unity { return Float(position / unity) }
        return 1 + Float((position - unity) / (1 - unity)) * (maxValue - 1)
    }
}

/// Fader com marcas, "U" no 100% e trilho na cor do app. O knob é retangular, como numa mesa de som.
/// Arrastar perto do 100% gruda no 100%. O teclado é tratado pela lista (↑↓ escolhem, ←→ ajustam).
struct MixerSlider: View {
    let value: Float
    let maxValue: Float
    let isMuted: Bool
    let isEnabled: Bool
    let tint: Color
    let label: String
    let onChange: (Float) -> Void

    private let knobSize = CGSize(width: 14, height: 22)
    private let trackHeight: CGFloat = 3

    private var scale: FaderScale { FaderScale(maxValue: maxValue) }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let travel = max(proxy.size.width - knobSize.width, 1)
                let x = scale.position(of: value) * travel
                ZStack(alignment: .topLeading) {
                    ticks(width: proxy.size.width, travel: travel)
                        .offset(y: 17)
                    Capsule().fill(Color.primary.opacity(0.16))
                        .frame(height: trackHeight).offset(y: 10)
                    Capsule().fill(isMuted ? Color.secondary.opacity(0.5) : tint)
                        .frame(width: x + knobSize.width / 2, height: trackHeight).offset(y: 10)
                    knob.offset(x: x)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    guard isEnabled else { return }
                    var next = scale.value(at: (drag.location.x - knobSize.width / 2) / travel)
                    if maxValue > 1, abs(next - 1) < 0.04 { next = 1 }
                    onChange(next)
                })
            }
            .frame(height: 24)
            labels
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isMuted ? "Mudo" : "\(Int((value * 100).rounded())) por cento")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.05, maxValue))
            case .decrement: onChange(max(value - 0.05, 0))
            @unknown default: break
            }
        }
    }

    private var knob: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: .controlColor))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
            .overlay(Rectangle().fill(isMuted ? Color.secondary : Color.primary.opacity(0.85)).frame(width: 2, height: 12))
            .frame(width: knobSize.width, height: knobSize.height)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    private func ticks(width: CGFloat, travel: CGFloat) -> some View {
        Canvas { context, size in
            let count = maxValue > 1 ? 16 : 8
            for index in 0...count {
                let x = knobSize.width / 2 + CGFloat(index) / CGFloat(count) * travel
                context.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: 4)), with: .color(.primary.opacity(0.18)))
            }
            let unityX = knobSize.width / 2 + scale.unity * travel
            context.fill(Path(CGRect(x: unityX - 0.5, y: -1, width: 1, height: 6)), with: .color(Palette.boost))
        }
        .frame(width: width, height: 6)
        .allowsHitTesting(false)
    }

    private var labels: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - knobSize.width, 1)
            let origin = knobSize.width / 2
            ZStack(alignment: .topLeading) {
                mark("∞").position(x: origin, y: 6)
                mark("U", color: Palette.boost).position(x: origin + scale.unity * travel, y: 6)
                if maxValue > 1 { mark("\(Int(maxValue))×").position(x: origin + travel, y: 6) }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func mark(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.system(size: 9, design: .monospaced)).foregroundStyle(color.opacity(0.8))
    }
}
