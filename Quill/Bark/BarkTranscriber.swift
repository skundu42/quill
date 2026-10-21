// Adapted from Conway Research’s Bark 3.0 reference runtime (CC BY 4.0).
// See docs/BARK.md for attribution and changes.
import CoreML
import Foundation

protocol BarkTranscribing: Sendable {
    func transcribe(pcm: Data) async throws -> String
}

actor BarkTranscriber: BarkTranscribing {
    static let shared = BarkTranscriber()
    static let sampleRate = 16_000
    static let maximumAudioBytes = sampleRate * 2 * 300

    private let directory: URL
    private var decoder: BarkDecoder?
    private var encoders: [Int: MLModel] = [:]

    init(directory: URL = BarkModelFiles.directory) {
        self.directory = directory
    }

    func transcribe(pcm: Data) async throws -> String {
        try Task.checkCancellation()
        #if arch(arm64)
        guard #available(macOS 15, *) else { throw BarkError.unsupported }
        guard pcm.count <= Self.maximumAudioBytes else { throw BarkError.recordingTooLong }
        let samples = try Self.samples(from: pcm)
        guard !samples.isEmpty, samples.contains(where: { $0 != 0 }) else { return "" }
        if decoder == nil {
            decoder = try BarkDecoder(
                directory: directory.appendingPathComponent("decoder"),
                vocabularyURL: directory.appendingPathComponent("vocab.json")
            )
        }
        guard let decoder else { throw BarkError.modelNotInstalled }
        var transcripts: [String] = []
        for range in Self.segmentRanges(samples) {
            try Task.checkCancellation()
            // Bark's evaluated frontend prepends 250 ms of silence to each piece.
            let piece = [Float](repeating: 0, count: 4_000) + samples[range]
            let features = try decoder.features(samples: piece)
            let window = piece.count <= 8 * Self.sampleRate ? 8 : 15
            let frames = window * 100 + 1
            guard features.frameCount <= frames else { throw BarkError.invalidAudio }
            let input = try MLMultiArray(shape: [1, NSNumber(value: frames), 128], dataType: .float16)
            let inputPointer = input.dataPointer.bindMemory(to: Float16.self, capacity: frames * 128)
            inputPointer.initialize(repeating: 0, count: frames * 128)
            for (index, value) in features.values.enumerated() { inputPointer[index] = Float16(value) }
            let mask = try MLMultiArray(shape: [1, NSNumber(value: frames)], dataType: .int32)
            let maskPointer = mask.dataPointer.bindMemory(to: Int32.self, capacity: frames)
            for index in 0..<frames { maskPointer[index] = index < features.validFrameCount ? 1 : 0 }
            let provider = try MLDictionaryFeatureProvider(dictionary: ["features": input, "mask": mask])
            let encoder = try encoder(for: window)
            let prediction = try await encoder.prediction(from: provider)
            try Task.checkCancellation()
            guard let encoded = prediction.featureValue(for: "encoded")?.multiArrayValue,
                  encoded.shape.count == 3, encoded.shape[0].intValue == 1,
                  encoded.shape[2].intValue == 640 else { throw BarkError.invalidEncoderOutput }
            let valid = Self.encodedLength(features.validFrameCount)
            guard encoded.shape[1].intValue >= valid else { throw BarkError.invalidEncoderOutput }
            var values = [Float]()
            values.reserveCapacity(valid * 640)
            for frame in 0..<valid {
                for channel in 0..<640 {
                    let value = encoded[[0, NSNumber(value: frame), NSNumber(value: channel)]].floatValue
                    guard value.isFinite else { throw BarkError.invalidEncoderOutput }
                    values.append(value)
                }
            }
            let text = try decoder.decode(encoded: values, frameCount: valid)
            if !text.isEmpty { transcripts.append(text) }
        }
        return transcripts.joined(separator: " ")
        #else
        throw BarkError.unsupported
        #endif
    }

    func unload() {
        decoder = nil
        encoders.removeAll()
    }

    /// Trigger Core ML's accelerator specialization during setup, before recording.
    func prepare() async throws {
        #if arch(arm64)
        guard #available(macOS 15, *) else { throw BarkError.unsupported }
        for window in [8, 15] {
            try Task.checkCancellation()
            let frames = window * 100 + 1
            let features = try MLMultiArray(shape: [1, NSNumber(value: frames), 128], dataType: .float16)
            features.dataPointer.bindMemory(to: UInt16.self, capacity: frames * 128)
                .initialize(repeating: 0, count: frames * 128)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: frames)], dataType: .int32)
            mask.dataPointer.bindMemory(to: Int32.self, capacity: frames).initialize(repeating: 1, count: frames)
            let provider = try MLDictionaryFeatureProvider(dictionary: ["features": features, "mask": mask])
            _ = try await encoder(for: window).prediction(from: provider)
        }
        #else
        throw BarkError.unsupported
        #endif
    }

    @available(macOS 15, *)
    private func encoder(for window: Int) throws -> MLModel {
        if let model = encoders[window] { return model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        configuration.functionName = "w\(window)"
        let model = try MLModel(contentsOf: directory.appendingPathComponent("BarkEncoder.mlmodelc"), configuration: configuration)
        encoders[window] = model
        return model
    }

    static func samples(from pcm: Data) throws -> [Float] {
        guard pcm.count.isMultiple(of: 2) else { throw BarkError.invalidAudio }
        return pcm.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 2).map { offset in
                Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))) / 32768
            }
        }
    }

    static func encodedLength(_ frames: Int) -> Int {
        (0..<3).reduce(frames) { value, _ in (value + 1) / 2 }
    }

    /// Match the reference's pause-based segmentation, reserving 250 ms for padding.
    /// Audio stays in memory; every sample belongs to exactly one segment.
    static func segmentRanges(_ samples: [Float]) -> [Range<Int>] {
        let maximum = 236_000 // 14.75 seconds
        guard !samples.isEmpty else { return [] }
        guard samples.count > maximum else { return [0..<samples.count] }
        let frameSize = 160
        let frameCount = samples.count / frameSize
        var energy = [Double](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let start = frame * frameSize
            energy[frame] = samples[start..<(start + frameSize)].reduce(0) { $0 + Double($1 * $1) } / Double(frameSize)
        }
        var prefix = [Double](repeating: 0, count: frameCount + 1)
        for index in 0..<frameCount { prefix[index + 1] = prefix[index] + energy[index] }
        var smoothed = [Double](repeating: 0, count: frameCount)
        for index in 0..<frameCount {
            let upper = min(frameCount, index + 10)
            let lower = max(0, index - 10)
            smoothed[index] = (prefix[upper] - prefix[lower]) / 20
        }
        var ranges: [Range<Int>] = []
        var start = 0
        while samples.count - start > maximum {
            let lower = (start + 80_000) / frameSize
            // Keep the midpoint of the quiet frame within the model's 14.75 s limit.
            let upper = (start + maximum - frameSize / 2) / frameSize
            let quietest = (lower...upper).min { smoothed[$0] < smoothed[$1] } ?? lower
            let cut = quietest * frameSize + frameSize / 2
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<samples.count)
        return ranges
    }
}
