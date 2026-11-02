import Foundation

// MARK: - CaptureDraft
// What the user meant to log, before names are resolved to contacts.
// Produced by both the plain-language parser and the sigil parser, so the
// palette shows one preview no matter how the input was typed.

struct CaptureDraft: Equatable {
    /// Names as typed or matched ("Sarah", "Jamie Lee"). Resolved later.
    var people: [String] = []
    /// A group name, when the log is for a whole group.
    var group: String?
    /// Canonical action ("Coffee"). nil = not detected yet; the UI asks.
    var action: String?
    /// When it happened. nil = now.
    var date: Date?
    var note: String = ""
    var tags: [String] = []

    var hasTarget: Bool { !people.isEmpty || group != nil }
}

/// What a line of palette input asks for.
enum CaptureIntent: Equatable {
    case empty
    case log(CaptureDraft)
    /// A sigil command that isn't a log (facts, groups, archive…).
    case command(ParsedCommand)
    case openGroup(String)
    case undo
    case invalid(String)
}

// MARK: - CaptureParser
// Entry point for palette input. Sigil syntax goes to CommandParser; anything
// else is read as plain language.

struct CaptureParser {
    var people: [String] = []
    var groups: [String] = []
    var actions: [String] = []
    var dates = DatePhraseParser()

    init(people: [String] = [], groups: [String] = [], actions: [String] = [], dates: DatePhraseParser = DatePhraseParser()) {
        self.people = people
        self.groups = groups
        self.actions = actions
        self.dates = dates
    }

    func parse(_ text: String, now: Date = Date()) -> CaptureIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard CommandParser.looksLikeSigilSyntax(trimmed) else {
            return .log(naturalLanguage.parse(trimmed, now: now))
        }

        let command = CommandParser(knownNames: people, dates: dates).parse(trimmed, now: now)
        switch command {
        case .undo:
            return .undo
        case .invalid(let reason):
            return .invalid(reason)
        case let .logInteraction(names, impulse, tags, note, date):
            return .log(CaptureDraft(
                people: names,
                action: ActionVocabulary.canonical(impulse, known: actions),
                date: date,
                note: note ?? "",
                tags: tags.map { $0.lowercased() }
            ))
        case let .logConstellationInteraction(group, impulse, tags, note, date):
            return .log(CaptureDraft(
                group: group,
                action: ActionVocabulary.canonical(impulse, known: actions),
                date: date,
                note: note ?? "",
                tags: tags.map { $0.lowercased() }
            ))
        case let .searchContact(name, query):
            // "@Sarah coffee yesterday" — read the leftover as plain language,
            // but the person is already decided.
            var draft = query.isEmpty ? CaptureDraft() : naturalLanguage.parse(query, now: now, findPeople: false)
            draft.people = [name]
            return .log(draft)
        case .searchConstellation(let name):
            return .openGroup(name)
        default:
            return .command(command)
        }
    }

    private var naturalLanguage: NaturalLanguageParser {
        NaturalLanguageParser(people: people, groups: groups, actions: actions, dates: dates)
    }
}

// MARK: - NaturalLanguageParser
// "Coffee with Sarah yesterday, talked about her move"
//   → people ["Sarah"], action "Coffee", date yesterday, note "talked about her move"
//
// The first clause (up to a comma, semicolon, colon, dash or full stop) is the
// "header" where we look for who, what and when. Everything after it is the note.
// Leftover header words that aren't fillers are kept in the note too, so
// nothing the user typed is thrown away.

struct NaturalLanguageParser {
    var people: [String]
    var groups: [String]
    var actions: [String]
    var dates: DatePhraseParser

    private static let fillers: Set<String> = [
        "with", "and", "&", "had", "have", "a", "an", "the", "for", "i", "we", "just", "quick", "some",
        "to", "my", "our", "also", "then", "plus",
    ]

    private static let notNames: Set<String> = [
        "i", "we", "my", "our", "the", "a", "an", "he", "she", "they", "him", "her", "them", "his", "their",
        "everyone", "everybody", "friends", "family", "team", "work", "colleagues", "kids", "folks",
        "today", "yesterday", "tonight", "morning", "afternoon", "evening", "night", "week", "month", "year",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "about", "at", "in", "on", "for", "from", "to", "of", "over", "after", "before", "and", "with",
    ]

