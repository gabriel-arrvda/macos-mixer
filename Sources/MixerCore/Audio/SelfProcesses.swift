import Darwin
import Foundation

/// Identifica processos que rodam o mesmo executável do app (inclusive instâncias antigas).
/// Capturar o áudio de uma instância irmã cria loop de retroalimentação.
enum SelfProcesses {
    static func pids(among candidates: [pid_t]) -> Set<pid_t> {
        var result: Set<pid_t> = [getpid()]
        guard let own = path(of: getpid()) else { return result }
        for pid in candidates where path(of: pid) == own { result.insert(pid) }
        return result
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }
}
