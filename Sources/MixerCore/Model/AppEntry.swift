import Foundation

/// O app dono de um ou mais processos de áudio (ex.: Chrome e seus helpers).
public struct AppOwner: Hashable, Sendable {
    /// Identificador estável: o bundle ID do app, ou `proc:<caminho>` pra ferramentas sem bundle.
    public let key: String
    public let name: String
    /// PID do processo principal, usado pra buscar o ícone.
    public let pid: pid_t

    public init(key: String, name: String, pid: pid_t) {
        self.key = key
        self.name = name
        self.pid = pid
    }
}

/// Um processo visto pelo Core Audio.
public struct AudioProcessInfo: Equatable, Sendable {
    public let objectID: UInt32
    public let pid: pid_t
    public let bundleID: String?
    public let isRunningOutput: Bool

    public init(objectID: UInt32, pid: pid_t, bundleID: String?, isRunningOutput: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }
}

/// Todos os processos de áudio de um mesmo app.
public struct AppGroup: Equatable, Sendable {
    public let owner: AppOwner
    public let objectIDs: [UInt32]
    public let isPlaying: Bool
    /// Subconjunto de `objectIDs` que está emitindo som agora.
    public let playingObjectIDs: [UInt32]

    /// Sem `playingObjectIDs`, assume que todos os processos tocam quando o grupo toca.
    public init(owner: AppOwner, objectIDs: [UInt32], isPlaying: Bool, playingObjectIDs: [UInt32]? = nil) {
        self.owner = owner
        self.objectIDs = objectIDs
        self.isPlaying = isPlaying
        self.playingObjectIDs = playingObjectIDs ?? (isPlaying ? objectIDs : [])
    }
}

public enum SessionStatus: Equatable, Sendable {
    case connecting
    case active
    case failed(String)
}

/// O que a UI mostra por linha.
public struct AppEntry: Identifiable, Equatable, Sendable {
    public var id: String { owner.key }
    public let owner: AppOwner
    /// Valor do slider (0...1). Com mudo, é o volume pra onde o som volta.
    public var volume: Float
    public var isMuted: Bool
    public var isPlaying: Bool
    public var status: SessionStatus

    public init(owner: AppOwner, volume: Float, isMuted: Bool, isPlaying: Bool, status: SessionStatus) {
        self.owner = owner
        self.volume = volume
        self.isMuted = isMuted
        self.isPlaying = isPlaying
        self.status = status
    }

    /// Ganho aplicado na thread de áudio.
    public var effectiveGain: Float { AppVolume(volume: volume, isMuted: isMuted).effectiveGain }
}
