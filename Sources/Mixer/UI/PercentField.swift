import MixerCore
import SwiftUI

/// Caixa com a porcentagem que também aceita digitação: "75", "75%", "M" para silenciar.
/// Enter confirma, Esc cancela, ↑↓ mudam 1% (com Shift, 10%). Valor inválido mostra o erro e volta sozinho.
struct PercentField: View {
    let value: Float
    let maxValue: Float
    let isMuted: Bool
    let isEnabled: Bool
    let tint: Color
    let label: String
    let onInput: (VolumeInput) -> Void
    @Binding var error: String?

    @State private var text = ""
    @State private var initialText = ""
    @State private var revertWork: DispatchWorkItem?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private var percent: Int { Int((value * 100).rounded()) }
    private var display: String { isMuted ? "Mudo" : "\(percent)%" }
    private var editingText: String { isMuted ? "M" : "\(percent)" }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(foreground)
            .frame(width: 54, height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(border, lineWidth: 1))
            .focused($focused)
            .disabled(!isEnabled)
            .onAppear { text = display }
            .onChange(of: display) { _, newValue in if !focused { text = newValue } }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    text = editingText
                    initialText = text
                } else if text != initialText {
                    commit()
                } else {
                    text = display
                }
            }
            .onChange(of: text) { _, _ in if focused, error != nil { error = nil } }
            .onSubmit { if commit() { focused = false } }
            .onKeyPress(.escape) {
                error = nil
                text = editingText
                initialText = text
                focused = false
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let step: Float = press.modifiers.contains(.shift) ? 0.1 : 0.01
                let base: Float = Float(Int(text.filter(\.isNumber)) ?? percent) / 100
                let next = min(max(base + (press.key == .upArrow ? step : -step), 0), maxValue)
                onInput(next == 0 ? .mute : .volume(next))
                text = "\(Int((next * 100).rounded()))"
                initialText = text
                return .handled
            }
            .help("Digite um valor de 0 a \(Int(maxValue * 100)), ou M para silenciar")
            .accessibilityLabel(label)
    }

    /// Aplica o texto. Devolve falso se for inválido (o erro fica visível e o valor volta depois de 1,8 s).
    @discardableResult
    private func commit() -> Bool {
        let parsed = VolumeInput.parse(text, max: maxValue)
        guard parsed != .invalid else {
            error = "Digite um número de 0 a \(Int(maxValue * 100)), ou M para silenciar"
            let work = DispatchWorkItem { error = nil; if !focused { text = display } }
            revertWork?.cancel()
            revertWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
            return false
        }
        error = nil
        onInput(parsed)
        initialText = text
        return true
    }

    private var foreground: Color {
        if error != nil { return Palette.clip }
        if focused { return tint }
        if isMuted { return scheme == .dark ? .white : Palette.clip }
        return value > 1 ? Palette.boost : .secondary
    }

    private var background: Color {
        if focused { return tint.opacity(0.16) }
        if isMuted { return Palette.clip.opacity(scheme == .dark ? 0.55 : 0.14) }
        return Color.primary.opacity(0.06)
    }

    private var border: Color {
        if error != nil { return Palette.clip }
        return focused ? tint : .clear
    }
}
