import XCTest
@testable import OrbitCore

final class CommandParserTests: XCTestCase {
    let now = TestClock.now
    private func parse(_ s: String, names: [String] = []) -> ParsedCommand {
        CommandParser(knownNames: names, dates: TestClock.usDates).parse(s, now: now)
    }

    func testEmailValueIsNotSplitIntoContacts() {
        XCTAssertEqual(parse("@Tom > email: tom@gmail.com"),
                       .setArtifact(contactNames: ["Tom"], key: "email", value: "tom@gmail.com"))
    }

    func testPunctuationInValues() {
        XCTAssertEqual(parse("@Tom > likes + Rock & Roll!"),
                       .appendArtifact(contactNames: ["Tom"], key: "likes", value: "Rock & Roll!", forceConvert: false))
    }

    func testHyphenatedKey() {
        XCTAssertEqual(parse("@Tom > t-shirt size: M"),
                       .setArtifact(contactNames: ["Tom"], key: "t-shirt size", value: "M"))
        XCTAssertEqual(parse("@Tom > likes - Jazz"),
                       .removeArtifact(contactNames: ["Tom"], key: "likes", value: "Jazz"))
    }

    func testVoidDeletes() {
        XCTAssertEqual(parse("@Tom > likes: void"), .deleteArtifact(contactNames: ["Tom"], key: "likes"))
    }

    func testEmptyFactValueIsInvalid() {
        if case .invalid = parse("@Tom > city:") {} else { XCTFail("empty value must be invalid") }
    }

    func testUnquotedTextBecomesNote() {
        XCTAssertEqual(parse("@Sarah !Coffee talked about her move"),
                       .logInteraction(contactNames: ["Sarah"], impulse: "Coffee", tags: [], note: "talked about her move", date: nil))
    }

    func testKnownNameSplitsLeftoverText() {
        XCTAssertEqual(parse("@Sarah coffee tomorrow", names: ["Sarah Connor"]),
                       .searchContact(name: "Sarah", query: "coffee tomorrow"))
        // Full multi-word name is kept when it matches.
        XCTAssertEqual(parse("@Sarah Connor !Call", names: ["Sarah Connor"]),
                       .logInteraction(contactNames: ["Sarah Connor"], impulse: "Call", tags: [], note: nil, date: nil))
    }

    func testQuotedNamesAndGroups() {
        XCTAssertEqual(parse("@\"Sarah Connor\" *\"Book Club\""),
                       .addToConstellation(contactNames: ["Sarah Connor"], constellationName: "Book Club"))
        XCTAssertEqual(parse("@Sarah *-Family"),
                       .removeFromConstellation(contactNames: ["Sarah"], constellationName: "Family"))
    }

    func testArchiveRestore() {
        XCTAssertEqual(parse("@A @B !archive"), .archiveContact(contactNames: ["A", "B"]))
        XCTAssertEqual(parse("@A !restore"), .restoreContact(contactNames: ["A"]))
    }

    func testQuotedTimeModifier() {
        if case let .logInteraction(_, _, _, _, date) = parse("@A !Call ^\"last monday\"") {
            XCTAssertEqual(date.map { TestClock.parts($0).d }, 26)
        } else { XCTFail() }
    }
}
