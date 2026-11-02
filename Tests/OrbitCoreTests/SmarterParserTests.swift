import XCTest
// Works both as the SwiftPM test target (module OrbitCore) and as an Xcode
// unit-test target hosted by the app (module Orbit).
#if canImport(OrbitCore)
@testable import OrbitCore
#else
@testable import Orbit
#endif

@MainActor
final class SmarterParserTests: XCTestCase {
    let now = TestClock.now

    let people = [
        PersonRef(name: "Mama"),
        PersonRef(name: "Sarah Connor", relationships: ["sister"]),
        PersonRef(name: "Ben Yeo", relationships: ["brother"]),
        PersonRef(name: "Margaret Yeo", aliases: ["mum"]),
        PersonRef(name: "Tom Baker"),
        PersonRef(name: "Ava Lim", aliases: ["the twins"]),
        PersonRef(name: "Leo Lim", aliases: ["the twins"]),
    ]
    let groups = [GroupRef(name: "Three Siblings"), GroupRef(name: "Book Club", aliases: ["readers"])]

    private func parser(ignoring: Set<String> = []) -> CaptureParser {
        CaptureParser(personRefs: people, groupRefs: groups, actions: [], dates: TestClock.usDates, ignoring: ignoring)
    }

    private func draft(_ text: String, ignoring: Set<String> = []) -> CaptureDraft? {
        if case .log(let d) = parser(ignoring: ignoring).parse(text, now: now) { return d }
        return nil
    }

    // MARK: The reported example

    func testSiblingsGroupAndTopicNote() {
        let d = draft("Texted my siblings about Mama going overseas.")!
        XCTAssertEqual(d.group, "Three Siblings")
        XCTAssertTrue(d.people.isEmpty, "Mama is the topic, not a participant")
        XCTAssertEqual(d.action, "Message")
        XCTAssertEqual(d.note, "about Mama going overseas.")
    }

    // MARK: Topic words

    func testTopicMarkerKeepsPeopleBeforeIt() {
        let d = draft("Called Tom about Mama's birthday")!
        XCTAssertEqual(d.people, ["Tom"])   // resolved to Tom Baker by the store
        XCTAssertEqual(d.note, "about Mama's birthday")
    }

    func testTrailingDateAfterTopic() {
        let d = draft("Called Tom about the move yesterday")!
        XCTAssertEqual(d.date.map { TestClock.parts($0).d }, 1)
        XCTAssertEqual(d.note, "about the move")
    }

    // MARK: Relationships and aliases

    func testSingularRelationship() {
        XCTAssertEqual(draft("Coffee with my sister")?.people, ["Sarah Connor"])
    }

    func testPluralRelationshipWithoutGroup() {
        let p = CaptureParser(personRefs: people, groupRefs: [], actions: [], dates: TestClock.usDates)
        guard case .log(let d) = p.parse("Called my siblings", now: now) else { return XCTFail() }
        XCTAssertEqual(Set(d.people), ["Sarah Connor", "Ben Yeo"])
    }

    func testUnknownRelationshipIsLeftForTheResolver() {
        XCTAssertEqual(draft("Lunch with my boss")?.people, ["my boss"])
    }

    func testAliases() {
        XCTAssertEqual(draft("Called mum")?.people, ["Margaret Yeo"])
        XCTAssertEqual(Set(draft("Played with the twins")?.people ?? []), ["Ava Lim", "Leo Lim"])
        XCTAssertEqual(draft("Drinks with the readers")?.group, "Book Club")
    }

    // MARK: Corrections

    func testIgnoredNameStaysInNote() {
        let d = draft("Coffee with Tom and Mama", ignoring: ["mama"])!
        XCTAssertEqual(d.people, ["Tom"])
        XCTAssertTrue(d.note.contains("Mama"))
    }

    func testIgnoredGroupWord() {
        let d = draft("Texted my siblings", ignoring: ["three siblings"])!
        XCTAssertNil(d.group)
    }

    func testGroupKeywordNeedsDeterminer() {
        // "Book" on its own must not pull in Book Club.
        XCTAssertNil(draft("Book with Tom")?.group)
    }

    // MARK: Facts

    private func facts(_ text: String) -> [FactDraft]? {
        if case .facts(let f) = parser().parse(text, now: now) { return f }
        return nil
    }

