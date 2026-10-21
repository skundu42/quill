// Adapted from Conway Research's Bark 3.0 Core ML reference, licensed CC-BY-4.0.
// https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/blob/85db2ad18ab41e534a222ee253c29191d77ed919/coreml/ane/bark_coreml.py
// Changes: native Swift/Accelerate execution, bounded NPY parsing, and cancellation.
// Model attribution and license details are recorded in docs/BARK.md.
import Accelerate
import Foundation

struct BarkFeatures {
    let values: [Float]
    let frameCount: Int
    let validFrameCount: Int
}

enum BarkDecoderError: LocalizedError {
    case invalidArray(String)
    case invalidModel(String)
    case invalidAudio
    case invalidEncoderOutput

    var errorDescription: String? {
        switch self {
        case .invalidArray(let detail):
            return "The Bark model contains an invalid array: \(detail). Download the model again."
        case .invalidModel(let detail):
            return "The Bark decoder is invalid: \(detail). Download the model again."
        case .invalidAudio:
            return "Bark needs finite, mono 16 kHz audio in segments of at most 15 seconds."
        case .invalidEncoderOutput:
            return "Bark returned invalid audio features. Please try recording again."
        }
    }
}

/// The restricted NumPy format used by the pinned Bark decoder export.
/// Parsing the header as data avoids evaluating Python expressions from a model file.
struct BarkNumpyArray {
    let shape: [Int]
    let values: [Float]
    let descriptor: String

    init(contentsOf url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 64 * 1_024 * 1_024 else {
            throw BarkDecoderError.invalidArray("unexpected file size")
        }
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 10, Array(bytes.prefix(6)) == [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59],
              bytes[7] == 0, [1, 2, 3].contains(bytes[6]) else {
            throw BarkDecoderError.invalidArray("unsupported NPY header")
        }
        let lengthBytes = bytes[6] == 1 ? 2 : 4
        let headerStart = 8 + lengthBytes
        guard bytes.count >= headerStart else {
            throw BarkDecoderError.invalidArray("truncated header")
        }
        let headerLength = (0..<lengthBytes).reduce(0) { $0 | Int(bytes[8 + $1]) << (8 * $1) }
        guard headerLength > 0, headerLength <= 65_536, headerLength <= bytes.count - headerStart,
              let header = String(bytes: bytes[headerStart..<(headerStart + headerLength)], encoding: .ascii) else {
            throw BarkDecoderError.invalidArray("invalid header length")
        }
        let pattern = #"^\s*\{\s*['\"]descr['\"]\s*:\s*['\"](<f4|<f2|\|i1)['\"]\s*,\s*['\"]fortran_order['\"]\s*:\s*False\s*,\s*['\"]shape['\"]\s*:\s*\(\s*([0-9]+(?:\s*,\s*[0-9]+)*\s*,?)\s*\)\s*,?\s*\}\s*$"#
        let expression = try NSRegularExpression(pattern: pattern)
        let headerRange = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let match = expression.firstMatch(in: header, range: headerRange),
              let descriptorRange = Range(match.range(at: 1), in: header),
              let dimensionsRange = Range(match.range(at: 2), in: header) else {
            throw BarkDecoderError.invalidArray("only C-order float32, float16, and int8 arrays are supported")
        }
        descriptor = String(header[descriptorRange])
        let dimensionStrings = header[dimensionsRange].split(separator: ",")
        guard (1...2).contains(dimensionStrings.count) else {
            throw BarkDecoderError.invalidArray("unsupported array rank")
        }
        var dimensions: [Int] = []
        var elementCount = 1
        for dimension in dimensionStrings {
            guard let count = Int(dimension.trimmingCharacters(in: .whitespaces)), count > 0,
                  count <= 1_000_000, elementCount <= 8_500_000 / count else {
                throw BarkDecoderError.invalidArray("array dimensions are too large")
            }
            dimensions.append(count)
            elementCount *= count
        }
        shape = dimensions
        let width = descriptor == "<f4" ? 4 : descriptor == "<f2" ? 2 : 1
        let payloadStart = headerStart + headerLength
        guard bytes.count - payloadStart == elementCount * width else {
            throw BarkDecoderError.invalidArray("array size does not match its shape")
        }
        var decoded = [Float]()
        decoded.reserveCapacity(elementCount)
        for index in 0..<elementCount {
            if index % 65_536 == 0 { try Task.checkCancellation() }
            let offset = payloadStart + index * width
            let value: Float
            switch descriptor {
            case "<f4":
                let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
                value = Float(bitPattern: bits)
            case "<f2":
                value = Self.float16(UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
            default:
                value = Float(Int8(bitPattern: bytes[offset]))
            }
            guard value.isFinite else { throw BarkDecoderError.invalidArray("non-finite weight") }
            decoded.append(value)
        }
        values = decoded
    }

    private static func float16(_ bits: UInt16) -> Float {
        // Float16 is not available on every architecture in Quill's universal build.
        let sign: Float = bits & 0x8000 == 0 ? 1 : -1
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Float(bits & 0x03FF)
        if exponent == 0 { return sign * fraction * powf(2, -24) }
        if exponent == 31 { return fraction == 0 ? sign * .infinity : .nan }
        return sign * (1 + fraction / 1_024) * powf(2, Float(exponent - 15))
    }
}

final class BarkFrontend {
    private let filters: [Float]
    private let window: [Float]
    private let transform: vDSP_DFT_Setup

