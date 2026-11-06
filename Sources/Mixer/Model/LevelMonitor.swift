import Foundation

/// Níveis dos medidores, separados do `MixerState` pra o redesenho de 20 quadros por segundo
/// atingir só os medidores, e não a lista inteira. Só roda com o menu aberto.
@MainActor
final class LevelMonitor: ObservableObject {
    static let outputKey = "__saida__"
    static let interval: TimeInterval = 1.0 / 20
    /// Quanto o medidor cai a cada quadro quando o som baixa (queda suave em vez de piscar).
    static let decay: Float = 0.82

    @Published private(set) var levels: [String: Float] = [:]

    private let source: () -> [String: Float]
    private var timer: Timer?

    init(source: @escaping () -> [String: Float]) {
        self.source = source
    }

    func level(_ key: String) -> Float { levels[key] ?? 0 }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        levels = [:]
    }

    private func tick() {
        let fresh = source()
        var next: [String: Float] = [:]
        for key in Set(fresh.keys).union(levels.keys) where key != Self.outputKey {
            let value = max(fresh[key] ?? 0, (levels[key] ?? 0) * Self.decay)
            if value > 0.0005 { next[key] = value }
        }
        // A saída mostra o mais alto entre os apps: é o que o Mixer está mandando pro alto-falante.
        next[Self.outputKey] = next.values.max() ?? 0
        if next != levels { levels = next }
    }
}