    func parse(_ text: String, now: Date = Date(), findPeople: Bool = true) -> CaptureDraft {
        var draft = CaptureDraft()
        var working = text

        // 1. Tags anywhere: #word
        draft.tags = Self.extract(pattern: "(?<!\\S)#([\\w-]+)", from: &working).map { $0.lowercased() }

        // 2. Legacy ^shorthand anywhere: ^3d, ^yesterday, ^"last monday"
        let shorthands = Self.extract(pattern: "(?<!\\S)\\^(?:\"([^\"]*)\"|(\\S+))", from: &working)
        for s in shorthands {
            if let d = dates.resolveShorthand(s, now: now) { draft.date = d; break }
        }

        // 3. Split header / body.
        let (header, body) = splitHeader(working)
        var head = header

        // 4. When
        if draft.date == nil, let match = dates.firstMatch(in: head, now: now) {
            draft.date = match.date
            head.replaceSubrange(match.range, with: " ")
        }

        // 5. Group ("dinner with Family")
        for group in groups.sorted(by: { $0.count > $1.count }) {
            if let r = Self.wholeWordRange(of: group, in: head) {
                draft.group = group
                head.replaceSubrange(r, with: " ")
                break
            }
        }

        // 6. Who
        if findPeople {
            draft.people = findNames(in: &head)
        }

        // 7. What
        if let found = ActionVocabulary.find(in: head, known: actions) {
            draft.action = found.action
            head.replaceSubrange(found.range, with: " ")
        } else if let leading = leadingActionBeforeWith(head) {
            // "Drinks with Tom" — an action we don't know yet.
            draft.action = ActionVocabulary.canonical(leading.word, known: actions)
            head.replaceSubrange(leading.range, with: " ")
        }

        var leftover = Self.cleanLeftover(head)

        // 8. Just a name ("sarah", "connor") — nothing else typed.
        if findPeople, draft.people.isEmpty, draft.group == nil, !leftover.isEmpty,
           leftover.split(separator: " ").count <= 3 {
            let candidates = people.map { NameCandidate(id: UUID(), name: $0) }
            if NameMatcher.match(leftover, in: candidates) != .none {
                draft.people = [leftover]
                leftover = ""
            }
        }

        // 9. Note = meaningful header leftovers + body
        let parts = [leftover, body.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        draft.note = parts.joined(separator: ", ")
        return draft
    }

    // MARK: Header split

    private func splitHeader(_ text: String) -> (String, String) {
        let separators = [", ", "; ", ": ", " - ", " — ", " – ", ". ", "\n"]
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            var earliest: Range<String.Index>?
            for sep in separators {
                if let r = text.range(of: sep, range: searchStart..<text.endIndex),
                   earliest == nil || r.lowerBound < earliest!.lowerBound {
                    earliest = r
                }
            }
            guard let sepRange = earliest else { break }
            let after = String(text[sepRange.upperBound...])
            // "with Sam, Alex and Jo" — a comma followed by a name continues the list.
            if text[sepRange].hasPrefix(","), startsWithPersonOrConjunction(after) {
                searchStart = sepRange.upperBound
                continue
            }
            return (String(text[..<sepRange.lowerBound]), after)
        }
        return (text, "")
    }

    private func startsWithPersonOrConjunction(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("and ") || lower.hasPrefix("& ") { return true }
        for name in people {
            let n = name.lowercased()
            if lower.hasPrefix(n) { return true }
            if let first = n.split(separator: " ").first, lower.hasPrefix(first + " ") || lower == first || lower.hasPrefix(first + ",") {
                return true
            }
        }
        // An unknown capitalised word followed by "and"/"," ("Jo and Alex") also continues a list.
        let words = trimmed.split(separator: " ")
        if let first = words.first, first.first?.isUppercase == true, words.count > 1,
           ["and", "&"].contains(words[1].lowercased()) || first.hasSuffix(",") {
            return true
        }
        return false
    }

    // MARK: Names

