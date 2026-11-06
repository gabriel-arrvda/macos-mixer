import Foundation

/// O que foi digitado na caixa de porcentagem.
public enum VolumeInput: Equatable, Sendable {
    /// Volume em 0...max (1 = 100%).
    case volume(Float)
    case mute
    case invalid

    /// Aceita "75", "75%", "75,5" (arredonda), e "M", "mudo", "mute", "0" ou "0%" para silenciar.
    /// `max` é o teto em fração (1 = 100%, 4 = 400%).
    public static func parse(_ text: String, max: Float) -> VolumeInput {
        let raw = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        if ["m", "mudo", "mute"].contains(raw) { return .mute }
        var number = raw
        if number.hasSuffix("%") { number.removeLast() }
        number = number.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, number.allSatisfy({ $0.isNumber || $0 == "." }),
              let value = Double(number), value.isFinite else { return .invalid }
        let percent = value.rounded()
        guard percent <= Double(max) * 100 else { return .invalid }
        return percent == 0 ? .mute : .volume(Float(percent / 100))
    }
}
