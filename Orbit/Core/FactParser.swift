import Foundation

// MARK: - FactDraft
// A fact the user wants to save, before the person is resolved.

struct FactDraft: Equatable, Hashable {
    enum Mode: Equatable, Hashable {
        /// Replace the value(s).
        case set
        /// Add to a list ("likes + jazz").
        case append
    }

    /// Person as typed or matched ("Sarah", "my sister"). Resolved later.
    var person: String
    var key: String
    var values: [String]
    var mode: Mode

    var summary: String {
        let joined = values.joined(separator: ", ")
        return mode == .append ? "\(key) + \(joined)" : "\(key): \(joined)"
    }
}

// MARK: - FactParser
// Recognises a small set of fact sentences:
//
//   Sarah's birthday is 3 March          → birthday: 3 March
//   Alex's kids are Ava and Leo          → kids: Ava, Leo
//   Tom works at Google                  → company: Google
//   Tom works as a designer / is a designer → role: designer
//   Priya lives in Austin / moved to Austin → city: Austin
//   Sam likes jazz / loves sushi         → likes + jazz
//   Sam hates olives                     → dislikes + olives
//   Sarah is allergic to peanuts         → allergies + peanuts
//   Jo has a dog called Rex              → pets + Rex (dog)
//   Sarah is my sister                   → relationship: sister
//   remember (that) …, note: …, fyi …    (optional lead-in)
//
// It also finds facts inside a log's note ("she's moving to Berlin") and
// returns them as suggestions the user can accept.

struct FactParser {
    var people: [PersonRef]

    init(people: [PersonRef]) {
        self.people = people
    }

    /// Keys whose values are lists.
    static let listKeys: Set<String> = ["likes", "dislikes", "kids", "children", "pets", "hobbies", "interests",
                                        "allergies", "languages", "siblings", "favourites", "favorites"]

    static let keyAliases: [String: String] = [
        "bday": "birthday", "b-day": "birthday", "birth day": "birthday", "dob": "birthday", "date of birth": "birthday",
        "children": "kids", "job": "role", "job title": "role", "title": "role", "employer": "company",
        "workplace": "company", "hometown": "hometown", "home town": "hometown", "email address": "email",
        "phone number": "phone", "number": "phone", "mobile": "phone", "favorite food": "favourite food",
        "favorite colour": "favourite colour", "favorite color": "favourite colour", "favourite color": "favourite colour",
    ]

    // MARK: Whole-sentence facts

