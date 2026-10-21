import CryptoKit
import XCTest
@testable import Quill

final class BarkTranscriberTests: XCTestCase {
    func testPCMIsDecodedAsLittleEndianSigned16Bit() throws {
        let samples = try BarkTranscriber.samples(from: Data([0, 0, 0xff, 0x7f, 0, 0x80, 0xff, 0xff]))
        XCTAssertEqual(samples, [0, 32767.0 / 32768, -1, -1.0 / 32768])
        XCTAssertThrowsError(try BarkTranscriber.samples(from: Data([1])))
    }

    func testSegmentationCoversEverySampleWithoutExceedingEncoderWindow() {
        for count in [1, 128_000, 236_000, 236_001, 480_000, 4_800_000] {
            let samples = (0..<count).map { Float($0 % 997) / 997 }
            let ranges = BarkTranscriber.segmentRanges(samples)
            XCTAssertEqual(ranges.first?.lowerBound, 0)
            XCTAssertEqual(ranges.last?.upperBound, count)
            XCTAssertEqual(ranges.reduce(0) { $0 + $1.count }, count)
            for (index, range) in ranges.enumerated() {
                XCTAssertGreaterThan(range.count, 0)
                XCTAssertLessThanOrEqual(range.count + 4_000, 240_000)
                if index > 0 { XCTAssertEqual(ranges[index - 1].upperBound, range.lowerBound) }
            }
        }
    }

    func testSegmentationChoosesAPause() {
        var samples = [Float](repeating: 0.5, count: 320_000)
        samples.replaceSubrange(150_000..<170_000, with: repeatElement(0, count: 20_000))
        let ranges = BarkTranscriber.segmentRanges(samples)
        XCTAssertTrue((150_000..<170_000).contains(ranges[0].upperBound))
    }

    func testEncodedLengthsMatchThreeStrideTwoConvolutions() {
        XCTAssertEqual(BarkTranscriber.encodedLength(1), 1)
        XCTAssertEqual(BarkTranscriber.encodedLength(800), 100)
        XCTAssertEqual(BarkTranscriber.encodedLength(1_475), 185)
    }

    func testSilenceFinishesWithoutLoadingAModel() async throws {
        let transcriber = BarkTranscriber(directory: URL(fileURLWithPath: "/nonexistent-bark-model"))
        #if arch(arm64)
        if #available(macOS 15, *) {
            let text = try await transcriber.transcribe(pcm: Data(repeating: 0, count: 32_000))
            XCTAssertEqual(text, "")
        }
        #endif
    }

    func testCancelledTranscriptionDoesNotLoadAModel() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BarkTranscriber(directory: URL(fileURLWithPath: "/nonexistent-bark-model"))
                .transcribe(pcm: Data([1, 0]))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled inference must throw")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testModelArtifactRejectsWrongSizeAndDigest() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("verified model".utf8)
        try data.write(to: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertNoThrow(try BarkModelFiles.verify(url, artifact: .init(path: "test", size: Int64(data.count), sha256: digest)))
        XCTAssertThrowsError(try BarkModelFiles.verify(url, artifact: .init(path: "test", size: 1, sha256: digest)))
        XCTAssertThrowsError(try BarkModelFiles.verify(url, artifact: .init(path: "test", size: Int64(data.count), sha256: "incorrect")))
    }
}
