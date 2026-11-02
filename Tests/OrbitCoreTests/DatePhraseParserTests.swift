import XCTest
@testable import OrbitCore

final class DatePhraseParserTests: XCTestCase {
    let p = TestClock.usDates
    let now = TestClock.now

    private func day(_ text: String, _ parser: DatePhraseParser? = nil) -> (y: Int, m: Int, d: Int, h: Int)? {
        (parser ?? p).firstMatch(in: text, now: now).map { TestClock.parts($0.date) }
    }

    func testRelativeDays() {
        XCTAssertEqual(day("yesterday")?.d, 1)
        XCTAssertEqual(day("coffee yesterday with sam")?.d, 1)
        XCTAssertEqual(day("3 days ago")?.d, 30)          // 30 Oct
        XCTAssertEqual(day("a week ago")?.m, 10)
        XCTAssertEqual(day("a couple of days ago")?.d, 31)
        XCTAssertEqual(day("two weeks ago")?.d, 19)
        XCTAssertEqual(day("today")?.d, 2)
    }

    func testPartsOfDay() {
        XCTAssertEqual(day("yesterday evening")?.h, 19)
        XCTAssertEqual(day("last night")?.d, 1)
        XCTAssertEqual(day("last night")?.h, 20)
        XCTAssertEqual(day("this morning")?.h, 9)
        // "this evening" typed at noon would be the future — clamp to now.
        XCTAssertEqual(day("this evening")?.h, 12)
    }

    func testWeekdays() {
        // now is Monday 2 Nov
        XCTAssertEqual(day("on friday")?.d, 30)
        XCTAssertEqual(day("last monday")?.d, 26)
        XCTAssertEqual(day("monday")?.d, 2)
        XCTAssertEqual(day("last sat")?.d, 31)
        XCTAssertNil(day("we sat down for lunch"), "bare 3-letter weekday must not match")
        XCTAssertNil(day("money talk"))
    }

    func testAbsoluteDates() {
        XCTAssertEqual(day("on 3 March").map { [$0.y, $0.m, $0.d] }, [2026, 3, 3])
        XCTAssertEqual(day("March 3rd").map { [$0.y, $0.m, $0.d] }, [2026, 3, 3])
        // December hasn't happened yet this year → last year.
        XCTAssertEqual(day("Dec 25").map { [$0.y, $0.m, $0.d] }, [2025, 12, 25])
        XCTAssertEqual(day("2025-06-01").map { [$0.y, $0.m, $0.d] }, [2025, 6, 1])
        XCTAssertNil(day("31 February"))
    }

    func testNumericDatesFollowLocale() {
        XCTAssertEqual(day("4/3", p).map { [$0.m, $0.d] }, [4, 3])
        XCTAssertEqual(day("4/3", TestClock.ukDates).map { [$0.m, $0.d] }, [3, 4])
        // Unambiguous when one side > 12
        XCTAssertEqual(day("15/3", p).map { [$0.m, $0.d] }, [3, 15])
    }

    func testTrailingTime() {
        let m = p.firstMatch(in: "yesterday at 3pm with Tom", now: now)
        XCTAssertEqual(m.map { TestClock.parts($0.date).h }, 15)
        XCTAssertEqual(m?.phrase, "yesterday at 3pm")
        XCTAssertEqual(day("on friday at 9:30am")?.h, 9)
    }

    func testRangeIsReported() {
        let text = "Coffee with Sam yesterday, great chat"
        let m = p.firstMatch(in: text, now: now)!
        XCTAssertEqual(String(text[m.range]), "yesterday")
    }

    func testShorthand() {
        XCTAssertEqual(p.resolveShorthand("2d", now: now).map { TestClock.parts($0).d }, 31)
        XCTAssertEqual(p.resolveShorthand("3h", now: now).map { TestClock.parts($0).h }, 9)
        XCTAssertEqual(p.resolveShorthand("yesterday", now: now).map { TestClock.parts($0).d }, 1)
        XCTAssertEqual(p.resolveShorthand("last-monday", now: now).map { TestClock.parts($0).d }, 26)
        XCTAssertEqual(p.resolveShorthand("lastweek", now: now).map { TestClock.parts($0).d }, 26)
        XCTAssertNil(p.resolveShorthand("banana", now: now))
        XCTAssertNil(p.resolveShorthand("", now: now))
    }

    func testCalendarDateForFacts() {
        let r = p.parseCalendarDate("3/15")
        XCTAssertEqual(r.map { TestClock.calendar.component(.month, from: $0.date) }, 3)
        XCTAssertEqual(r?.hasYear, false)
        let full = p.parseCalendarDate("14 July 1990")
        XCTAssertEqual(full.map { TestClock.calendar.component(.year, from: $0.date) }, 1990)
        XCTAssertNil(p.parseCalendarDate("loves jazz"))
    }
}
