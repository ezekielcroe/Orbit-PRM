import Foundation

// MARK: - Birthdays
// Date facts ("birthday", "anniversary") are free text in the database. These
// helpers turn them into dates and work out the next occurrence for reminders.

enum Birthdays {

    /// Keys whose values should be treated as recurring yearly dates.
    static let recurringKeys = ["birthday", "bday", "anniversary", "born", "dob"]

    static func isRecurringDateKey(_ key: String) -> Bool {
        let k = key.lowercased()
        return recurringKeys.contains(where: { k.contains($0) })
    }

    /// Next occurrence of `date`'s month and day at or after the start of `now`'s day.
    /// Feb 29 falls back to Feb 28 in non-leap years.
    static func nextOccurrence(of date: Date, after now: Date, calendar: Calendar = .current) -> Date? {
        let md = calendar.dateComponents([.month, .day], from: date)
        guard let month = md.month, let day = md.day else { return nil }
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: now)

        for y in [year, year + 1] {
            var comps = DateComponents(year: y, month: month, day: day)
            var candidate = calendar.date(from: comps)
            if month == 2 && day == 29, let c = candidate, calendar.component(.month, from: c) != 2 {
                comps.day = 28
                candidate = calendar.date(from: comps)
            }
            if let c = candidate, c >= today { return c }
        }
        return nil
    }

    /// Whole days from today until the next occurrence (0 = today).
    static func daysUntil(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int? {
        guard let next = nextOccurrence(of: date, after: now, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: next).day
    }
}
