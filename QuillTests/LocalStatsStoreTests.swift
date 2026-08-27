import XCTest
@testable import Quill

@MainActor
final class LocalStatsStoreTests: XCTestCase {
    func testRecordingUpdatesDailyAndLifetimeTotals() {
        let suite = "LocalStatsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalStatsStore(defaults: defaults, now: { Date(timeIntervalSince1970: 1_700_000_000) })

        store.record(transcript: "A short local dictation")

        XCTAssertEqual(store.todayDictations, 1)
        XCTAssertEqual(store.todayWords, 4)
        XCTAssertEqual(store.totalDictations, 1)
        XCTAssertEqual(store.totalWords, 4)
    }

    func testDailyCountsResetWithoutClearingLifetimeTotals() {
        let suite = "LocalStatsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        let store = LocalStatsStore(defaults: defaults, now: { date })
        store.record(transcript: "one two three")

        date.addTimeInterval(86_400)
        store.refreshDay()

        XCTAssertEqual(store.todayDictations, 0)
        XCTAssertEqual(store.todayWords, 0)
        XCTAssertEqual(store.totalDictations, 1)
        XCTAssertEqual(store.totalWords, 3)
    }
}
