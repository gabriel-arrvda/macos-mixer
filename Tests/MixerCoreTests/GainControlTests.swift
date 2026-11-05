import CoreAudio
import XCTest
@testable import MixerCore

final class GainControlTests: XCTestCase {
    private func run(frames: Int, channels: Int = 2, start: Float, target: Float, step: Float, value: Float = 1)
        -> (output: [Float], end: Float, peak: Float) {
        let source = [Float](repeating: value, count: frames * channels)
        var destination = [Float](repeating: -9, count: frames * channels)
        var peak: Float = 0
        let end = GainControl.apply(source: source, destination: &destination, frames: frames,
                                    sourceChannels: channels, destinationChannels: channels,
                                    startGain: start, targetGain: target, step: step, peak: &peak)
        return (destination, end, peak)
    }

    func testRampHasNoJumpsAndReachesTarget() {
        let step: Float = 1.0 / 100
        let result = run(frames: 300, start: 1, target: 0.2, step: step)
        let left = stride(from: 0, to: result.output.count, by: 2).map { result.output[$0] }
        for pair in zip(left, left.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(pair.1 - pair.0), step + 1e-6, "salto maior que um passo")
        }
        XCTAssertEqual(result.end, 0.2, accuracy: 1e-6)
        XCTAssertEqual(left.last!, 0.2, accuracy: 1e-6)
        // 80% de queda com passo de 1% por frame leva 80 frames.
        XCTAssertEqual(left[78], 0.2 + step, accuracy: 1e-5)
        XCTAssertEqual(left[79], 0.2, accuracy: 1e-5)
    }

    func testRampUpReachesTargetWithoutOvershoot() {
        let result = run(frames: 500, start: 0, target: 0.5, step: 0.003)
        XCTAssertLessThanOrEqual(result.output.max()!, 0.5 + 1e-6)
        XCTAssertEqual(result.end, 0.5, accuracy: 1e-6)
    }

    func testRampContinuesAcrossBlocks() {
        let first = run(frames: 50, start: 1, target: 0, step: 0.01)
        XCTAssertEqual(first.end, 0.5, accuracy: 1e-5)
        let second = run(frames: 50, start: first.end, target: 0, step: 0.01)
        XCTAssertEqual(second.end, 0, accuracy: 1e-5)
    }

    func testSteadyGainScalesAllChannelsAndReportsInputPeak() {
        let result = run(frames: 8, channels: 2, start: 0.3, target: 0.3, step: 0.01, value: 0.8)
        XCTAssertTrue(result.output.allSatisfy { abs($0 - 0.24) < 1e-6 })
        XCTAssertEqual(result.peak, 0.8, accuracy: 1e-6)   // pico é da entrada, antes do ganho
    }

    func testZeroGainIsSilentButPeakStillSeesInput() {
        let result = run(frames: 8, start: 0, target: 0, step: 0.01)
        XCTAssertTrue(result.output.allSatisfy { $0 == 0 })
        XCTAssertEqual(result.peak, 1)
    }

    func testExtraOutputChannelsAreSilenced() {
        let source: [Float] = [1, 1, 1, 1]            // 2 frames, estéreo
        var destination = [Float](repeating: -9, count: 8) // 2 frames, 4 canais
        var peak: Float = 0
        _ = GainControl.apply(source: source, destination: &destination, frames: 2, sourceChannels: 2,
                              destinationChannels: 4, startGain: 1, targetGain: 1, step: 0.1, peak: &peak)
        XCTAssertEqual(destination, [1, 1, 0, 0, 1, 1, 0, 0])
    }

    func testTargetIsClampedAndNaNIgnored() {
        let gain = GainControl(sampleRate: 48_000, initialGain: 0.5)
        gain.setTarget(2)
        XCTAssertEqual(gain.targetGain, 1)
        gain.setTarget(-1)
        XCTAssertEqual(gain.targetGain, 0)
        gain.setTarget(.nan)
        XCTAssertEqual(gain.targetGain, 1)
    }

    func testPeakIsTakenAndReset() {
        let gain = GainControl(sampleRate: 48_000, initialGain: 1)
        XCTAssertEqual(gain.takePeak(), 0)
        let list = AudioBufferListHelper(frames: 4, channels: 2, value: 0.6)
        gain.process(input: list.input, output: list.output)
        XCTAssertEqual(gain.takePeak(), 0.6, accuracy: 1e-6)
        XCTAssertEqual(gain.takePeak(), 0)
    }

    func testProcessWithAudioBufferList() {
        let gain = GainControl(sampleRate: 48_000, initialGain: 0.5)
        let list = AudioBufferListHelper(frames: 4, channels: 2, value: 1)
        gain.process(input: list.input, output: list.output)
        XCTAssertEqual(list.outputSamples, [Float](repeating: 0.5, count: 8))
    }
}

/// AudioBufferList de um buffer só, com memória própria.
final class AudioBufferListHelper {
    let input: UnsafeMutablePointer<AudioBufferList>
    let output: UnsafeMutablePointer<AudioBufferList>
    private let inData: UnsafeMutablePointer<Float>
    private let outData: UnsafeMutablePointer<Float>
    private let count: Int

    init(frames: Int, channels: Int, value: Float) {
        count = frames * channels
        inData = .allocate(capacity: count); inData.initialize(repeating: value, count: count)
        outData = .allocate(capacity: count); outData.initialize(repeating: -9, count: count)
        input = Self.makeList(inData, channels: channels, count: count)
        output = Self.makeList(outData, channels: channels, count: count)
    }

    deinit { input.deallocate(); output.deallocate(); inData.deallocate(); outData.deallocate() }

    var outputSamples: [Float] { Array(UnsafeBufferPointer(start: outData, count: count)) }

    private static func makeList(_ data: UnsafeMutablePointer<Float>, channels: Int, count: Int) -> UnsafeMutablePointer<AudioBufferList> {
        let list = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        list.pointee = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: UInt32(channels), mDataByteSize: UInt32(count * MemoryLayout<Float>.size), mData: data))
        return list
    }
}

final class ClippingTests: XCTestCase {
    func testOutputIsClippedToUnitRange() {
        let input: [Float] = [5, -5, 0.5]
        var output = [Float](repeating: 0, count: 3)
        var peak: Float = 0
        _ = GainControl.apply(source: input, destination: &output, frames: 3, sourceChannels: 1,
                              destinationChannels: 1, startGain: 1, targetGain: 1, step: 0.1, peak: &peak)
        XCTAssertEqual(output, [1, -1, 0.5])
    }
}