    private func findNames(in head: inout String) -> [String] {
        // (name, character offset) — offsets survive blanking because every
        // replacement keeps the same number of characters.
        var found: [(String, Int)] = []

        func blank(_ r: Range<String.Index>) {
            head.replaceSubrange(r, with: String(repeating: " ", count: head[r].count))
        }

        // a) Full known names, longest first.
        for name in people.sorted(by: { $0.count > $1.count }) {
            while let r = Self.wholeWordRange(of: name, in: head) {
                found.append((name, head.distance(from: head.startIndex, to: r.lowerBound)))
                blank(r)
            }
        }

        // b) Single words that are part of a known name ("Sam" → Sam Okafor),
        //    when capitalised or introduced by with/and/&/comma.
        // c) Unknown capitalised names introduced by with/and/&/comma ("with Jamie Lee").
        let nameWords: Set<String> = Set(people.flatMap { $0.lowercased().split(separator: " ").map(String.init) })
            .subtracting(Self.notNames)
        let words = Self.words(in: head)
        var toBlank: [Range<String.Index>] = []
        var i = 0
        while i < words.count {
            let (word, range) = words[i]
            let lower = word.lowercased()
            let previous = i > 0 ? words[i - 1].0.lowercased() : ""
            let introduced = ["with", "and", "&"].contains(previous)
                || (i > 0 && head[words[i - 1].1.upperBound..<range.lowerBound].contains(","))
            let capitalised = word.first?.isUppercase == true
            let offset = head.distance(from: head.startIndex, to: range.lowerBound)

            if nameWords.contains(lower) && (capitalised || introduced) {
                found.append((word, offset))
                toBlank.append(range)
                i += 1
                continue
            }
            if introduced && capitalised && !Self.notNames.contains(lower) && !Self.fillers.contains(lower) {
                var parts = [word]
                var last = range
                var j = i + 1
                while j < words.count, parts.count < 3,
                      words[j].0.first?.isUppercase == true,
                      !Self.notNames.contains(words[j].0.lowercased()),
                      head[words[j - 1].1.upperBound..<words[j].1.lowerBound].allSatisfy({ $0 == " " }) {
                    parts.append(words[j].0)
                    last = words[j].1
                    j += 1
                }
                found.append((parts.joined(separator: " "), offset))
                toBlank.append(range.lowerBound..<last.upperBound)
                i = j
                continue
            }
            i += 1
        }
        // Replace from the end so earlier ranges stay valid.
        for r in toBlank.sorted(by: { $0.lowerBound > $1.lowerBound }) { blank(r) }

        var seen = Set<String>()
        return found
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private func leadingActionBeforeWith(_ head: String) -> (word: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: "^\\s*(?:(?:i|we|just|had|have|a|an|some|went for|went to)\\s+)*([A-Za-z][\\w'-]{1,20}(?:\\s+[A-Za-z][\\w'-]{1,20})?)\\s+with\\b", options: [.caseInsensitive]) else { return nil }
        let ns = head as NSString
        guard let m = regex.firstMatch(in: head, range: NSRange(location: 0, length: ns.length)),
              let r = Range(m.range(at: 1), in: head) else { return nil }
        let word = String(head[r])
        if Self.fillers.contains(word.lowercased()) || Self.notNames.contains(word.lowercased()) { return nil }
        return (word, r)
    }

    // MARK: Utilities

    private static func words(in text: String) -> [(String, Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        var start: String.Index?
        var i = text.startIndex
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "-" || c == "’" }
        while i < text.endIndex {
            if isWordChar(text[i]) {
                if start == nil { start = i }
            } else if let s = start {
                result.append((String(text[s..<i]), s..<i))
                start = nil
            }
            i = text.index(after: i)
        }
        if let s = start { result.append((String(text[s..<text.endIndex]), s..<text.endIndex)) }
        return result
    }

    static func wholeWordRange(of phrase: String, in text: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\w])" + escaped + "(?![\\w])", options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Range(m.range, in: text)
    }

    /// Removes every match of `pattern` from `text`, returning the first non-nil capture of each.
    private static func extract(pattern: String, from text: inout String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var values: [String] = []
        for m in matches {
            for g in 1..<max(m.numberOfRanges, 2) where m.range(at: g).location != NSNotFound {
                values.append(ns.substring(with: m.range(at: g)))
                break
            }
        }
        text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return values
    }

    /// Strip fillers and stray punctuation from the ends of what's left of the header.
    private static func cleanLeftover(_ text: String) -> String {
        var words = text
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        func droppable(_ w: String) -> Bool {
            let l = w.lowercased()
            return fillers.contains(l) || ActionVocabulary.weakPhrases.contains(l)
        }
        while let first = words.first, droppable(first) { words.removeFirst() }
        while let last = words.last, droppable(last) || last.allSatisfy({ $0.isPunctuation }) { words.removeLast() }
        // Drop a dangling conjunction run between removed names: "and and".
        var cleaned: [String] = []
        for w in words {
            if ["and", "&"].contains(w.lowercased()), let prev = cleaned.last, ["and", "&"].contains(prev.lowercased()) { continue }
            cleaned.append(w)
        }
        return cleaned.joined(separator: " ")
    }
}
