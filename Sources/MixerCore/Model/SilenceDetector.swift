import Foundation

/// Decide se o áudio capturado está chegando zerado em todos os apps ativos (sinal de permissão negada).
/// Um app só em pausa ou em silêncio entre faixas não dispara: só vale se TODOS os ativos vierem zerados
/// por mais de `threshold` segundos.
public struct SilenceDetector {
    public enum Verdict: Equatable, Sendable {
        /// Nenhum app ativo: não há o que concluir.
        case idle
        /// Zerado, mas ainda dentro da tolerância.
        case pending
        case receiving
        case silent
    }

    public static let silenceThreshold: Float = 0.0001

    public let threshold: TimeInterval
    private var silentSince: Date?

    public init(threshold: TimeInterval = 5) {
        self.threshold = threshold
    }

    /// `peaks`: o maior pico de entrada de cada app ativo desde a última leitura.
    public mutating func update(peaks: [Float], now: Date) -> Verdict {
        guard !peaks.isEmpty else {
            silentSince = nil
            return .idle
        }
        if peaks.contains(where: { $0 > Self.silenceThreshold }) {
            silentSince = nil
            return .receiving
        }
        let start = silentSince ?? now
        silentSince = start
        return now.timeIntervalSince(start) >= threshold ? .silent : .pending
    }
}
