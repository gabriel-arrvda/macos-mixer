import CoreAudio
import Foundation

/// Erro com mensagem legível pra qualquer falha do Core Audio.
public struct AudioError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw AudioError("\(what) falhou (OSStatus \(status))") }
}

func propertyAddress(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func getProperty<T>(_ object: AudioObjectID,
                    _ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    as type: T.Type,
                    default value: T) throws -> T {
    var address = propertyAddress(selector, scope: scope)
    var size = UInt32(MemoryLayout<T>.size)
    var result = value
    try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result), "leitura da propriedade")
    return result
}

func getString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = propertyAddress(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
          let value, (value as String).isEmpty == false else { return nil }
    return value as String
}
