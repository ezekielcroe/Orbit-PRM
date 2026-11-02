import Foundation

// MARK: - DatePhraseParser
// Finds a natural-language date phrase inside free text and resolves it to a
// Date relative to `now`. Pure Foundation (no SwiftData / SwiftUI) so it is
// unit-testable with `swift test`.
//
// Interactions are things that already happened, so every phrase resolves to
// a moment at or before `now`. A bare "March 3" that would land in the future
// rolls back a year; "monday" means the most recent Monday.
//
// Supported phrases (case-insensitive):
//   today, tonight, this morning/afternoon/evening, just now
//   yesterday [morning|afternoon|evening|night], last night
//   N/a/an/one…twelve minutes|hours|days|weeks|months|years ago
//   a couple of days ago, a few days ago
//   last week, last month, last year, last weekend
//   [on|last] monday…sunday (also mon, tue, tues, wed, thu, thur, thurs, fri, sat, sun)
//   3 March, March 3, Mar 3rd, 3rd of March [2025]
//   2025-03-03, 3/3, 3/3/2025 (day/month order follows the locale when ambiguous)
// Optional trailing time: "at 3pm", "at 3:30 pm", "at 15:00".

struct DateMatch: Equatable {
    let date: Date
    let range: Range<String.Index>
    let phrase: String
}

struct DatePhraseParser {
    var calendar: Calendar = .current
    var locale: Locale = .current

    init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: - Public API

    /// Find the first date phrase in `text`. Returns nil if none is present.
    func firstMatch(in text: String, now: Date = Date()) -> DateMatch? {
        let ns = text as NSString
        var best: (range: NSRange, date: Date)?

        for rule in rules {
            let matches = rule.regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                guard let date = rule.resolve(match, ns, now) else { continue }
                // Earliest wins; on a tie, the longer phrase wins.
                if let current = best {
                    if match.range.location < current.range.location ||
                        (match.range.location == current.range.location && match.range.length > current.range.length) {
                        best = (match.range, date)
                    }
                } else {
                    best = (match.range, date)
                }
                break // only the first hit per rule matters for "earliest"
            }
        }

