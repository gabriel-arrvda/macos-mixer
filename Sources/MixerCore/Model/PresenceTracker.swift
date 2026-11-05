import Foundation

/// Decide quais apps continuam na lista: quem toca e quem parou há menos de `grace` segundos.
/// Evita a lista piscar entre faixas e mantém o slider no lugar.
public struct PresenceTracker {
    public let grace: TimeInterval
    private var lastActive: [String: Date] = [:]

    public init(grace: TimeInterval = 5) {
        self.grace = grace
    }

    /// `active`: chaves que estão tocando agora. Devolve as que devem aparecer.
    public mutating func update(active: Set<String>, now: Date) -> Set<String> {
        for key in active { lastActive[key] = now }
        lastActive = lastActive.filter { now.timeIntervalSince($0.value) <= grace }
        return Set(lastActive.keys)
    }
}
