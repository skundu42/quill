import XCTest
@testable import Quill

final class BarkDecoderTests: XCTestCase {
    func testNumpyFloat32AndInt8UseLittleEndianCOrder() throws {
        let floats: [Float] = [1.5, -2.25, 0, 12]
        let bytes = floats.flatMap { value in
            (0..<4).map { UInt8(truncatingIfNeeded: value.bitPattern >> ($0 * 8)) }
        }
        let array = try BarkNumpyArray(data: numpy(descriptor: "<f4", shape: "2, 2", payload: bytes))
        XCTAssertEqual(array.shape, [2, 2])
        XCTAssertEqual(array.values, floats)

        let integers = try BarkNumpyArray(data: numpy(descriptor: "|i1", shape: "4,", payload: [128, 255, 0, 127]))
        XCTAssertEqual(integers.values, [-128, -1, 0, 127])
    }

    func testNumpyFloat16PreservesSubnormalsAndSignedZero() throws {
        let bits: [UInt16] = [0, 0x8000, 1, 0x3C00, 0xC000, 0x7BFF]
        let bytes = bits.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
        let array = try BarkNumpyArray(data: numpy(descriptor: "<f2", shape: "6,", payload: bytes))
        XCTAssertEqual(array.values, [0, -0, powf(2, -24), 1, -2, 65_504])
        XCTAssertEqual(array.values[1].sign, .minus)
    }

    func testNumpyVersionTwoUsesFourByteHeaderLength() throws {
        let array = try BarkNumpyArray(data: numpy(descriptor: "|i1", shape: "1,", payload: [42], version: 2))
        XCTAssertEqual(array.values, [42])
    }

    func testNumpyRejectsMalformedUnsupportedAndOversizedArrays() {
        let invalid = [
            Data(),
            numpy(descriptor: "<f4", shape: "1,", payload: [0, 0]),
            numpy(descriptor: "<f4", shape: "1,", payload: [0, 0, 0, 0, 0]),
            numpy(descriptor: "<f4", shape: "0,", payload: []),
            numpy(descriptor: "<f4", shape: "999999, 999999", payload: []),
            numpy(descriptor: "<f4", shape: "1, 1, 1", payload: [0, 0, 0, 0]),
            numpy(descriptor: ">f4", shape: "1,", payload: [0, 0, 0, 0]),
            numpy(descriptor: "|i1", shape: "1,", payload: [0], fortranOrder: true),
            numpy(descriptor: "<f2", shape: "1,", payload: [0, 124]),
            numpy(descriptor: "<f4", shape: "1,", payload: [0, 0, 192, 127]),
        ]
        for data in invalid { XCTAssertThrowsError(try BarkNumpyArray(data: data)) }
    }

    func testFrontendMatchesNumpyReferenceForWindowFFTAndNormalization() throws {
        // Captured from the pinned bark_coreml.py Frontend, with one-hot mel filters.
        // Mixed tones exercise pre-emphasis, the symmetric Hann window, and both edges.
        var filters = [Float](repeating: 0, count: 128 * 257)
        for channel in 0..<128 { filters[channel * 257 + channel + 1] = 1 }
        let frontend = try BarkFrontend(melFilters: filters)
        let samples = (0..<1600).map { index in
            Float(0.1 * sin(2 * Double.pi * 440 * Double(index) / 16_000)
                  + 0.03 * cos(2 * Double.pi * 1730 * Double(index) / 16_000))
        }
        let features = try frontend.features(samples: samples)
        XCTAssertEqual(features.frameCount, 11)
        XCTAssertEqual(features.validFrameCount, 10)
        let expected: [Float] = [2.29916167, 0.43734547, -0.33217943, -0.47843009, -0.88315535,
                                 -0.82002926, -0.46028221, -0.35372654, -0.48508102, 1.07637370]
        for frame in expected.indices {
            XCTAssertEqual(features.values[frame * 128], expected[frame], accuracy: 0.001, "frame \(frame)")
        }
        XCTAssertEqual(Array(features.values.suffix(128)), Array(repeating: 0, count: 128))
        for channel in 0..<128 {
            let mean = (0..<10).reduce(Float.zero) { $0 + features.values[$1 * 128 + channel] } / 10
            XCTAssertEqual(mean, 0, accuracy: 0.0001)
        }
    }

    func testFrontendSilenceIsFiniteAndRejectsInvalidAudio() throws {
        let frontend = try BarkFrontend(melFilters: Array(repeating: 0, count: 128 * 257))
        let silence = try frontend.features(samples: Array(repeating: 0, count: 4000))
        XCTAssertTrue(silence.values.allSatisfy(\.isFinite))
        // The reference's float32 mean accumulation leaves this finite residual.
        XCTAssertEqual(silence.values[0], -0.15965512, accuracy: 0.000001)
        XCTAssertEqual(Array(silence.values.suffix(128)), Array(repeating: 0, count: 128))
        XCTAssertThrowsError(try frontend.features(samples: []))
        XCTAssertThrowsError(try frontend.features(samples: Array(repeating: .nan, count: 160)))
        XCTAssertThrowsError(try frontend.features(samples: Array(repeating: 0, count: 240_001)))
    }

    func testTDTBlankAndSymbolLimitAlwaysAdvance() {
        var progress = BarkDecodingProgress()
        progress.advance(isBlank: true, duration: 0, maxSymbols: 10)
        XCTAssertEqual(progress.frameIndex, 1)
        for _ in 0..<9 { progress.advance(isBlank: false, duration: 0, maxSymbols: 10) }
        XCTAssertEqual(progress.frameIndex, 1)
        XCTAssertEqual(progress.symbolsAtFrame, 9)
        progress.advance(isBlank: false, duration: 0, maxSymbols: 10)
        XCTAssertEqual(progress.frameIndex, 2)
        XCTAssertEqual(progress.symbolsAtFrame, 0)
        progress.advance(isBlank: false, duration: 3, maxSymbols: 10)
        XCTAssertEqual(progress.frameIndex, 5)
        XCTAssertEqual(progress.symbolsAtFrame, 0)
        progress.advance(isBlank: false, duration: 0, maxSymbols: 10)
        progress.advance(isBlank: true, duration: 2, maxSymbols: 10)
        XCTAssertEqual(progress.frameIndex, 7)
        XCTAssertEqual(progress.symbolsAtFrame, 0)
    }

    private func numpy(descriptor: String, shape: String, payload: [UInt8], version: UInt8 = 1,
                       fortranOrder: Bool = false) -> Data {
        var header = "{'descr': '\(descriptor)', 'fortran_order': \(fortranOrder ? "True" : "False"), 'shape': (\(shape)), }"
        let offset = version == 1 ? 10 : 12
        header += String(repeating: " ", count: (64 - (offset + header.utf8.count + 1) % 64) % 64) + "\n"
        var bytes: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, version, 0]
        for index in 0..<(version == 1 ? 2 : 4) {
            bytes.append(UInt8(truncatingIfNeeded: header.utf8.count >> (index * 8)))
        }
        bytes += Array(header.utf8)
        bytes += payload
        return Data(bytes)
    }
}
