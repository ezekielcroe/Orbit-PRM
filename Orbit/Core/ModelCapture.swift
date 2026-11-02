import Foundation

// MARK: - Re-read contract
// "Re-read" asks a language model (Apple Intelligence on supported devices)
// to fill in the same fields the rule-based parser produces. The model sits
// behind `CaptureReader` so the app can swap in a fake in tests and so this
// file stays free of any framework that only exists on newer OS versions.
//
// The model's answer is never trusted on its own: `toIntent` turns it into an
// ordinary CaptureIntent, and the palette then resolves every name against the
// real contacts and groups and shows the preview before anything is saved.

/// What the model returned. Plain strings; dates are phrases ("yesterday",
/// "2026-10-30") and go through DatePhraseParser like typed text does.
struct ModelCapture: Equatable {
    var people: [String] = []
    var group: String?
    var action: String?
    var when: String?
    var note: String = ""
    var tags: [String] = []
    var facts: [ModelFact] = []
}

struct ModelFact: Equatable {
    var person: String
    var key: String
    var value: String
    var addsToList: Bool
}

/// The candidates the model may choose from. Kept short — on-device models
/// have small context windows — and checked again after the answer comes back.
struct ReaderContext: Equatable {
    var people: [String]
    var groups: [String]
    var actions: [String]
    var today: Date
}

enum ReaderAvailability: Equatable {
    case available
    case unavailable(String)
}

protocol CaptureReader {
    var availability: ReaderAvailability { get }
    func read(_ text: String, context: ReaderContext) async throws -> ModelCapture
}

extension ModelCapture {

    /// Convert the model's answer into the same intent the parser produces.
    /// A statement with only facts (no one to log with) becomes `.facts`.
    func toIntent(knownActions: [String], dates: DatePhraseParser = DatePhraseParser(), now: Date = Date()) -> CaptureIntent {
        let cleanPeople = Self.unique(people.map(Self.clean).filter { !$0.isEmpty })
        let cleanGroup = group.map(Self.clean).flatMap { $0.isEmpty ? nil : $0 }
        let factDrafts = facts.compactMap { f -> FactDraft? in
            let person = Self.clean(f.person)
            let key = Self.clean(f.key).lowercased()
            let value = Self.clean(f.value)
            guard !person.isEmpty, !key.isEmpty, !value.isEmpty else { return nil }
            let list = f.addsToList || FactParser.listKeys.contains(key)
            return FactDraft(person: person, key: FactParser.keyAliases[key] ?? key,
                             values: list ? FactParser.splitList(value) : [value],
                             mode: f.addsToList ? .append : .set)
        }

        let rawAction = action.map(Self.clean) ?? ""
        if cleanPeople.isEmpty && cleanGroup == nil && rawAction.isEmpty && !factDrafts.isEmpty {
            return .facts(factDrafts)
        }

        var draft = CaptureDraft()
        draft.people = cleanPeople
        draft.group = cleanGroup
        draft.action = rawAction.isEmpty ? nil : ActionVocabulary.canonical(rawAction, known: knownActions)
        if let phrase = when.map(Self.clean), !phrase.isEmpty, !["now", "today", "just now"].contains(phrase.lowercased()) {
            draft.date = dates.firstMatch(in: phrase, now: now)?.date ?? dates.resolveShorthand(phrase, now: now)
        }
        draft.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.tags = Self.unique(tags.map { Self.clean($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }.filter { !$0.isEmpty })
        draft.suggestedFacts = factDrafts
        return .log(draft)
    }

    /// The prompt sent with the user's text.
    static func prompt(for text: String, context: ReaderContext) -> String {
        let day = context.today.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        var lines = ["Today is \(day).", ""]
        if !context.people.isEmpty { lines.append("Known people: " + context.people.joined(separator: "; ")) }
        if !context.groups.isEmpty { lines.append("Known groups: " + context.groups.joined(separator: "; ")) }
        if !context.actions.isEmpty { lines.append("Usual actions: " + context.actions.joined(separator: ", ")) }
        lines.append("")
        lines.append("Entry: \(text)")
        return lines.joined(separator: "\n")
    }

    static let instructions = """
    You read short entries from a personal relationship journal and extract structured fields.
    - people: the people the user was in touch with. Use the exact spelling from "Known people" when one clearly matches; otherwise copy the name as written. Do not list people who are only mentioned as a topic (in "talked about Mama's trip", Mama is a topic, not a participant).
    - group: a known group name only if the user was in touch with that whole group.
    - action: one or two words for what happened, e.g. Message, Call, Coffee, Meal, Meeting, Video Call, Visit. Prefer the usual actions.
    - when: a short date phrase such as "yesterday", "last Friday", "3 days ago" or an ISO date. Leave empty if not stated.
    - note: what was discussed, in the user's own words. Keep it short; do not invent details.
    - facts: lasting details about a person (birthday, city, company, role, likes, kids, allergies, relationship). Set addsToList for likes, dislikes, allergies, kids and pets.
    If the entry only states facts and no contact happened, leave people, group and action empty.
    """

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.").union(.whitespacesAndNewlines))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
