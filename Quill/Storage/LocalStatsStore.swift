import Combine
import Foundation

@MainActor
final class LocalStatsStore: ObservableObject {
    static let shared = LocalStatsStore()

    private enum Key {
        static let totalDictations = "stats.totalDictations"
        static let totalWords = "stats.totalWords"
        static let todayDictations = "stats.todayDictations"
        static let todayWords = "stats.todayWords"
        static let dayStamp = "stats.dayStamp"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    @Published private(set) var totalDictations: Int
    @Published private(set) var totalWords: Int
    @Published private(set) var todayDictations: Int
    @Published private(set) var todayWords: Int

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        totalDictations = defaults.integer(forKey: Key.totalDictations)
        totalWords = defaults.integer(forKey: Key.totalWords)
        todayDictations = defaults.integer(forKey: Key.todayDictations)
        todayWords = defaults.integer(forKey: Key.todayWords)
        rollToCurrentDayIfNeeded()
    }

    func record(transcript: String) {
        rollToCurrentDayIfNeeded()
        let words = transcript.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return }

        totalDictations += 1
        totalWords += words
        todayDictations += 1
        todayWords += words
        persist()
    }

    func refreshDay() {
        rollToCurrentDayIfNeeded()
    }

    func reset() {
        totalDictations = 0
        totalWords = 0
        todayDictations = 0
        todayWords = 0
        persist()
    }

    private func rollToCurrentDayIfNeeded() {
        let stamp = Self.dayStamp(for: now(), calendar: calendar)
        guard defaults.string(forKey: Key.dayStamp) != stamp else { return }
        todayDictations = 0
        todayWords = 0
        defaults.set(stamp, forKey: Key.dayStamp)
        defaults.set(0, forKey: Key.todayDictations)
        defaults.set(0, forKey: Key.todayWords)
    }

    private func persist() {
        defaults.set(totalDictations, forKey: Key.totalDictations)
        defaults.set(totalWords, forKey: Key.totalWords)
        defaults.set(todayDictations, forKey: Key.todayDictations)
        defaults.set(todayWords, forKey: Key.todayWords)
        defaults.set(Self.dayStamp(for: now(), calendar: calendar), forKey: Key.dayStamp)
    }

    private static func dayStamp(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