    init(melFilters: [Float]) throws {
        guard melFilters.count == 128 * 257, melFilters.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let transform = vDSP_DFT_zop_CreateSetup(nil, 512, .FORWARD) else {
            throw BarkDecoderError.invalidModel("invalid mel filters or unavailable FFT")
        }
        filters = melFilters
        self.transform = transform
        var window = [Float](repeating: 0, count: 512)
        for index in 0..<400 {
            window[56 + index] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(index) / 399))
        }
        self.window = window
    }

    deinit { vDSP_DFT_DestroySetup(transform) }

    func features(samples: [Float]) throws -> BarkFeatures {
        guard (160...240_000).contains(samples.count), samples.allSatisfy(\.isFinite) else {
            throw BarkDecoderError.invalidAudio
        }
        try Task.checkCancellation()
        var emphasized = samples
        for index in 1..<samples.count { emphasized[index] = samples[index] - 0.97 * samples[index - 1] }
        let validFrames = samples.count / 160
        let frameCount = validFrames + 1
        var features = [Float](repeating: 0, count: frameCount * 128)
        var input = [Float](repeating: 0, count: 512)
        let imaginaryInput = [Float](repeating: 0, count: 512)
        var real = [Float](repeating: 0, count: 512)
        var imaginary = [Float](repeating: 0, count: 512)
        var power = [Float](repeating: 0, count: 257)
        var mel = [Float](repeating: 0, count: 128)
        for frame in 0..<frameCount {
            if frame % 16 == 0 { try Task.checkCancellation() }
            for index in 0..<512 {
                let sampleIndex = frame * 160 + index - 256
                input[index] = sampleIndex >= 0 && sampleIndex < emphasized.count
                    ? emphasized[sampleIndex] * window[index] : 0
            }
            // A complex DFT with zero imaginary input has NumPy rfft's normalization.
            vDSP_DFT_Execute(transform, input, imaginaryInput, &real, &imaginary)
            for bin in 0..<257 { power[bin] = real[bin] * real[bin] + imaginary[bin] * imaginary[bin] }
            cblas_sgemv(CblasRowMajor, CblasNoTrans, 128, 257, 1, filters, 257, power, 1, 0, &mel, 1)
            for channel in 0..<128 { features[frame * 128 + channel] = logf(mel[channel] + powf(2, -24)) }
        }
        for channel in 0..<128 {
            var mean: Float = 0
            for frame in 0..<validFrames { mean += features[frame * 128 + channel] }
            mean /= Float(validFrames)
            var squaredDifference: Float = 0
            for frame in 0..<validFrames {
                let difference = features[frame * 128 + channel] - mean
                squaredDifference += difference * difference
            }
            let standardDeviation = sqrtf(squaredDifference / Float(max(1, validFrames - 1)))
            for frame in 0..<validFrames {
                features[frame * 128 + channel] = (features[frame * 128 + channel] - mean) / (standardDeviation + 1e-5)
            }
            features[validFrames * 128 + channel] = 0
        }
        guard features.allSatisfy(\.isFinite) else { throw BarkDecoderError.invalidAudio }
        return BarkFeatures(values: features, frameCount: frameCount, validFrameCount: validFrames)
    }
}

