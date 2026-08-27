import AVFoundation
import Foundation

struct AudioChunkAccumulator {
    private(set) var storage = Data()
    let chunkSize: Int

    init(chunkSize: Int = 3_200) {
        precondition(chunkSize > 0)
        self.chunkSize = chunkSize
    }

    mutating func append(_ data: Data) -> [Data] {
        storage.append(data)
        var chunks: [Data] = []
        while storage.count >= chunkSize {
            chunks.append(storage.prefix(chunkSize))
            storage.removeFirst(chunkSize)
        }
        return chunks
    }

    mutating func flush() -> Data? {
        guard !storage.isEmpty else { return nil }
        let remainder = storage
        storage.removeAll(keepingCapacity: true)
        return remainder
    }
}

enum AudioRecorderError: LocalizedError, Equatable {
    case unavailableInput
    case unsupportedFormat
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unavailableInput: "No microphone input is available."
        case .unsupportedFormat: "The microphone audio format is not supported."
        case .conversionFailed: "Quill could not convert microphone audio."
        }
    }
}

enum AudioLevelMeter {
    static func normalizedLevel(samples: UnsafePointer<Int16>, count: Int) -> Double {
        guard count > 0 else { return 0 }

        let sampleStride = max(1, count / 256)
        var sumOfSquares = 0.0
        var sampledCount = 0
        for index in stride(from: 0, to: count, by: sampleStride) {
            let normalizedSample = Double(samples[index]) / Double(Int16.max)
            sumOfSquares += normalizedSample * normalizedSample
            sampledCount += 1
        }

        let rms = sqrt(sumOfSquares / Double(sampledCount))
        let decibels = 20 * log10(max(rms, 0.0001))
        return min(max((decibels + 50) / 42, 0), 1)
    }
}

final class AudioRecorder: @unchecked Sendable {
    typealias ChunkHandler = @Sendable (Data) -> Void
    typealias LevelHandler = @Sendable (Double) -> Void

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var accumulator = AudioChunkAccumulator()
    private var chunkHandler: ChunkHandler?
    private var levelHandler: LevelHandler?
    private var smoothedLevel = 0.0
    private let lock = NSLock()
    private var running = false

    var isRunning: Bool {
        lock.withLock { running }
    }

    func start(onChunk: @escaping ChunkHandler, onLevel: @escaping LevelHandler) throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.unavailableInput
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.unsupportedFormat
        }

        self.converter = converter
        self.chunkHandler = onChunk
        self.levelHandler = onLevel
        smoothedLevel = 0
        accumulator = AudioChunkAccumulator()

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndChunk(buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        do {
            try engine.start()
            lock.withLock { running = true }
        } catch {
            inputNode.removeTap(onBus: 0)
            self.converter = nil
            self.chunkHandler = nil
            self.levelHandler = nil
            throw error
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { running = false }
        if let remainder = accumulator.flush() {
            chunkHandler?(remainder)
        }
        converter = nil
        chunkHandler = nil
        levelHandler = nil
        smoothedLevel = 0
    }

    private func convertAndChunk(_ inputBuffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            if suppliedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              conversionError == nil,
              outputBuffer.frameLength > 0,
              let samples = outputBuffer.int16ChannelData?.pointee else {
            QuillLogger.audio.error("Audio conversion failed")
            return
        }

        let rawLevel = AudioLevelMeter.normalizedLevel(
            samples: samples,
            count: Int(outputBuffer.frameLength)
        )
        let smoothing = rawLevel > smoothedLevel ? 0.62 : 0.16
        smoothedLevel += (rawLevel - smoothedLevel) * smoothing
        levelHandler?(smoothedLevel)

        let data = Data(bytes: samples, count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size)
        for chunk in accumulator.append(data) {
            chunkHandler?(chunk)
        }
    }
}
