import Foundation

public struct AppVolume: Equatable, Sendable {
    public var volume: Float
    public var isMuted: Bool

    public static let `default` = AppVolume(volume: 1, isMuted: false)
    /// Volume máximo (400%). Acima de 1 é ganho extra; a saída continua limitada em ±1.
    public static let maxVolume: Float = 4

    /// Limita a 0...`maxVolume`. NaN vira 1.
    public static func clamp(_ volume: Float) -> Float {
        volume.isNaN ? 1 : min(max(volume, 0), maxVolume)
    }

    public init(volume: Float, isMuted: Bool) {
        self.volume = volume
        self.isMuted = isMuted
    }

    /// Ganho aplicado na thread de áudio.
    public var effectiveGain: Float { isMuted ? 0 : volume }
}

/// Guarda volume e mudo por app (chave do dono) no `UserDefaults`.
public final class VolumeStore {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "mixer") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func load(_ key: String) -> AppVolume {
        guard let stored = defaults.object(forKey: volumeKey(key)) as? Double, stored.isFinite else {
            return AppVolume(volume: AppVolume.default.volume, isMuted: defaults.bool(forKey: mutedKey(key)))
        }
        return AppVolume(volume: AppVolume.clamp(Float(stored)), isMuted: defaults.bool(forKey: mutedKey(key)))
    }

    public func save(_ value: AppVolume, for key: String) {
        defaults.set(Double(AppVolume.clamp(value.volume)), forKey: volumeKey(key))
        defaults.set(value.isMuted, forKey: mutedKey(key))
    }

    /// Saída escolhida pro app (UID do dispositivo). `nil` = segue a saída padrão do sistema.
    public func loadOutput(_ key: String) -> String? {
        defaults.string(forKey: outputKey(key))
    }

    public func saveOutput(_ uid: String?, for key: String) {
        if let uid { defaults.set(uid, forKey: outputKey(key)) } else { defaults.removeObject(forKey: outputKey(key)) }
    }

    private func outputKey(_ key: String) -> String { "\(prefix).output.\(key)" }
    private func volumeKey(_ key: String) -> String { "\(prefix).volume.\(key)" }
    private func mutedKey(_ key: String) -> String { "\(prefix).muted.\(key)" }
}