    func testFactStatements() {
        XCTAssertEqual(facts("Sarah's birthday is 3 March"),
                       [FactDraft(person: "Sarah", key: "birthday", values: ["3 March"], mode: .set)])
        XCTAssertEqual(facts("Tom works at Google"),
                       [FactDraft(person: "Tom", key: "company", values: ["Google"], mode: .set)])
        XCTAssertEqual(facts("Tom is a designer")?.first?.key, "role")
        XCTAssertEqual(facts("remember that Sarah is allergic to peanuts")?.first,
                       FactDraft(person: "Sarah", key: "allergies", values: ["peanuts"], mode: .append))
        XCTAssertEqual(facts("Ava Lim's kids are Max and Zoe")?.first?.values, ["Max", "Zoe"])
        XCTAssertEqual(facts("Ben likes jazz and sushi")?.first?.values, ["jazz", "sushi"])
        XCTAssertEqual(facts("Priya moved to Austin")?.first, FactDraft(person: "Priya", key: "city", values: ["Austin"], mode: .set))
        XCTAssertEqual(facts("Tom is my cousin")?.first, FactDraft(person: "Tom", key: "relationship", values: ["cousin"], mode: .set))
        XCTAssertEqual(facts("my sister's birthday is 3 March")?.first?.person, "my sister")
        XCTAssertEqual(facts("Jo has a dog called Rex")?.first?.values, ["Rex (dog)"])
    }

    func testLogsAreNotMistakenForFacts() {
        XCTAssertNil(facts("Coffee with Sarah yesterday"))
        XCTAssertNil(facts("Texted my siblings about Mama going overseas."))
        XCTAssertNil(facts("Called Tom"))
    }

    func testSuggestedFactsFromNote() {
        let d = draft("Coffee with Tom, he's moving to Berlin and got a job at Spotify")!
        XCTAssertTrue(d.suggestedFacts.contains(FactDraft(person: "Tom", key: "city", values: ["Berlin"], mode: .set)))
        XCTAssertTrue(d.suggestedFacts.contains(where: { $0.key == "company" && $0.values == ["Spotify"] }))
    }
}

// MARK: - Re-read mapping

@MainActor
final class ModelCaptureTests: XCTestCase {
    let now = TestClock.now

    func testLogMapping() {
        let capture = ModelCapture(people: ["Sarah Connor", " sarah connor "], group: nil, action: "texted",
                                   when: "yesterday", note: "about Mama's trip", tags: ["#Family"], facts: [])
        guard case .log(let d) = capture.toIntent(knownActions: [], dates: TestClock.usDates, now: now) else { return XCTFail() }
        XCTAssertEqual(d.people, ["Sarah Connor"])
        XCTAssertEqual(d.action, "Message")
        XCTAssertEqual(d.date.map { TestClock.parts($0).d }, 1)
        XCTAssertEqual(d.tags, ["family"])
    }

    func testFactOnlyMapping() {
        let capture = ModelCapture(people: [], facts: [ModelFact(person: "Tom", key: "Likes", value: "jazz and blues", addsToList: true)])
        XCTAssertEqual(capture.toIntent(knownActions: [], dates: TestClock.usDates, now: now),
                       .facts([FactDraft(person: "Tom", key: "likes", values: ["jazz", "blues"], mode: .append)]))
    }

    func testNowMeansNoDate() {
        let capture = ModelCapture(people: ["Tom"], action: "Call", when: "today")
        guard case .log(let d) = capture.toIntent(knownActions: [], now: now) else { return XCTFail() }
        XCTAssertNil(d.date)
    }

    func testPromptListsCandidates() {
        let prompt = ModelCapture.prompt(for: "hi", context: ReaderContext(people: ["Sarah"], groups: ["Book Club"], actions: ["Call"], today: now))
        XCTAssertTrue(prompt.contains("Known people: Sarah"))
        XCTAssertTrue(prompt.contains("Entry: hi"))
    }

    func testFakeReaderRoundTrip() async throws {
        struct FakeReader: CaptureReader {
            var availability: ReaderAvailability { .available }
            func read(_ text: String, context: ReaderContext) async throws -> ModelCapture {
                ModelCapture(people: ["Sarah"], action: "Call")
            }
        }
        let capture = try await FakeReader().read("anything", context: ReaderContext(people: [], groups: [], actions: [], today: now))
        guard case .log(let d) = capture.toIntent(knownActions: []) else { return XCTFail() }
        XCTAssertEqual(d.people, ["Sarah"])
    }
}

@MainActor
final class RelationshipsTests: XCTestCase {
    func testCanonicalForms() {
        XCTAssertEqual(Relationships.canonicalForms(inValue: "older sister"), ["sister"])
        XCTAssertEqual(Relationships.canonicalForms(inValue: "Mum"), ["mother"])
        XCTAssertEqual(Relationships.canonicalForms(inValue: "best friend"), ["best friend"])
        XCTAssertEqual(Relationships.pluralMembers("siblings"), ["sister", "brother", "sibling"])
    }

    func testGroupKeywords() {
        XCTAssertEqual(GroupRef(name: "Three Siblings").keywords, ["siblings"])
        XCTAssertEqual(GroupRef(name: "The Book Club").keywords, ["book", "club"])
    }
}
