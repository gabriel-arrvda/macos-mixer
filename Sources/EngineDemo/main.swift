import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
import AppKit
import MixerCore

// Demo do engine sem UI. Uso: EngineDemo [bundleID=volume ...]
// Ex.: EngineDemo com.apple.Safari=0.3 com.google.Chrome=0
// Mostra os apps que tocam, aplica os volumes dados (e os guardados) e imprime o pico de cada um.
// Ctrl+C encerra e devolve o áudio ao normal.

MainActor.assumeIsolated {
    let manager = SessionManager()
    var overrides: [String: Float] = [:]
    for arg in CommandLine.arguments.dropFirst() {
        let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2, let value = Float(parts[1]) { overrides[parts[0]] = value }
    }

    var lastDescription = ""
    manager.onEntriesChange = { entries in
        for entry in entries { if let value = overrides.removeValue(forKey: entry.id) { manager.setVolume(value, for: entry.id) } }
        let text = entries.map { entry in
            let state = entry.isMuted ? "mudo" : String(format: "%.0f%%", entry.volume * 100)
            let status: String
            switch entry.status {
            case .connecting: status = "conectando"
            case .active: status = entry.isPlaying ? "tocando" : "parado"
            case .failed(let message): status = "ERRO: \(message)"
            }
            return "  \(entry.owner.name) [\(entry.id)] \(state) \(status)"
        }.joined(separator: "\n")
        if text != lastDescription {
            lastDescription = text
            print("--- \(Date().formatted(date: .omitted, time: .standard))\n\(text.isEmpty ? "  (nada tocando)" : text)")
        }
    }
    manager.onOutputChange = { device in print(">>> saída mudou para: \(device.name) (\(device.nominalSampleRate()) Hz)") }
    manager.start()
    if let output = manager.output { print("Saída: \(output.name) (\(output.nominalSampleRate()) Hz)") }

    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        MainActor.assumeIsolated {
            let peaks = manager.takePeaks().sorted { $0.key < $1.key }
            if !peaks.isEmpty { print("picos: " + peaks.map { String(format: "%@=%.3f", $0.key, $0.value) }.joined(separator: "  ")) }
        }
    }

    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { manager.stop() }; exit(0) }
    source.resume()
    print("Rodando. Ctrl+C para sair.")
}
RunLoop.main.run()