        guard let found = best, let range = Range(found.range, in: text) else { return nil }
        let withTime = applyTrailingTime(to: found.date, in: text, after: range, now: now)
        return DateMatch(date: withTime.date, range: range.lowerBound..<withTime.end, phrase: String(text[range.lowerBound..<withTime.end]))
    }

    /// Parse a string that should be *only* a date (e.g. a birthday fact value).
    /// Unlike `firstMatch`, a missing year is NOT rolled back — the caller gets
    /// the month/day in the year `referenceYear` (default 2000, a leap year so
    /// Feb 29 survives).
    func parseCalendarDate(_ text: String, referenceYear: Int = 2000) -> (date: Date, hasYear: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)

        for pattern in [Self.isoPattern, Self.numericPattern, Self.dayMonthPattern, Self.monthDayPattern] {
            guard let regex = try? NSRegularExpression(pattern: "^\\s*" + pattern + "\\s*$", options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: trimmed, options: [], range: full),
                  let parts = calendarParts(from: m, ns, pattern: pattern) else { continue }
            let year = parts.year ?? referenceYear
            guard let date = makeDate(year: year, month: parts.month, day: parts.day, hour: 12) else { continue }
            return (date, parts.year != nil)
        }
        return nil
    }

    /// Resolve the legacy `^` shorthand used by the command palette:
    /// "2d", "3h", "1w", "1m" (months), "1y", plus any phrase `firstMatch` understands.
    /// Returns nil when the modifier isn't understood — callers should surface
    /// that as an error instead of silently using "now".
    func resolveShorthand(_ modifier: String, now: Date = Date()) -> Date? {
        let mod = modifier.trimmingCharacters(in: .whitespaces).lowercased()
        guard !mod.isEmpty else { return nil }

        if let regex = try? NSRegularExpression(pattern: "^(\\d{1,4})(h|d|w|m|y)$"),
           let m = regex.firstMatch(in: mod, range: NSRange(location: 0, length: (mod as NSString).length)) {
            let ns = mod as NSString
            guard let n = Int(ns.substring(with: m.range(at: 1))) else { return nil }
            switch ns.substring(with: m.range(at: 2)) {
            case "h": return calendar.date(byAdding: .hour, value: -n, to: now)
            case "d": return calendar.date(byAdding: .day, value: -n, to: now)
            case "w": return calendar.date(byAdding: .weekOfYear, value: -n, to: now)
            case "m": return calendar.date(byAdding: .month, value: -n, to: now)
            case "y": return calendar.date(byAdding: .year, value: -n, to: now)
            default: return nil
            }
        }

        // Allow ^lastweek, ^last-monday, ^3days etc. by normalising separators.
        let spaced = mod
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let candidates = [spaced, Self.splitGlued(spaced)]
        for candidate in candidates {
            if let match = firstMatch(in: candidate, now: now),
               match.phrase.count == candidate.trimmingCharacters(in: .whitespaces).count {
                return match.date
            }
        }
        return nil
    }

    // MARK: - Rules

    private struct Rule {
        let regex: NSRegularExpression
        let resolve: (NSTextCheckingResult, NSString, Date) -> Date?
    }

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "couple of": 2, "a couple of": 2, "few": 3, "a few": 3,
    ]

    private static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
    ]

    private static let monthAlternation = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
    private static let weekdayAlternation = "mon(?:day)?|tues?(?:day)?|wed(?:nesday)?|thu(?:r(?:s)?)?(?:sday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?"
    private static let numberAlternation = "\\d{1,3}|a couple of|couple of|a few|few|an|a|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"

    static let isoPattern = "(\\d{4})-(\\d{1,2})-(\\d{1,2})"
    static let numericPattern = "(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?"
    static let dayMonthPattern = "(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+of)?\\s+(\(monthAlternation))\\.?(?:,?\\s+(\\d{4}))?"
    static let monthDayPattern = "(\(monthAlternation))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?"

    private var rules: [Rule] {
        var list: [Rule] = []
        func add(_ pattern: String, _ resolve: @escaping (NSTextCheckingResult, NSString, Date) -> Date?) {
            // \b on both sides keeps "mon" from matching inside "money".
            let wrapped = "(?<![\\w/-])(?:" + pattern + ")(?![\\w/-])"
            if let regex = try? NSRegularExpression(pattern: wrapped, options: [.caseInsensitive]) {
                list.append(Rule(regex: regex, resolve: resolve))
            }
        }
        let cal = calendar

        add("just now|right now") { _, _, now in now }
        add("today") { _, _, now in now }
        add("this (morning|afternoon|evening)") { m, ns, now in
            self.atPeriod(ns.substring(with: m.range(at: 1)), on: now, now: now)
        }
        add("tonight") { _, _, now in self.atPeriod("night", on: now, now: now) }
        add("yesterday(?:\\s+(morning|afternoon|evening|night))?") { m, ns, now in
            guard let day = cal.date(byAdding: .day, value: -1, to: now) else { return nil }
            if m.range(at: 1).location != NSNotFound {
                return self.atPeriod(ns.substring(with: m.range(at: 1)), on: day, now: nil)
            }
            return day
        }
        add("last night") { _, _, now in
            guard let day = cal.date(byAdding: .day, value: -1, to: now) else { return nil }
            return self.atPeriod("night", on: day, now: nil)
        }
        add("(\(Self.numberAlternation))\\s+(minute|min|hour|hr|day|week|wk|month|year|yr)s?\\s+ago") { m, ns, now in
            let rawNumber = ns.substring(with: m.range(at: 1)).lowercased()
            guard let n = Int(rawNumber) ?? Self.numberWords[rawNumber] else { return nil }
            let unit = ns.substring(with: m.range(at: 2)).lowercased()
            switch unit {
            case "minute", "min": return cal.date(byAdding: .minute, value: -n, to: now)
            case "hour", "hr": return cal.date(byAdding: .hour, value: -n, to: now)
            case "day": return cal.date(byAdding: .day, value: -n, to: now)
            case "week", "wk": return cal.date(byAdding: .weekOfYear, value: -n, to: now)
            case "month": return cal.date(byAdding: .month, value: -n, to: now)
            case "year", "yr": return cal.date(byAdding: .year, value: -n, to: now)
            default: return nil
            }
        }
        add("last (week|month|year)") { m, ns, now in
            switch ns.substring(with: m.range(at: 1)).lowercased() {
            case "week": return cal.date(byAdding: .weekOfYear, value: -1, to: now)
            case "month": return cal.date(byAdding: .month, value: -1, to: now)
            default: return cal.date(byAdding: .year, value: -1, to: now)
            }
        }
        add("last weekend|this weekend|the weekend|over the weekend") { _, _, now in
            // Most recent Saturday strictly before today (or today if it is Saturday/Sunday).
            let weekday = cal.component(.weekday, from: now)
            let back: Int
            switch weekday {
            case 7: back = 0          // Saturday
            case 1: back = 1          // Sunday → yesterday's Saturday
            default: back = weekday   // Mon(2)→2 … Fri(6)→6
            }
            return self.noon(cal.date(byAdding: .day, value: -back, to: now) ?? now)
        }
        add("(?:(last|on|this past)\\s+)?(\(Self.weekdayAlternation))") { m, ns, now in
            let qualifier = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)).lowercased() : ""
            let name = ns.substring(with: m.range(at: 2)).lowercased()
            // A bare "sat"/"sun"/"wed" with no qualifier is too likely to be an
            // ordinary word ("sat down", "sun was out"); require a qualifier for
            // three-letter abbreviations.
            if qualifier.isEmpty && name.count <= 3 { return nil }
            guard let target = Self.weekdayNames[name] else { return nil }
            let today = cal.component(.weekday, from: now)
            var back = (today - target + 7) % 7
            if back == 0 && qualifier == "last" { back = 7 }
            return self.noon(cal.date(byAdding: .day, value: -back, to: now) ?? now)
        }
        add(Self.isoPattern) { m, ns, now in
            guard let parts = self.calendarParts(from: m, ns, pattern: Self.isoPattern) else { return nil }
            return self.pastDate(parts, now: now)
        }
        add(Self.dayMonthPattern) { m, ns, now in
            guard let parts = self.calendarParts(from: m, ns, pattern: Self.dayMonthPattern) else { return nil }
            return self.pastDate(parts, now: now)
        }
        add(Self.monthDayPattern) { m, ns, now in
            guard let parts = self.calendarParts(from: m, ns, pattern: Self.monthDayPattern) else { return nil }
            return self.pastDate(parts, now: now)
        }
        add(Self.numericPattern) { m, ns, now in
            guard let parts = self.calendarParts(from: m, ns, pattern: Self.numericPattern) else { return nil }
            return self.pastDate(parts, now: now)
        }
        return list
    }

    // MARK: - Helpers

    private func calendarParts(from m: NSTextCheckingResult, _ ns: NSString, pattern: String) -> (year: Int?, month: Int, day: Int)? {
        func group(_ i: Int) -> String? {
            guard i < m.numberOfRanges else { return nil }
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        // Rules wrap the pattern in one non-capturing group, so indexes are unchanged.
        switch pattern {
        case Self.isoPattern:
            guard let y = group(1).flatMap(Int.init), let mo = group(2).flatMap(Int.init), let d = group(3).flatMap(Int.init) else { return nil }
            return validated(year: y, month: mo, day: d)
        case Self.dayMonthPattern:
            guard let d = group(1).flatMap(Int.init), let name = group(2), let mo = monthNumber(name) else { return nil }
            return validated(year: group(3).flatMap(Int.init), month: mo, day: d)
        case Self.monthDayPattern:
            guard let name = group(1), let mo = monthNumber(name), let d = group(2).flatMap(Int.init) else { return nil }
            return validated(year: group(3).flatMap(Int.init), month: mo, day: d)
        case Self.numericPattern:
            guard let a = group(1).flatMap(Int.init), let b = group(2).flatMap(Int.init) else { return nil }
            var year = group(3).flatMap(Int.init)
            if let y = year, y < 100 { year = 2000 + y }
            let (month, day): (Int, Int)
            if a > 12 && b <= 12 { (month, day) = (b, a) }
            else if b > 12 && a <= 12 { (month, day) = (a, b) }
            else { (month, day) = dayFirstLocale ? (b, a) : (a, b) }
            return validated(year: year, month: month, day: day)
        default:
            return nil
        }
    }

    private func validated(year: Int?, month: Int, day: Int) -> (year: Int?, month: Int, day: Int)? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let y = year, !(1900...2200).contains(y) { return nil }
        return (year, month, day)
    }

    private func monthNumber(_ name: String) -> Int? {
        let key = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let n = Self.monthNames[key] { return n }
        if key.hasPrefix("sept") { return 9 }
        return Self.monthNames[String(key.prefix(3))]
    }

    /// True when the locale writes numeric dates day-first (e.g. en_GB, en_SG).
    var dayFirstLocale: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: locale) ?? "M/d"
        guard let d = format.firstIndex(of: "d"), let m = format.firstIndex(of: "M") else { return false }
        return d < m
    }

    private func pastDate(_ parts: (year: Int?, month: Int, day: Int), now: Date) -> Date? {
        let thisYear = calendar.component(.year, from: now)
        if let y = parts.year {
            return makeDate(year: y, month: parts.month, day: parts.day, hour: 12)
        }
        guard let candidate = makeDate(year: thisYear, month: parts.month, day: parts.day, hour: 12) else { return nil }
        if calendar.startOfDay(for: candidate) > calendar.startOfDay(for: now) {
            return makeDate(year: thisYear - 1, month: parts.month, day: parts.day, hour: 12)
        }
        return candidate
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
        guard let date = calendar.date(from: comps) else { return nil }
        // Reject rollovers like 31 February → 3 March.
        guard calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
        return date
    }

    private func noon(_ date: Date) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    /// Set a representative hour for a part of day. When `now` is given and the
    /// result would be in the future (e.g. "this evening" typed at 3pm), clamp to now.
    private func atPeriod(_ period: String, on day: Date, now: Date?) -> Date? {
        let hour: Int
        switch period.lowercased() {
        case "morning": hour = 9
        case "afternoon": hour = 14
        case "evening": hour = 19
        default: hour = 20 // night
        }
        guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
        if let now, date > now { return now }
        return date
    }

    private static let timeRegex = try? NSRegularExpression(
        pattern: "^\\s*(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm|a\\.m\\.|p\\.m\\.)?(?![\\w])",
        options: [.caseInsensitive]
    )

    /// Look for "at 3pm" / "at 15:30" directly after the date phrase.
    private func applyTrailingTime(to date: Date, in text: String, after range: Range<String.Index>, now: Date) -> (date: Date, end: String.Index) {
        let tail = String(text[range.upperBound...])
        guard let regex = Self.timeRegex else { return (date, range.upperBound) }
        let ns = tail as NSString
        guard let m = regex.firstMatch(in: tail, range: NSRange(location: 0, length: ns.length)) else { return (date, range.upperBound) }

        // Require either "at" or an am/pm marker or a colon, so "3 March 2025 2 friends" doesn't parse "2" as a time.
        let matchedText = ns.substring(with: m.range).lowercased()
        let hasAt = matchedText.trimmingCharacters(in: .whitespaces).hasPrefix("at")
        let hasMeridiem = m.range(at: 3).location != NSNotFound
        let hasMinutes = m.range(at: 2).location != NSNotFound
        guard hasAt || hasMeridiem || hasMinutes else { return (date, range.upperBound) }

        guard var hour = Int(ns.substring(with: m.range(at: 1))) else { return (date, range.upperBound) }
        let minute = hasMinutes ? Int(ns.substring(with: m.range(at: 2))) ?? 0 : 0
        if hasMeridiem {
            let meridiem = ns.substring(with: m.range(at: 3)).lowercased()
            if meridiem.hasPrefix("p") && hour < 12 { hour += 12 }
            if meridiem.hasPrefix("a") && hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute),
              let withTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else {
            return (date, range.upperBound)
        }
        guard let tailRange = Range(m.range, in: tail) else { return (date, range.upperBound) }
        let consumed = tail.distance(from: tail.startIndex, to: tailRange.upperBound)
        let end = text.index(range.upperBound, offsetBy: consumed)
        return (min(withTime, max(now, date)), end)
    }

    /// "lastweek" → "last week", "3days" → "3 days", "2daysago" → "2 days ago".
    private static func splitGlued(_ s: String) -> String {
        var out = s
        let words = "(yesterday|today|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekend|last|this|ago|minutes|minute|hours|hour|days|day|weeks|week|months|month|years|year)"
        if let regex = try? NSRegularExpression(pattern: words) {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: " $1 ")
        }
        if let regex = try? NSRegularExpression(pattern: "(\\d)([a-z])") {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "$1 $2")
        }
        return out.split(separator: " ").joined(separator: " ")
    }
}