    /// Returns facts when the whole input is a fact statement, otherwise nil.
    func parseStatement(_ text: String) -> [FactDraft]? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        body = Self.stripLeadIn(body)
        body = body.trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespaces))
        guard !body.isEmpty, let (person, rest) = splitSubject(body) else { return nil }
        guard let facts = parsePredicate(rest, person: person, allowGenericPossessive: true), !facts.isEmpty else { return nil }
        return facts
    }

    // MARK: Facts inside a note

    /// Facts mentioned about `person` inside a log note, as suggestions.
    func suggestions(inNote note: String, person: String) -> [FactDraft] {
        let pronoun = "(?:she|he|they)"
        // "…, he's moving to Berlin and got a job at Spotify": a clause joined
        // by "and" keeps the same subject.
        let subject = "(?:\\b(?:she|he|they)(?:'s|’s| is| are| has| have)?|\\band)"
        let possessive = "(?:her|his|their)"
        let stop = "([^.,;!?]+?)(?=$|[.,;!?]|\\s+(?:and|but|so|because|which|who)\\s)"
        let patterns: [(String, (String) -> FactDraft?)] = [
            ("\(subject)\\s+(?:moving|moved|relocating|relocated)\\s+to\\s+\(stop)", { v in
                FactDraft(person: person, key: "city", values: [v], mode: .set) }),
            ("\\b\(pronoun)\\s+(?:now\\s+)?lives?\\s+in\\s+\(stop)", { v in
                FactDraft(person: person, key: "city", values: [v], mode: .set) }),
            ("\(subject)\\s+(?:now\\s+)?(?:got a (?:new )?job|started|starting|joined|joining|works|working)\\s+(?:at|with|for)\\s+\(stop)", { v in
                FactDraft(person: person, key: "company", values: [v], mode: .set) }),
            ("\\b\(possessive)\\s+birthday\\s+is\\s+(?:on\\s+)?\(stop)", { v in
                FactDraft(person: person, key: "birthday", values: [v], mode: .set) }),
            ("\\b\(pronoun)\\s+(?:really\\s+)?(?:likes|loves|like|love|enjoys|enjoy)\\s+\(stop)", { v in
                FactDraft(person: person, key: "likes", values: Self.splitList(v), mode: .append) }),
            ("\\b\(pronoun)(?:'s|’s| is| are)\\s+allergic\\s+to\\s+\(stop)", { v in
                FactDraft(person: person, key: "allergies", values: Self.splitList(v), mode: .append) }),
            ("\\b\(possessive)\\s+(wife|husband|partner|girlfriend|boyfriend|son|daughter|dog|cat)(?:'s name)?\\s+is\\s+(?:called\\s+|named\\s+)?\(stop)", { _ in nil }),
        ]

        var results: [FactDraft] = []
        for (pattern, make) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = note as NSString
            for m in regex.matches(in: note, range: NSRange(location: 0, length: ns.length)) {
                let valueGroup = m.numberOfRanges - 1
                guard m.range(at: valueGroup).location != NSNotFound else { continue }
                let value = Self.cleanValue(ns.substring(with: m.range(at: valueGroup)))
                guard !value.isEmpty, value.split(separator: " ").count <= 6 else { continue }
                if m.numberOfRanges == 3, m.range(at: 1).location != NSNotFound {
                    // "her husband is Tom" → husband: Tom
                    let key = ns.substring(with: m.range(at: 1)).lowercased()
                    let fact = ["dog", "cat"].contains(key)
                        ? FactDraft(person: person, key: "pets", values: ["\(value) (\(key))"], mode: .append)
                        : FactDraft(person: person, key: key, values: [value], mode: .set)
                    results.append(fact)
                } else if let fact = make(value) {
                    results.append(fact)
                }
            }
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.key + "|" + $0.values.joined(separator: ",").lowercased()).inserted }
    }

    // MARK: Subject

    /// Split "Sarah's birthday is…" / "my sister likes…" into (person, rest).
    /// `rest` keeps its leading "'s" or space so predicates can tell them apart.
    private func splitSubject(_ text: String) -> (String, String)? {
        let lower = text.lowercased()

        // "my sister", "our neighbour"
        if let regex = try? NSRegularExpression(pattern: "^(my|our)\\s+([a-z-]+(?:\\s+friend)?)(?=['’]s\\b|\\s)", options: [.caseInsensitive]),
           let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
           let r = Range(m.range, in: text) {
            let term = (text as NSString).substring(with: m.range(at: 2)).lowercased()
            if Relationships.canonical(term) != nil {
                return (String(text[r]), String(text[r.upperBound...]))
            }
        }

        // Known names and aliases, longest first, at the very start.
        var phrases: [(phrase: String, name: String)] = []
        for p in people {
            phrases.append((p.name, p.name))
            for a in p.aliases { phrases.append((a, p.name)) }
            if let first = p.name.split(separator: " ").first, first.count >= 2 { phrases.append((String(first), String(first))) }
        }
        phrases.sort { $0.phrase.count > $1.phrase.count }
        for (phrase, name) in phrases {
            let p = phrase.lowercased()
            guard lower.hasPrefix(p) else { continue }
            let rest = String(text.dropFirst(phrase.count))
            if rest.hasPrefix("'s") || rest.hasPrefix("’s") || rest.hasPrefix(" ") {
                return (name == phrase ? String(text.prefix(phrase.count)) : name, rest)
            }
        }

        // Unknown capitalised name (one or two words): "Jamie Lee's birthday is…"
        if let regex = try? NSRegularExpression(pattern: "^([A-Z][\\p{L}-]+(?:\\s+[A-Z][\\p{L}-]+)?)(?=['’]s\\b|\\s)"),
           let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
           let r = Range(m.range(at: 1), in: text) {
            let name = String(text[r])
            let first = name.split(separator: " ").first.map { $0.lowercased() } ?? ""
            let notNames: Set<String> = ["i", "we", "he", "she", "they", "it", "this", "that", "my", "our", "remember", "note", "the"]
            if !notNames.contains(first) {
                return (name, String(text[r.upperBound...]))
            }
        }
        return nil
    }

    // MARK: Predicate

    private func parsePredicate(_ rest: String, person: String, allowGenericPossessive: Bool) -> [FactDraft]? {
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.caseInsensitive]) else { return nil }
            let ns = rest as NSString
            guard let m = regex.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
        func fact(_ key: String, _ value: String, _ mode: FactDraft.Mode = .set, list: Bool = false) -> [FactDraft]? {
            let cleaned = Self.cleanValue(value)
            guard !cleaned.isEmpty else { return nil }
            let values = list ? Self.splitList(cleaned) : [cleaned]
            return [FactDraft(person: person, key: key, values: values, mode: mode)]
        }

        if let g = match("\\s+(?:works|worked|is working)\\s+(?:at|for)\\s+(.+)") { return fact("company", g[0]) }
        if let g = match("\\s+(?:works|worked|is working)\\s+as\\s+(?:an?\\s+)?(.+)") { return fact("role", g[0]) }
        if let g = match("\\s+(?:lives|lived|is living|now lives)\\s+in\\s+(.+)") { return fact("city", g[0]) }
        if let g = match("(?:\\s+is|['’]s)?\\s+(?:moving|moved|relocating|relocated)\\s+to\\s+(.+)") { return fact("city", g[0]) }
        if let g = match("\\s+(?:studies|studied|is studying)\\s+at\\s+(.+)") { return fact("school", g[0]) }
        if let g = match("\\s+(?:is|was)\\s+born\\s+on\\s+(.+)") { return fact("birthday", g[0]) }
        if let g = match("\\s+(?:really\\s+)?(?:likes|loves|enjoys|adores|is into|is a fan of)\\s+(.+)") { return fact("likes", g[0], .append, list: true) }
        if let g = match("\\s+(?:dislikes|hates|can't stand|cannot stand|doesn't like|does not like)\\s+(.+)") { return fact("dislikes", g[0], .append, list: true) }
        if let g = match("(?:\\s+is|['’]s)\\s+allergic\\s+to\\s+(.+)") { return fact("allergies", g[0], .append, list: true) }
        if let g = match("(?:\\s+is|['’]s)\\s+married\\s+to\\s+(.+)") { return fact("spouse", g[0]) }
        if let g = match("\\s+has\\s+an?\\s+([a-z]+)\\s+(?:called|named)\\s+(.+)") {
            let animal = g[0].lowercased()
            return fact("pets", "\(Self.cleanValue(g[1])) (\(animal))", .append)
        }
        if let g = match("(?:\\s+is|['’]s)\\s+my\\s+([a-z-]+(?:\\s+friend)?)") {
            if let canonical = Relationships.canonical(g[0]) { return fact("relationship", canonical) }
        }
        if allowGenericPossessive, let g = match("['’]s\\s+([\\p{L}][\\p{L} -]{0,30}?)\\s+(is|are|was|were)\\s+(.+)") {
            var key = g[0].lowercased().trimmingCharacters(in: .whitespaces)
            guard key.split(separator: " ").count <= 3 else { return nil }
            key = Self.keyAliases[key] ?? key
            let plural = g[1].lowercased() == "are" || g[1].lowercased() == "were" || Self.listKeys.contains(key)
            if let canonical = Relationships.canonical(key), Relationships.pluralMembers(key) == nil {
                // "Sarah's husband is Tom" — still a fact about Sarah.
                return fact(canonical, g[2])
            }
            return fact(key, g[2], .set, list: plural)
        }
        if let g = match("\\s+is\\s+(?:an?|the)\\s+(.+)") { return fact("role", g[0]) }
        return nil
    }

    // MARK: Helpers

    static func stripLeadIn(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "^(?:remember|note|fyi|fact|reminder)\\s*(?:that\\s+|:\\s*|,\\s*|-\\s*|\\s+)", options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    static func cleanValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?\"'“”").union(.whitespacesAndNewlines))
    }

    static func splitList(_ value: String) -> [String] {
        value
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " & ", with: ",")
            .split(separator: ",")
            .map { cleanValue(String($0)) }
            .filter { !$0.isEmpty }
    }
}
