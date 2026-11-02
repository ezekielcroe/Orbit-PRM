import XCTest
// Works both as the SwiftPM test target (module OrbitCore) and as an Xcode
// unit-test target hosted by the app (module Orbit).
#if canImport(OrbitCore)
@testable import OrbitCore
#else
@testable import Orbit
#endif

@MainActor
final class NameMatcherTests: XCTestCase {
    let a = NameCandidate(id: UUID(), name: "Sarah Connor")
    let b = NameCandidate(id: UUID(), name: "Sam Okafor")
    let c = NameCandidate(id: UUID(), name: "Sam Lee")
    let d = NameCandidate(id: UUID(), name: "José Álvarez")
    var all: [NameCandidate] { [a, b, c, d] }

    func testTiers() {
        XCTAssertEqual(NameMatcher.match("sarah connor", in: all), .unique(a.id))
        XCTAssertEqual(NameMatcher.match("sar", in: all), .unique(a.id))
        XCTAssertEqual(NameMatcher.match("connor", in: all), .unique(a.id))
        XCTAssertEqual(NameMatcher.match("Sam", in: all), .ambiguous([b.id, c.id]))
        XCTAssertEqual(NameMatcher.match("okaf", in: all), .unique(b.id))
        XCTAssertEqual(NameMatcher.match("jose", in: all), .unique(d.id))
        XCTAssertEqual(NameMatcher.match("zed", in: all), .none)
    }

    func testRankedPrefersPrefix() {
        let r = NameMatcher.ranked("sa", in: all).map(\.name)
        XCTAssertEqual(r.first, "Sam Lee")
        XCTAssertTrue(r.contains("Sarah Connor"))
    }
}

@MainActor
final class ActionVocabularyTests: XCTestCase {
    func testCanonical() {
        XCTAssertEqual(ActionVocabulary.canonical("text"), "Message")
        XCTAssertEqual(ActionVocabulary.canonical("Texted"), "Message")
        XCTAssertEqual(ActionVocabulary.canonical("  coffee "), "Coffee")
        XCTAssertEqual(ActionVocabulary.canonical("bouldering"), "Bouldering")
        XCTAssertEqual(ActionVocabulary.canonical("run", known: ["Run"]), "Run")
    }

    func testSuggestionsMergeHistoryAndDefaults() {
        let s = ActionVocabulary.suggestions(history: ["Text", "Message", "Run", "Run", "Run"], limit: 4)
        XCTAssertEqual(s.first, "Run")
        XCTAssertEqual(s[1], "Message")
        XCTAssertEqual(s.count, 4)
    }

    func testFindPrefersLongerPhrase() {
        XCTAssertEqual(ActionVocabulary.find(in: "video call with mum")?.action, "Video Call")
    }
}

@MainActor
final class AttentionEngineTests: XCTestCase {
    let now = TestClock.now
    let cal = TestClock.calendar

    private func input(orbit: Int = 1, daysAgo: Int? = nil, count: Int = 0, momentum: Double = 0,
                       observed: Double = 0, snoozedDays: Int? = nil, confirmed: Bool = false,
                       archived: Bool = false, name: String = "Alex Chen") -> AttentionInput {
        AttentionInput(
            id: UUID(), name: name, orbit: orbit,
            lastContact: daysAgo.map { cal.date(byAdding: .day, value: -$0, to: now)! },
            interactionCount: count, momentum: momentum, observedCadenceDays: observed,
            snoozedUntil: snoozedDays.map { cal.date(byAdding: .day, value: $0, to: now)! },
            closenessConfirmed: confirmed, isArchived: archived
        )
    }

    func testImportedNeverContactedDoesNotFloodToday() {
        let imported = (0..<200).map { _ in input(orbit: 2) }
        XCTAssertTrue(AttentionEngine.ranked(imported, now: now, calendar: cal).isEmpty)
    }

    func testConfirmedNeverContactedAppears() {
        let item = AttentionEngine.evaluate(input(orbit: 1, confirmed: true), now: now, calendar: cal)
        XCTAssertEqual(item?.kind, .neverContacted)
    }

