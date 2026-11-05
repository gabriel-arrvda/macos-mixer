import Foundation

/// Agrupa processos de áudio pelo app dono. Puro: o jeito de achar o dono entra como parâmetro.
public enum ProcessGrouper {
    /// Devolve um grupo por dono, em ordem alfabética estável (nome, depois chave).
    /// Processos sem dono (`resolver` devolve nil) e os de `excluding` ficam de fora.
    public static func group(_ processes: [AudioProcessInfo],
                             excluding excludedPIDs: Set<pid_t> = [],
                             resolver: (AudioProcessInfo) -> AppOwner?) -> [AppGroup] {
        var ordered: [AppOwner] = []
        var objects: [String: [UInt32]] = [:]
        var playing: [String: [UInt32]] = [:]

        for process in processes where !excludedPIDs.contains(process.pid) {
            guard let owner = resolver(process), !excludedPIDs.contains(owner.pid) else { continue }
            if objects[owner.key] == nil { ordered.append(owner) }
            objects[owner.key, default: []].append(process.objectID)
            if process.isRunningOutput { playing[owner.key, default: []].append(process.objectID) }
        }

        return ordered
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return order == .orderedSame ? lhs.key < rhs.key : order == .orderedAscending
            }
            .map { owner in
                let playingObjects = playing[owner.key, default: []].sorted()
                return AppGroup(owner: owner, objectIDs: objects[owner.key, default: []].sorted(),
                                isPlaying: !playingObjects.isEmpty, playingObjectIDs: playingObjects)
            }
    }
}
