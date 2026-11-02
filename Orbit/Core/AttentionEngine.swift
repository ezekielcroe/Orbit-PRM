import Foundation

// MARK: - AttentionEngine
// Decides who appears on Today and why. Replaces the separate "drifting" and
// "losing momentum" lists with one ranked list and one plain-language reason
// per person. Pure Foundation — the app passes value snapshots in.
//
// Eligibility
//   • not archived, closeness has a cadence (orbit 0–3)
//   • not snoozed
//   • has history, OR the user has confirmed their closeness. Imported people
//     with no history never flood the list on day one.
//
// Score (higher = more urgent)
//   dueness  = daysSince / cadence           (≥ 1 means overdue)
//   fading   = how far momentum sits below the healthy band (0…1)
//   weight   = closer orbits matter more     (Inner Circle 5 … Outer 2)
//   score    = (max(dueness − 0.75, 0) + fading × 0.6) × weight
// A person is a candidate when overdue, or when fading with real history.

struct AttentionInput: Equatable {
    var id: UUID
    var name: String
    var orbit: Int
    var lastContact: Date?
    var interactionCount: Int
    var momentum: Double
    /// Mean gap between recent interactions, in days. 0 = unknown.
    var observedCadenceDays: Double
    var snoozedUntil: Date?
    var closenessConfirmed: Bool
    var isArchived: Bool
}

struct AttentionItem: Equatable, Identifiable {
    enum Kind: Equatable { case neverContacted, overdue, fading }
    let id: UUID
    let score: Double
    let kind: Kind
    let reason: String
}

enum AttentionEngine {

    static func cadenceDays(forOrbit orbit: Int) -> Int? {
        switch orbit {
        case 0: return 7
        case 1: return 30
        case 2: return 90
        case 3: return 365
        default: return nil
        }
    }

    static func cadenceWord(forOrbit orbit: Int) -> String {
        switch orbit {
        case 0: return "weekly"
        case 1: return "monthly"
        case 2: return "every few months"
        case 3: return "yearly"
        default: return "no set rhythm"
        }
    }

    static func isEligible(_ c: AttentionInput, now: Date) -> Bool {
        guard !c.isArchived, cadenceDays(forOrbit: c.orbit) != nil else { return false }
        if let until = c.snoozedUntil, until > now { return false }
        return c.interactionCount > 0 || c.closenessConfirmed
    }

    /// Whether this person is past their cadence (and counts for attention).
    static func isOverdue(_ c: AttentionInput, now: Date, calendar: Calendar = .current) -> Bool {
        guard let cadence = cadenceDays(forOrbit: c.orbit), !c.isArchived else { return false }
        guard let last = c.lastContact else { return c.closenessConfirmed }
        return days(from: last, to: now, calendar: calendar) > cadence
    }

    static func evaluate(_ c: AttentionInput, now: Date, calendar: Calendar = .current) -> AttentionItem? {
        guard isEligible(c, now: now), let cadence = cadenceDays(forOrbit: c.orbit) else { return nil }
        let weight = Double(5 - c.orbit)
        let firstName = c.name.split(separator: " ").first.map(String.init) ?? c.name

        guard let last = c.lastContact else {
            return AttentionItem(
                id: c.id,
                score: 0.75 * weight,
                kind: .neverContacted,
                reason: "Nothing logged with \(firstName) yet. You'd like to be in touch \(cadenceWord(forOrbit: c.orbit))."
            )
        }

        let daysSince = days(from: last, to: now, calendar: calendar)
        let dueness = Double(daysSince) / Double(cadence)
        let fading = (c.interactionCount >= 2) ? max(0, min(1, 1 - c.momentum)) : 0

        let overdue = daysSince > cadence
        guard overdue || fading > 0.25 else { return nil }

        let score = (max(dueness - 0.75, 0) + fading * 0.6) * weight
        let reason = reasonText(firstName: firstName, daysSince: daysSince, cadence: cadence, orbit: c.orbit,
                                observed: c.observedCadenceDays, overdue: overdue)
        return AttentionItem(id: c.id, score: score, kind: overdue ? .overdue : .fading, reason: reason)
    }

    static func ranked(_ inputs: [AttentionInput], now: Date, calendar: Calendar = .current) -> [AttentionItem] {
        inputs
            .compactMap { evaluate($0, now: now, calendar: calendar) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: Daily picks
    // Today shows a short list that stays put for the whole day, so logging or
    // snoozing someone ticks them off instead of reshuffling the list.

    struct DailyPicks: Equatable {
        var day: String      // yyyy-MM-dd
        var ids: [UUID]
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Reuse the picks already made today; otherwise take the top `count`.
    static func dailyPicks(ranked: [AttentionItem], previous: DailyPicks?, now: Date, count: Int = 5, calendar: Calendar = .current) -> DailyPicks {
        let today = dayKey(for: now, calendar: calendar)
        if let previous, previous.day == today, !previous.ids.isEmpty {
            return previous
        }
        return DailyPicks(day: today, ids: ranked.prefix(count).map(\.id))
    }

    // MARK: Helpers

    static func days(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    static func describeSpan(days: Int) -> String {
        switch days {
        case ..<1: return "today"
        case 1: return "a day"
        case 2...13: return "\(days) days"
        case 14...59: return "\(Int((Double(days) / 7).rounded())) weeks"
        case 60...364: return "\(Int((Double(days) / 30).rounded())) months"
        default:
            let years = Int((Double(days) / 365).rounded())
            return years <= 1 ? "over a year" : "\(years) years"
        }
    }

    private static func reasonText(firstName: String, daysSince: Int, cadence: Int, orbit: Int, observed: Double, overdue: Bool) -> String {
        let span = describeSpan(days: daysSince)
        let usual = Int(observed.rounded())
        if usual > 0, Double(daysSince) > observed * 1.5, daysSince - usual >= 2 {
            let rhythm = usual == 1 ? "day" : describeSpan(days: usual)
            return "You used to talk every \(rhythm) — it's been \(span)."
        }
        if overdue {
            return "It's been \(span). You'd like to be in touch \(cadenceWord(forOrbit: orbit))."
        }
        return "Still on track, but you've been in touch with \(firstName) less often lately."
    }
}
