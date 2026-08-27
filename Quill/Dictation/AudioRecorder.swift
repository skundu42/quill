import AudioToolbox
import AVFoundation
import CoreAudio
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
    case deviceConfigurationFailed
    case inputConfigurationChanged

    var errorDescription: String? {
        switch self {
        case .unavailableInput: "No microphone input is available."
        case .unsupportedFormat: "The microphone audio format is not supported."
        case .conversionFailed: "Quill could not convert microphone audio."
        case .deviceConfigurationFailed: "Quill could not use the selected microphone."
        case .inputConfigurationChanged: "The microphone changed or disconnected. Try dictating again."
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

struct AudioLevelUpdateLimiter {
    let minimumInterval: Duration
    private var lastDelivery: ContinuousClock.Instant?

    init(minimumInterval: Duration = .milliseconds(33)) {
        self.minimumInterval = minimumInterval
    }

    mutating func shouldDeliver(at instant: ContinuousClock.Instant = .now) -> Bool {
        guard let lastDelivery else {
            self.lastDelivery = instant
            return true
        }
        guard lastDelivery.duration(to: instant) >= minimumInterval else { return false }
        self.lastDelivery = instant
        return true
    }

    mutating func reset() {
        lastDelivery = nil
    }
}

final class AudioRecorder: @unchecked Sendable {
    typealias ChunkHandler = @Sendable (Data) -> Void
    typealias LevelHandler = @Sendable (Double) -> Void
    typealias ErrorHandler = @Sendable (AudioRecorderError) -> Void

    private let engine = AVAudioEngine()
    private let deviceProvider: any AudioInputDeviceProviding
    private var converter: AVAudioConverter?
    private var accumulator = AudioChunkAccumulator()
    private var chunkHandler: ChunkHandler?
    private var levelHandler: LevelHandler?
    private var errorHandler: ErrorHandler?
    private var configurationObserver: NSObjectProtocol?
    private var activeSelection: ActiveAudioInputSelection?
    private var smoothedLevel = 0.0
    private var levelUpdateLimiter = AudioLevelUpdateLimiter()
    private let lock = NSLock()
    private let lifecycleLock = NSLock()
    private let deliveryQueue = DispatchQueue(label: "com.quill.voice.audio-delivery")
    private var running = false

    private struct PreparedInput {
        let resolution: AudioInputResolution
        let selection: ActiveAudioInputSelection
        let inputNode: AVAudioInputNode
        let inputFormat: AVAudioFormat
        let targetFormat: AVAudioFormat
        let converter: AVAudioConverter
    }

    init(deviceProvider: any AudioInputDeviceProviding = CoreAudioInputDeviceProvider()) {
        self.deviceProvider = deviceProvider
    }

    var isRunning: Bool {
        lock.withLock { running }
    }

    @discardableResult
    func prewarm(microphone: MicrophonePreference?) throws -> AudioInputResolution {
        try lifecycleLock.withLock {
            if isRunning {
                return try resolveInput(microphone: microphone).0
            }
            let prepared = try prepareInput(microphone: microphone)
            engine.prepare()
            return prepared.resolution
        }
    }

    @discardableResult
    func start(
        microphone: MicrophonePreference?,
        onChunk: @escaping ChunkHandler,
        onLevel: @escaping LevelHandler,
        onError: @escaping ErrorHandler
    ) throws -> AudioInputResolution {
        try lifecycleLock.withLock {
            try startLocked(
                microphone: microphone,
                onChunk: onChunk,
                onLevel: onLevel,
                onError: onError
            )
        }
    }

    private func startLocked(
        microphone: MicrophonePreference?,
        onChunk: @escaping ChunkHandler,
        onLevel: @escaping LevelHandler,
        onError: @escaping ErrorHandler
    ) throws -> AudioInputResolution {
        if isRunning {
            return try resolveInput(microphone: microphone).0
        }

        let prepared = try prepareInput(microphone: microphone)

        lock.withLock {
            converter = prepared.converter
            chunkHandler = onChunk
            levelHandler = onLevel
            errorHandler = onError
            activeSelection = prepared.selection
            smoothedLevel = 0
            levelUpdateLimiter.reset()
            accumulator = AudioChunkAccumulator()
            running = true
        }

        prepared.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: prepared.inputFormat) { [weak self] buffer, _ in
            self?.convertAndChunk(buffer, targetFormat: prepared.targetFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            prepared.inputNode.removeTap(onBus: 0)
            lock.withLock {
                running = false
                self.converter = nil
                chunkHandler = nil
                levelHandler = nil
                errorHandler = nil
                activeSelection = nil
            }
            throw error
        }

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleInputConfigurationChange()
        }
        return prepared.resolution
    }

    func stop() {
        lifecycleLock.withLock {
            stopLocked()
        }
    }

    private func stopLocked() {
        guard isRunning else { return }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let delivery = lock.withLock { () -> (Data?, ChunkHandler?) in
            running = false
            let remainder = accumulator.flush()
            let handler = chunkHandler
            converter = nil
            chunkHandler = nil
            levelHandler = nil
            errorHandler = nil
            activeSelection = nil
            smoothedLevel = 0
            levelUpdateLimiter.reset()
            return (remainder, handler)
        }
        deliveryQueue.sync {
            if let remainder = delivery.0 {
                delivery.1?(remainder)
            }
        }
    }

    private func resolveInput(
        microphone: MicrophonePreference?
    ) throws -> (AudioInputResolution, ActiveAudioInputSelection) {
        let devices = try deviceProvider.inputDevices()
        let defaultID = try deviceProvider.defaultInputDeviceID()
        guard let resolution = AudioInputResolution.resolve(
            preference: microphone,
            devices: devices,
            defaultDeviceID: defaultID
        ) else { throw AudioRecorderError.unavailableInput }
        return (
            resolution,
            ActiveAudioInputSelection(preference: microphone, resolution: resolution)
        )
    }

    private func prepareInput(microphone: MicrophonePreference?) throws -> PreparedInput {
        let (resolution, selection) = try resolveInput(microphone: microphone)
        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioRecorderError.unavailableInput
        }
        if selection.requiresExplicitDeviceConfiguration {
            var deviceID = AudioDeviceID(selection.device.deviceID)
            let deviceStatus = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard deviceStatus == noErr else {
                QuillLogger.audio.error("Unable to select audio input device: \(deviceStatus)")
                throw AudioRecorderError.deviceConfigurationFailed
            }
        }

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
        return PreparedInput(
            resolution: resolution,
            selection: selection,
            inputNode: inputNode,
            inputFormat: inputFormat,
            targetFormat: targetFormat,
            converter: converter
        )
    }

    private func handleInputConfigurationChange() {
        guard isRunning else { return }
        if inputRouteIsUnchanged(), engine.isRunning {
            QuillLogger.audio.debug("Ignoring audio configuration notification; input route is unchanged")
            return
        }
        let handler = lock.withLock { errorHandler }
        stop()
        handler?(.inputConfigurationChanged)
    }

    private func inputRouteIsUnchanged() -> Bool {
        guard let selection = lock.withLock({ activeSelection }) else { return false }
        do {
            let devices = try deviceProvider.inputDevices()
            let defaultID = try deviceProvider.defaultInputDeviceID()
            let audioUnitDeviceID = selection.requiresExplicitDeviceConfiguration
                ? currentAudioUnitDeviceID()
                : nil
            return selection.matchesCurrentRoute(
                devices: devices,
                defaultDeviceID: defaultID,
                audioUnitDeviceID: audioUnitDeviceID
            )
        } catch {
            QuillLogger.audio.error("Unable to verify audio input after configuration change: \(error.localizedDescription)")
            return false
        }
    }

    private func currentAudioUnitDeviceID() -> AudioDeviceID? {
        guard let audioUnit = engine.inputNode.audioUnit else { return nil }
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &size
        )
        guard status == noErr else {
            QuillLogger.audio.error("Unable to read current audio input device: \(status)")
            return nil
        }
        return deviceID
    }

    private func convertAndChunk(_ inputBuffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        lock.withLock {
            guard running, let converter, let chunkHandler, let levelHandler else { return }

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

            let data = Data(bytes: samples, count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size)
            let chunks = accumulator.append(data)
            let level = levelUpdateLimiter.shouldDeliver() ? smoothedLevel : nil
            guard level != nil || !chunks.isEmpty else { return }
            deliveryQueue.async {
                if let level { levelHandler(level) }
                for chunk in chunks {
                    chunkHandler(chunk)
                }
            }
        }
    }
}
