import Foundation

// MARK: - ActionVocabulary
// One shared list of interaction types ("actions", stored as Interaction.impulse)
// used by every logging surface, plus normalisation so "text", "Texted" and
// "Message" end up as the same thing in the data.

enum ActionVocabulary {

    /// Shown when the user has little or no history yet.
    static let defaults = ["Message", "Call", "Coffee", "Meal", "Meeting", "Video Call", "Visit"]

    /// Words people type → canonical action. Keys are lowercase.
    static let aliases: [String: String] = [
        "call": "Call", "called": "Call", "phone": "Call", "phoned": "Call", "rang": "Call", "phone call": "Call",
        "message": "Message", "messaged": "Message", "text": "Message", "texted": "Message", "texting": "Message",
        "sms": "Message", "dm": "Message", "dmed": "Message", "dm'd": "Message", "whatsapp": "Message",
        "whatsapped": "Message", "chat": "Message", "chatted": "Message", "imessage": "Message",
        "coffee": "Coffee", "had coffee": "Coffee", "coffees": "Coffee", "tea": "Coffee",
        "meal": "Meal", "lunch": "Meal", "dinner": "Meal", "breakfast": "Meal", "brunch": "Meal",
        "supper": "Meal", "ate": "Meal",
        "meeting": "Meeting", "met": "Meeting", "meet": "Meeting",
        "video": "Video Call", "video call": "Video Call", "facetime": "Video Call", "facetimed": "Video Call",
        "zoom": "Video Call", "zoomed": "Video Call",
        "visit": "Visit", "visited": "Visit", "saw": "Visit", "hung out": "Visit", "hangout": "Visit",
        "email": "Email", "emailed": "Email",
    ]

    /// Generic verbs that only count when nothing more specific is present:
    /// "met Sarah for coffee" is Coffee, not Meeting.
    static let weakPhrases: Set<String> = ["met", "meet", "saw", "chat", "chatted", "ate", "hung out", "hangout"]

    /// Canonicalise a raw action string.
    /// 1. Alias table ("texted" → "Message").
    /// 2. Case-insensitive match against `known` keeps the user's existing spelling.
    /// 3. Otherwise trim and capitalise the first letter ("bouldering" → "Bouldering").
    static func canonical(_ raw: String, known: [String] = []) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let key = trimmed.lowercased()
        if let alias = aliases[key] { return alias }
        if let existing = known.first(where: { $0.lowercased() == key }) { return existing }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    /// Suggestions for pickers: the user's own actions by frequency, then any
    /// defaults they haven't used, capped at `limit`.
    static func suggestions(history: [String], limit: Int = 8) -> [String] {
        var counts: [String: (display: String, count: Int)] = [:]
        for raw in history {
            let action = canonical(raw)
            guard !action.isEmpty else { continue }
            let key = action.lowercased()
            counts[key] = (counts[key]?.display ?? action, (counts[key]?.count ?? 0) + 1)
        }
        let used = counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.display < $1.display }
            .map(\.display)
        var result = used
        for d in defaults where !result.contains(where: { $0.lowercased() == d.lowercased() }) {
            result.append(d)
        }
        return Array(result.prefix(limit))
    }

    /// Find an action phrase inside free text. Longer phrases win ("video call"
    /// over "call"). Returns the canonical action and the matched range.
    static func find(in text: String, known: [String] = []) -> (action: String, range: Range<String.Index>)? {
        var phrases: [(phrase: String, action: String)] = aliases.map { ($0.key, $0.value) }
        for k in known where aliases[k.lowercased()] == nil {
            phrases.append((k.lowercased(), k))
        }
        phrases.sort { $0.phrase.count > $1.phrase.count }

        var strong: (action: String, range: Range<String.Index>)?
        var weak: (action: String, range: Range<String.Index>)?
        let ns = text as NSString
        for (phrase, action) in phrases {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            guard let regex = try? NSRegularExpression(pattern: "(?<![\\w])" + escaped + "(?![\\w])", options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                  let r = Range(m.range, in: text) else { continue }
            let isWeak = weakPhrases.contains(phrase)
            let current = isWeak ? weak : strong
            // Earlier position wins; equal position keeps the longer phrase (sorted first).
            if current == nil || r.lowerBound < current!.range.lowerBound {
                if isWeak { weak = (action, r) } else { strong = (action, r) }
            }
        }
        return strong ?? weak
    }
}
