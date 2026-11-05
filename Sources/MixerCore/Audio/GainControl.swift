import CAtomics
import CoreAudio
import Foundation

/// Ganho com rampa pra uma sessão de áudio.
///
/// `setTarget` e `takePeak` são chamados de qualquer thread. `process` só roda na thread de áudio.
/// Nada aqui aloca memória nem usa lock depois do `init`: o alvo e o pico são `UInt32` atômicos
/// (bits de um `Float`) e o ganho atual só é tocado pela thread de áudio.
public final class GainControl: @unchecked Sendable {
    public static let defaultRampSeconds = 0.02

    private let shared: UnsafeMutablePointer<UInt32>   // [0] alvo, [1] pico de entrada
    private let currentGain: UnsafeMutablePointer<Float>
    private let step: Float                             // variação máxima do ganho por frame

    public init(sampleRate: Double, rampSeconds: Double = GainControl.defaultRampSeconds, initialGain: Float = 1) {
        let frames = max(sampleRate * rampSeconds, 1)
        step = Float(1.0 / frames)
        let initial = GainControl.clamp(initialGain)
        shared = .allocate(capacity: 2)
        shared.initialize(repeating: 0, count: 2)
        shared[0] = initial.bitPattern
        currentGain = .allocate(capacity: 1)
        currentGain.initialize(to: initial)
    }

    deinit {
        shared.deallocate()
        currentGain.deallocate()
    }

    public var targetGain: Float { Float(bitPattern: ca_load_u32(shared)) }

    public func setTarget(_ gain: Float) {
        ca_store_u32(shared, GainControl.clamp(gain).bitPattern)
    }

    /// Maior amplitude de entrada (antes do ganho) desde a última chamada.
    public func takePeak() -> Float {
        Float(bitPattern: ca_exchange_u32(shared + 1, 0))
    }

    static func clamp(_ gain: Float) -> Float {
        gain.isNaN ? 1 : min(max(gain, 0), 1)
    }

    // MARK: - Thread de áudio

    /// Copia `input` pra `output` aplicando o ganho. Buffers sem entrada correspondente saem em silêncio.
    public func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let target = Float(bitPattern: ca_load_u32(shared))
        let start = currentGain.pointee
        var end = start
        var peak: Float = 0

        for index in 0..<outputs.count {
            guard let destination = outputs[index].mData else { continue }
            guard index < inputs.count, let source = inputs[index].mData else {
                memset(destination, 0, Int(outputs[index].mDataByteSize))
                continue
            }
            let inChannels = max(Int(inputs[index].mNumberChannels), 1)
            let outChannels = max(Int(outputs[index].mNumberChannels), 1)
            let inFrames = Int(inputs[index].mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
            let outFrames = Int(outputs[index].mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
            let frames = min(inFrames, outFrames)
            end = GainControl.apply(
                source: source.assumingMemoryBound(to: Float.self),
                destination: destination.assumingMemoryBound(to: Float.self),
                frames: frames, sourceChannels: inChannels, destinationChannels: outChannels,
                startGain: start, targetGain: target, step: step, peak: &peak)
            // Sobra de buffer de saída (se houver) fica em silêncio.
            let written = frames * outChannels * MemoryLayout<Float>.size
            let total = Int(outputs[index].mDataByteSize)
            if total > written { memset(destination + written, 0, total - written) }
        }

        currentGain.pointee = end
        ca_max_u32(shared + 1, peak.bitPattern)
    }

    /// Núcleo da conta, separado do Core Audio pra poder testar. Retorna o ganho no fim do bloco.
    /// O ganho anda no máximo `step` por frame na direção do alvo, igual pra todos os canais.
    static func apply(source: UnsafePointer<Float>,
                      destination: UnsafeMutablePointer<Float>,
                      frames: Int,
                      sourceChannels: Int,
                      destinationChannels: Int,
                      startGain: Float,
                      targetGain: Float,
                      step: Float,
                      peak: inout Float) -> Float {
        var gain = startGain
        let shared = min(sourceChannels, destinationChannels)
        for frame in 0..<frames {
            if gain != targetGain {
                gain = gain < targetGain ? min(gain + step, targetGain) : max(gain - step, targetGain)
            }
            let inBase = frame * sourceChannels
            let outBase = frame * destinationChannels
            for channel in 0..<shared {
                let sample = source[inBase + channel]
                peak = max(peak, abs(sample))
                // Limita em ±1: se algo der errado (ex.: loop de captura), não sai ruído gigante.
                destination[outBase + channel] = min(max(sample * gain, -1), 1)
            }
            for channel in shared..<destinationChannels { destination[outBase + channel] = 0 }
        }
        return gain
    }
}
