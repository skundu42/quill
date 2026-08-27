import XCTest
@testable import Quill

final class AudioLevelMeterTests: XCTestCase {
    func testSilenceProducesZeroLevel() {
        let samples = Array(repeating: Int16.zero, count: 512)
        let level = samples.withUnsafeBufferPointer { buffer in
            AudioLevelMeter.normalizedLevel(samples: buffer.baseAddress!, count: buffer.count)
        }

        XCTAssertEqual(level, 0, accuracy: 0.001)
    }

    func testFullScaleAudioIsClampedToOne() {
        let samples = Array(repeating: Int16.max, count: 512)
        let level = samples.withUnsafeBufferPointer { buffer in
            AudioLevelMeter.normalizedLevel(samples: buffer.baseAddress!, count: buffer.count)
        }

        XCTAssertEqual(level, 1, accuracy: 0.001)
    }

    func testTypicalVoiceLevelFallsInsideDisplayRange() {
        let samples = Array(repeating: Int16(1_200), count: 512)
        let level = samples.withUnsafeBufferPointer { buffer in
            AudioLevelMeter.normalizedLevel(samples: buffer.baseAddress!, count: buffer.count)
        }

        XCTAssertGreaterThan(level, 0.2)
        XCTAssertLessThan(level, 0.8)
    }

    func testLevelUpdateLimiterCapsDeliveryRate() {
        var limiter = AudioLevelUpdateLimiter(minimumInterval: .milliseconds(33))
        let start = ContinuousClock.now

        XCTAssertTrue(limiter.shouldDeliver(at: start))
        XCTAssertFalse(limiter.shouldDeliver(at: start.advanced(by: .milliseconds(20))))
        XCTAssertTrue(limiter.shouldDeliver(at: start.advanced(by: .milliseconds(34))))
    }

    func testLevelUpdateLimiterCanBeReset() {
        var limiter = AudioLevelUpdateLimiter(minimumInterval: .seconds(1))
        let start = ContinuousClock.now

        XCTAssertTrue(limiter.shouldDeliver(at: start))
        XCTAssertFalse(limiter.shouldDeliver(at: start))

        limiter.reset()

        XCTAssertTrue(limiter.shouldDeliver(at: start))
    }
}