    func testOverdueAndSnooze() {
        XCTAssertEqual(AttentionEngine.evaluate(input(orbit: 1, daysAgo: 45, count: 3, momentum: 0.6), now: now, calendar: cal)?.kind, .overdue)
        XCTAssertNil(AttentionEngine.evaluate(input(orbit: 1, daysAgo: 45, count: 3, snoozedDays: 7), now: now, calendar: cal))
        XCTAssertNil(AttentionEngine.evaluate(input(orbit: 1, daysAgo: 45, count: 3, archived: true), now: now, calendar: cal))
        XCTAssertNil(AttentionEngine.evaluate(input(orbit: 4, daysAgo: 900, count: 3), now: now, calendar: cal))
    }

    func testOnTrackAndHealthyIsNotListed() {
        XCTAssertNil(AttentionEngine.evaluate(input(orbit: 1, daysAgo: 5, count: 6, momentum: 1.4), now: now, calendar: cal))
    }

    func testFadingButOnTime() {
        let item = AttentionEngine.evaluate(input(orbit: 1, daysAgo: 20, count: 4, momentum: 0.5), now: now, calendar: cal)
        XCTAssertEqual(item?.kind, .fading)
        XCTAssertTrue(item!.reason.contains("less often"))
    }

    func testCloserOrbitRanksHigherForSameLapse() {
        let inner = input(orbit: 0, daysAgo: 14, count: 3, momentum: 0.3)
        let outer = input(orbit: 3, daysAgo: 730, count: 3, momentum: 0.3)
        let ranked = AttentionEngine.ranked([outer, inner], now: now, calendar: cal)
        XCTAssertEqual(ranked.first?.id, inner.id)
    }

    func testPlainLanguageReasonUsesObservedRhythm() {
        let item = AttentionEngine.evaluate(input(orbit: 1, daysAgo: 42, count: 8, momentum: 0.4, observed: 14), now: now, calendar: cal)!
        XCTAssertEqual(item.reason, "You used to talk every 2 weeks — it's been 6 weeks.")
        XCTAssertFalse(item.reason.contains("momentum"))
    }

    func testDailyPicksAreStableWithinADay() {
        let a = AttentionItem(id: UUID(), score: 3, kind: .overdue, reason: "")
        let b = AttentionItem(id: UUID(), score: 2, kind: .overdue, reason: "")
        let first = AttentionEngine.dailyPicks(ranked: [a, b], previous: nil, now: now, count: 1, calendar: cal)
        XCTAssertEqual(first.ids, [a.id])
        // Ranking changes later the same day → picks stay.
        let later = AttentionEngine.dailyPicks(ranked: [b, a], previous: first, now: now.addingTimeInterval(3600), count: 1, calendar: cal)
        XCTAssertEqual(later.ids, [a.id])
        // Next day → re-pick.
        let tomorrow = AttentionEngine.dailyPicks(ranked: [b, a], previous: first, now: now.addingTimeInterval(86_400), count: 1, calendar: cal)
        XCTAssertEqual(tomorrow.ids, [b.id])
    }
}

@MainActor
final class BirthdayTests: XCTestCase {
    let cal = TestClock.calendar

    func testNextOccurrence() {
        let bday = TestClock.date(2000, 3, 15)
        let next = Birthdays.nextOccurrence(of: bday, after: TestClock.now, calendar: cal)!
        XCTAssertEqual(TestClock.parts(next).y, 2027)
        let soon = TestClock.date(1990, 11, 5)
        XCTAssertEqual(Birthdays.daysUntil(soon, from: TestClock.now, calendar: cal), 3)
        XCTAssertEqual(Birthdays.daysUntil(TestClock.date(1990, 11, 2), from: TestClock.now, calendar: cal), 0)
    }

    func testLeapDay() {
        let leap = TestClock.date(2000, 2, 29)
        let next = Birthdays.nextOccurrence(of: leap, after: TestClock.now, calendar: cal)!
        XCTAssertEqual([TestClock.parts(next).m, TestClock.parts(next).d], [2, 28]) // 2027 is not a leap year
    }

    func testKeys() {
        XCTAssertTrue(Birthdays.isRecurringDateKey("Birthday"))
        XCTAssertTrue(Birthdays.isRecurringDateKey("wedding anniversary"))
        XCTAssertFalse(Birthdays.isRecurringDateKey("city"))
    }
}
