import Foundation
@testable import OrbitCore

enum TestClock {
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    /// Monday 2 November 2026, 12:00 UTC.
    static let now: Date = date(2026, 11, 2, 12)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func parts(_ date: Date) -> (y: Int, m: Int, d: Int, h: Int) {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return (c.year!, c.month!, c.day!, c.hour!)
    }

    static var usDates: DatePhraseParser { DatePhraseParser(calendar: calendar, locale: Locale(identifier: "en_US")) }
    static var ukDates: DatePhraseParser { DatePhraseParser(calendar: calendar, locale: Locale(identifier: "en_GB")) }
}
