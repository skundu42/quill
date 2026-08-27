import XCTest
@testable import Quill

final class AudioChunkAccumulatorTests: XCTestCase {
    func testEmitsExactChunksAndKeepsRemainder() {
        var accumulator = AudioChunkAccumulator(chunkSize: 4)

        XCTAssertEqual(accumulator.append(Data([1, 2, 3])), [])
        XCTAssertEqual(accumulator.append(Data([4, 5, 6, 7, 8])), [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])])
        XCTAssertNil(accumulator.flush())
    }

    func testFlushReturnsPartialChunk() {
        var accumulator = AudioChunkAccumulator(chunkSize: 4)
        _ = accumulator.append(Data([1, 2]))
        XCTAssertEqual(accumulator.flush(), Data([1, 2]))
        XCTAssertNil(accumulator.flush())
    }
}
