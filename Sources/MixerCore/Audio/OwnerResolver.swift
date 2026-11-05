import AppKit
import Darwin
import Foundation

/// Descobre o app dono de um processo de áudio.
///
/// Ordem: (1) o próprio processo é um app; (2) ferramenta de linha de comando fora de bundle
/// (afplay, mpv) vale por si; (3) o processo "responsável" do macOS (cobre o WebKit.GPU do Safari);
/// (4) a cadeia de processos pai (helpers do Chrome e do Electron); (5) prefixo do bundle ID
/// (`com.microsoft.teams2.helper` → `com.microsoft.teams2`). Daemons do sistema ficam de fora.
public final class OwnerResolver {
    private let apps: [pid_t: NSRunningApplication]
    private let appsByBundleID: [String: NSRunningApplication]

    /// Tira uma foto dos apps abertos. Crie um resolver por atualização da lista.
    public init() {
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        apps = Dictionary(regular.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        appsByBundleID = Dictionary(regular.compactMap { app in app.bundleIdentifier.map { ($0, app) } },
                                    uniquingKeysWith: { first, _ in first })
    }

    public func owner(of process: AudioProcessInfo) -> AppOwner? {
        if let app = apps[process.pid] { return owner(for: app) }

        let path = Self.executablePath(of: process.pid)
        if let path, !path.contains(".app/"), !path.contains(".xpc/"), !Self.isSystemPath(path) {
            return AppOwner(key: "proc:\(path)", name: (path as NSString).lastPathComponent, pid: process.pid)
        }
        if let app = responsibleApp(for: process.pid) ?? ancestorApp(of: process.pid)
            ?? prefixApp(for: process.bundleID) {
            return owner(for: app)
        }
        return nil
    }

    // MARK: - Estratégias

    private func owner(for app: NSRunningApplication) -> AppOwner {
        let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "App"
        return AppOwner(key: app.bundleIdentifier ?? "pid:\(app.processIdentifier)", name: name, pid: app.processIdentifier)
    }

    private func responsibleApp(for pid: pid_t) -> NSRunningApplication? {
        guard let function = Self.responsiblePIDFunction else { return nil }
        let responsible = function(pid)
        return responsible > 0 && responsible != pid ? apps[responsible] : nil
    }

    private func ancestorApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<8 {
            guard let parent = Self.parentPID(of: current), parent > 1 else { return nil }
            if let app = apps[parent] { return app }
            current = parent
        }
        return nil
    }

    private func prefixApp(for bundleID: String?) -> NSRunningApplication? {
        guard var parts = bundleID?.split(separator: ".").map(String.init) else { return nil }
        while parts.count > 2 {
            parts.removeLast()
            if let app = appsByBundleID[parts.joined(separator: ".")] { return app }
        }
        return nil
    }

    // MARK: - Chamadas de sistema

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    static func isSystemPath(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// `responsibility_get_pid_responsible_for_pid` não é API pública, mas só lê a relação de
    /// responsabilidade entre processos (a que o Activity Monitor usa). Não mexe em TCC.
    /// Se o símbolo sumir num macOS futuro, as outras estratégias continuam valendo.
    private static let responsiblePIDFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()
}
