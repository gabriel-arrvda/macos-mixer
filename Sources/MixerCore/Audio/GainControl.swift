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

    private let shared: UnsafeMutablePointer<UInt32>   // [0] alvo, [1] pico de entrada, [2] nível de saída
    private let currentGain: UnsafeMutablePointer<Float>
    private let step: Float                             // variação máxima do ganho por frame
    /// Posição, na lista de buffers de entrada do aggregate device, do buffer que carrega o áudio do tap.
    private let inputIndex: Int

    public init(sampleRate: Double, rampSeconds: Double = GainControl.defaultRampSeconds,
                initialGain: Float = 1, inputIndex: Int = 0) {
        self.inputIndex = inputIndex
        let frames = max(sampleRate * rampSeconds, 1)
        step = Float(1.0 / frames)
        let initial = GainControl.clamp(initialGain)
        shared = .allocate(capacity: 3)
        shared.initialize(repeating: 0, count: 3)
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

    /// Limita a 0...`AppVolume.maxVolume` (até 400%). NaN vira 1.
    /// Maior amplitude que saiu pro alto-falante (depois do ganho) desde a última chamada.
    /// Leitor separado de `takePeak`, pra o medidor da UI não interferir na detecção de silêncio.
    /// Na sondagem o app toca sem ganho, então o nível é o próprio pico de entrada.
    public func takeLevel() -> Float {
        Float(bitPattern: ca_exchange_u32(shared + 2, 0))
    }

    static func clamp(_ gain: Float) -> Float { AppVolume.clamp(gain) }

    // MARK: - Thread de áudio

    /// Só mede o pico do buffer do tap. Não toca na saída: usado na sondagem, antes de a permissão ser confirmada.
    public func processProbe(input: UnsafePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard inputIndex < inputs.count, let source = inputs[inputIndex].mData else { return }
        let samples = Int(inputs[inputIndex].mDataByteSize) / MemoryLayout<Float>.size
        let data = source.assumingMemoryBound(to: Float.self)
        var peak: Float = 0
        for index in 0..<samples { peak = max(peak, abs(data[index])) }
        ca_max_u32(shared + 1, peak.bitPattern)
        ca_max_u32(shared + 2, peak.bitPattern)
    }

    /// Copia o buffer do tap pro primeiro buffer de `output` aplicando o ganho. O resto da saída fica em silêncio.
    public func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let target = Float(bitPattern: ca_load_u32(shared))
        let start = currentGain.pointee
        var end = start
        var peak: Float = 0
        var level: Float = 0

        for index in 0..<outputs.count {
            guard let destination = outputs[index].mData else { continue }
            let total = Int(outputs[index].mDataByteSize)
            guard index == 0, inputIndex < inputs.count, let source = inputs[inputIndex].mData else {
                memset(destination, 0, total)
                continue
            }
            let inChannels = max(Int(inputs[inputIndex].mNumberChannels), 1)
            let outChannels = max(Int(outputs[index].mNumberChannels), 1)
            let inFrames = Int(inputs[inputIndex].mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
            let outFrames = total / (MemoryLayout<Float>.size * outChannels)
            let frames = min(inFrames, outFrames)
            end = GainControl.apply(
                source: source.assumingMemoryBound(to: Float.self),
                destination: destination.assumingMemoryBound(to: Float.self),
                frames: frames, sourceChannels: inChannels, destinationChannels: outChannels,
                startGain: start, targetGain: target, step: step, peak: &peak)
            // Sobra de buffer de saída (se houver) fica em silêncio.
            let written = frames * outChannels * MemoryLayout<Float>.size
            if total > written { memset(destination + written, 0, total - written) }
            let out = destination.assumingMemoryBound(to: Float.self)
            for sample in 0..<(frames * outChannels) { level = max(level, abs(out[sample])) }
        }

        currentGain.pointee = end
        ca_max_u32(shared + 1, peak.bitPattern)
        ca_max_u32(shared + 2, level.bitPattern)
    }

    /// Só pra testes: simula um pico de entrada.
    func recordPeak(_ value: Float) {
        ca_max_u32(shared + 1, value.bitPattern)
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
        // Saída mono com entrada de vários canais: mistura todos em vez de descartar os outros.
        let mixesDown = destinationChannels == 1 && sourceChannels > 1
        for frame in 0..<frames {
            if gain != targetGain {
                gain = gain < targetGain ? min(gain + step, targetGain) : max(gain - step, targetGain)
            }
            let inBase = frame * sourceChannels
            let outBase = frame * destinationChannels
            if mixesDown {
                var sum: Float = 0
                for channel in 0..<sourceChannels {
                    let sample = source[inBase + channel]
                    peak = max(peak, abs(sample))
                    sum += sample
                }
                destination[outBase] = min(max(sum / Float(sourceChannels) * gain, -1), 1)
                continue
            }
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
