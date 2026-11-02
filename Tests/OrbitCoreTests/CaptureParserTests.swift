import XCTest
@testable import OrbitCore

final class CaptureParserTests: XCTestCase {
    let people = ["Sarah Connor", "Sam Okafor", "Sam Lee", "Tom Baker", "Mum"]
    let groups = ["Family", "Book Club"]
    let now = TestClock.now

    private var parser: CaptureParser {
        CaptureParser(people: people, groups: groups, actions: ["Run"], dates: TestClock.usDates)
    }

    private func draft(_ text: String) -> CaptureDraft? {
        if case .log(let d) = parser.parse(text, now: now) { return d }
        return nil
    }

    // MARK: Plain language

    func testHeadlineExample() {
        let d = draft("Coffee with Sarah yesterday, talked about her move")!
        XCTAssertEqual(d.people, ["Sarah"])
        XCTAssertEqual(d.action, "Coffee")
        XCTAssertEqual(d.date.map { TestClock.parts($0).d }, 1)
        XCTAssertEqual(d.note, "talked about her move")
    }

    func testFullNameAndAliasVerb() {
        let d = draft("texted Sarah Connor about the party")!
        XCTAssertEqual(d.people, ["Sarah Connor"])
        XCTAssertEqual(d.action, "Message")
        XCTAssertEqual(d.note, "about the party")
    }

    func testLowercaseNameAfterWith() {
        let d = draft("lunch with tom")!
        XCTAssertEqual(d.people, ["tom"])
        XCTAssertEqual(d.action, "Meal")
        XCTAssertEqual(d.note, "")
    }

    func testMultiplePeopleWithCommaList() {
        let d = draft("Dinner with Sam, Tom and Mum on friday")!
        XCTAssertEqual(d.people, ["Sam", "Tom", "Mum"])
        XCTAssertEqual(d.action, "Meal")
        XCTAssertEqual(d.date.map { TestClock.parts($0).d }, 30)
    }

    func testUnknownPersonIsKept() {
        let d = draft("Coffee with Jamie Lee, new neighbour")!
        XCTAssertEqual(d.people, ["Jamie Lee"])
        XCTAssertEqual(d.note, "new neighbour")
    }

    func testWeakVerbLosesToSpecificAction() {
        XCTAssertEqual(draft("met Tom for coffee")?.action, "Coffee")
        XCTAssertEqual(draft("met Tom")?.action, "Meeting")
    }

    func testUnknownActionBeforeWith() {
        let d = draft("Drinks with Tom")!
        XCTAssertEqual(d.action, "Drinks")
        XCTAssertEqual(d.people, ["Tom"])
    }

    func testKnownCustomAction() {
        XCTAssertEqual(draft("run with Sam Lee this morning")?.action, "Run")
    }

    func testGroup() {
        let d = draft("dinner with family last night")!
        XCTAssertEqual(d.group, "Family")
        XCTAssertTrue(d.people.isEmpty)
        XCTAssertEqual(d.date.map { TestClock.parts($0).h }, 20)
    }

    func testTagsInPlainLanguage() {
        let d = draft("Call with Mum #health about her surgery")!
        XCTAssertEqual(d.tags, ["health"])
        XCTAssertEqual(d.action, "Call")
        XCTAssertEqual(d.note, "about her surgery")
    }

    func testJustAName() {
        let d = draft("sarah")!
        XCTAssertEqual(d.people, ["sarah"])
        XCTAssertNil(d.action)
        XCTAssertEqual(d.note, "")
    }

    func testNothingIsLost() {
        let d = draft("Lunch with Tom at Nando's, he got the job")!
        XCTAssertEqual(d.note, "at Nando's, he got the job")
    }

    func testDateInNoteIsNotUsedAsWhen() {
        let d = draft("Coffee with Sarah, she's moving on 3 March")!
        XCTAssertNil(d.date)
        XCTAssertEqual(d.note, "she's moving on 3 March")
    }

    // MARK: Sigil syntax still works

    func testSigilLog() {
        let d = draft("@Sarah !Coffee #work \"Discussed merger\" ^yesterday")!
        XCTAssertEqual(d.people, ["Sarah"])
        XCTAssertEqual(d.action, "Coffee")
        XCTAssertEqual(d.tags, ["work"])
        XCTAssertEqual(d.note, "Discussed merger")
        XCTAssertEqual(d.date.map { TestClock.parts($0).d }, 1)
    }

    func testSigilNameThenPlainLanguage() {
        let d = draft("@Sarah coffee yesterday")!
        XCTAssertEqual(d.people, ["Sarah"])
        XCTAssertEqual(d.action, "Coffee")
        XCTAssertEqual(d.date.map { TestClock.parts($0).d }, 1)
    }

    func testSigilGroupLog() {
        let d = draft("*Family !Call #chat")!
        XCTAssertEqual(d.group, "Family")
        XCTAssertEqual(d.action, "Call")
    }

    func testSigilUndoAndInvalidTime() {
        XCTAssertEqual(parser.parse("!undo", now: now), .undo)
        if case .invalid(let reason) = parser.parse("@Sarah !Call ^banana", now: now) {
            XCTAssertTrue(reason.contains("^banana"))
        } else {
            XCTFail("unknown ^ must be an error")
        }
    }

    func testEmailInPlainLanguageIsNotSigil() {
        XCTAssertFalse(CommandParser.looksLikeSigilSyntax("emailed tom@example.com"))
        XCTAssertFalse(CommandParser.looksLikeSigilSyntax("Great chat with Sam!"))
        XCTAssertTrue(CommandParser.looksLikeSigilSyntax("@Sam !Call"))
    }
}