struct BarkDecodingProgress {
    private(set) var frameIndex = 0
    private(set) var symbolsAtFrame = 0

    mutating func advance(isBlank: Bool, duration: Int, maxSymbols: Int) {
        if isBlank {
            frameIndex += max(duration, 1)
            symbolsAtFrame = 0
        } else {
            symbolsAtFrame += 1
            let advance = duration == 0 && symbolsAtFrame >= maxSymbols ? 1 : duration
            if advance > 0 { symbolsAtFrame = 0 }
            frameIndex += advance
        }
    }
}

/// CPU stages ported from Conway Research's Bark 3.0 Core ML reference (CC-BY-4.0).
/// The encoder supplies already-projected 640-component frames.
final class BarkDecoder {
    private struct Vocabulary: Decodable {
        let vocabularySize: Int
        let blankID: Int
        let durations: [Int]
        let maxSymbols: Int
        let pieces: [String]
        let specialIDs: [Int]

        enum CodingKeys: String, CodingKey {
            case vocabularySize = "vocab_size", blankID = "blank_id"
            case durations, pieces
            case maxSymbols = "max_symbols_per_step", specialIDs = "special_ids"
        }
    }

    private struct Matrix {
        let values: [Float]
        let rows: Int
        let columns: Int

        func addProduct(_ input: [Float], to output: inout [Float]) {
            cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(columns), 1,
                        values, Int32(columns), input, 1, 1, &output, 1)
        }
    }

    private struct Layer {
        let inputWeights: Matrix
        let recurrentWeights: Matrix
        let bias: [Float]
    }

    private struct State {
        var hidden = [Float](repeating: 0, count: 640)
        var cell = [Float](repeating: 0, count: 640)
    }

    private let vocabulary: Vocabulary
    private let specialIDs: Set<Int>
    private let embedding: Matrix
    private let layers: [Layer]
    private let projection: Matrix
    private let projectionBias: [Float]
    private let head: Matrix
    private let headBias: [Float]
    private let frontend: BarkFrontend

    init(directory: URL, vocabularyURL: URL) throws {
        let vocabularySize = try vocabularyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard vocabularySize > 0, vocabularySize <= 1_048_576 else {
            throw BarkDecoderError.invalidModel("invalid vocabulary size")
        }
        let vocabulary = try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: vocabularyURL))
        guard vocabulary.vocabularySize == 8193, vocabulary.blankID == 8192,
              vocabulary.durations == [0, 1, 2, 3, 4], vocabulary.maxSymbols == 10,
              vocabulary.pieces.count == 8192,
              vocabulary.specialIDs.allSatisfy({ (0..<8193).contains($0) }) else {
            throw BarkDecoderError.invalidModel("unsupported vocabulary configuration")
        }
        self.vocabulary = vocabulary
        specialIDs = Set(vocabulary.specialIDs)

        func array(_ name: String, shape: [Int]) throws -> [Float] {
            let array = try BarkNumpyArray(contentsOf: directory.appendingPathComponent(name + ".npy"))
            guard array.shape == shape else { throw BarkDecoderError.invalidModel("unexpected shape for \(name)") }
            return array.values
        }
        func matrix(_ name: String, rows: Int, columns: Int) throws -> Matrix {
            let quantized = try BarkNumpyArray(contentsOf: directory.appendingPathComponent(name + ".q.npy"))
            guard quantized.shape == [rows, columns], quantized.descriptor == "|i1" else {
                throw BarkDecoderError.invalidModel("unexpected quantization for \(name)")
            }
            let scales = try array(name + ".s", shape: [rows])
            guard scales.allSatisfy({ $0 >= 0 }) else {
                throw BarkDecoderError.invalidModel("negative quantization scale")
            }
            var values = quantized.values
            for row in 0..<rows {
                if row % 128 == 0 { try Task.checkCancellation() }
                for column in 0..<columns { values[row * columns + column] *= scales[row] }
            }
            guard values.allSatisfy(\.isFinite) else { throw BarkDecoderError.invalidModel("invalid dequantized weight") }
            return Matrix(values: values, rows: rows, columns: columns)
        }

        embedding = try matrix("decoder.embedding.weight", rows: 8193, columns: 640)
        layers = try (0..<2).map { index in
            let inputBias = try array("decoder.lstm.bias_ih_l\(index)", shape: [2560])
            let recurrentBias = try array("decoder.lstm.bias_hh_l\(index)", shape: [2560])
            return Layer(
                inputWeights: try matrix("decoder.lstm.weight_ih_l\(index)", rows: 2560, columns: 640),
                recurrentWeights: try matrix("decoder.lstm.weight_hh_l\(index)", rows: 2560, columns: 640),
                bias: zip(inputBias, recurrentBias).map(+)
            )
        }
        projection = try matrix("decoder.decoder_projector.weight", rows: 640, columns: 640)
        projectionBias = try array("decoder.decoder_projector.bias", shape: [640])
        head = try matrix("joint.head.weight", rows: 8198, columns: 640)
        headBias = try array("joint.head.bias", shape: [8198])
        frontend = try BarkFrontend(melFilters: array("mel_filters", shape: [128, 257]))
    }

    func features(samples: [Float]) throws -> BarkFeatures { try frontend.features(samples: samples) }

    func decode(encoded: [Float], frameCount: Int) throws -> String {
        guard (0...188).contains(frameCount), encoded.count == frameCount * 640,
              encoded.allSatisfy(\.isFinite) else { throw BarkDecoderError.invalidEncoderOutput }
        guard frameCount > 0 else { return "" }
        var state = [State(), State()]
        var prediction = try step(token: vocabulary.blankID, state: &state)
        var progress = BarkDecodingProgress()
        var tokens: [Int] = []
        while progress.frameIndex < frameCount {
            try Task.checkCancellation()
            let offset = progress.frameIndex * 640
            var joint = [Float](repeating: 0, count: 640)
            for index in 0..<640 { joint[index] = max(encoded[offset + index] + prediction[index], 0) }
            var logits = headBias
            head.addProduct(joint, to: &logits)
            guard logits.allSatisfy(\.isFinite) else { throw BarkDecoderError.invalidEncoderOutput }
            let token = Self.argmax(logits, range: 0..<vocabulary.vocabularySize)
            let durationIndex = Self.argmax(logits, range: vocabulary.vocabularySize..<logits.count)
                - vocabulary.vocabularySize
            let isBlank = token == vocabulary.blankID
            if !isBlank {
                tokens.append(token)
                prediction = try step(token: token, state: &state)
            }
            progress.advance(isBlank: isBlank, duration: vocabulary.durations[durationIndex], maxSymbols: vocabulary.maxSymbols)
        }
        return tokens.filter { !specialIDs.contains($0) && $0 < vocabulary.pieces.count }.map { vocabulary.pieces[$0] }.joined()
            .replacingOccurrences(of: "▁", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func step(token: Int, state: inout [State]) throws -> [Float] {
        var input = Array(embedding.values[(token * 640)..<((token + 1) * 640)])
        for index in layers.indices {
            try Task.checkCancellation()
            let layer = layers[index]
            var gates = layer.bias
            layer.inputWeights.addProduct(input, to: &gates)
            layer.recurrentWeights.addProduct(state[index].hidden, to: &gates)
            guard gates.allSatisfy(\.isFinite) else { throw BarkDecoderError.invalidEncoderOutput }
            for unit in 0..<640 {
                let inputGate = Self.sigmoid(gates[unit])
                let forgetGate = Self.sigmoid(gates[640 + unit])
                let candidate = tanhf(gates[1280 + unit])
                let outputGate = Self.sigmoid(gates[1920 + unit])
                let cell = forgetGate * state[index].cell[unit] + inputGate * candidate
                state[index].cell[unit] = cell
                state[index].hidden[unit] = outputGate * tanhf(cell)
            }
            input = state[index].hidden
        }
        var output = projectionBias
        projection.addProduct(input, to: &output)
        guard output.allSatisfy(\.isFinite) else { throw BarkDecoderError.invalidEncoderOutput }
        return output
    }

    private static func sigmoid(_ value: Float) -> Float {
        if value >= 0 { return 1 / (1 + expf(-value)) }
        let exponential = expf(value)
        return exponential / (1 + exponential)
    }

    private static func argmax(_ values: [Float], range: Range<Int>) -> Int {
        var best = range.lowerBound
        for index in range.dropFirst() where values[index] > values[best] { best = index }
        return best
    }
}
