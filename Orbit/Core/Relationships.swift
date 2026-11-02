import Foundation

// MARK: - Relationships
// Kinship and role words ("my sister", "my siblings", "my boss"). A contact's
// relationship lives in an ordinary fact — key "relationship", e.g. "sister"
// or "older sister" — so it is visible and editable like any other fact.
// Plural words ("siblings", "parents") expand to every contact whose
// relationship is one of the singular forms.

enum Relationships {

    /// Spoken word → canonical relationship. Keys are lowercase.
    static let synonyms: [String: String] = [
        "mum": "mother", "mom": "mother", "mother": "mother", "mama": "mother", "mamma": "mother",
        "ma": "mother", "mommy": "mother", "mummy": "mother", "mam": "mother",
        "dad": "father", "father": "father", "papa": "father", "pa": "father", "daddy": "father", "pop": "father",
        "sister": "sister", "sis": "sister",
        "brother": "brother", "bro": "brother",
        "sibling": "sibling",
        "wife": "wife", "husband": "husband", "partner": "partner", "spouse": "partner",
        "girlfriend": "girlfriend", "boyfriend": "boyfriend", "fiance": "fiancé", "fiancé": "fiancé", "fiancee": "fiancé", "fiancée": "fiancé",
        "son": "son", "daughter": "daughter", "kid": "child", "child": "child",
        "grandma": "grandmother", "granny": "grandmother", "nana": "grandmother", "grandmother": "grandmother", "gran": "grandmother",
        "grandpa": "grandfather", "granddad": "grandfather", "grandad": "grandfather", "grandfather": "grandfather",
        "aunt": "aunt", "auntie": "aunt", "aunty": "aunt",
        "uncle": "uncle", "cousin": "cousin", "niece": "niece", "nephew": "nephew",
        "stepmother": "stepmother", "stepmom": "stepmother", "stepmum": "stepmother",
        "stepfather": "stepfather", "stepdad": "stepfather",
        "mother-in-law": "mother-in-law", "father-in-law": "father-in-law",
        "boss": "boss", "manager": "boss", "colleague": "colleague", "coworker": "colleague", "co-worker": "colleague",
        "cofounder": "cofounder", "co-founder": "cofounder", "mentor": "mentor", "mentee": "mentee",
        "roommate": "roommate", "flatmate": "roommate", "housemate": "roommate",
        "neighbour": "neighbour", "neighbor": "neighbour",
        "best friend": "best friend", "bestie": "best friend", "bff": "best friend",
        "godmother": "godmother", "godfather": "godfather", "godson": "godson", "goddaughter": "goddaughter",
    ]

    /// Plural word → the singular relationships it covers.
    static let plurals: [String: Set<String>] = [
        "siblings": ["sister", "brother", "sibling"],
        "sisters": ["sister"],
        "brothers": ["brother"],
        "parents": ["mother", "father", "stepmother", "stepfather"],
        "folks": ["mother", "father"],
        "kids": ["son", "daughter", "child"],
        "children": ["son", "daughter", "child"],
        "sons": ["son"],
        "daughters": ["daughter"],
        "grandparents": ["grandmother", "grandfather"],
        "cousins": ["cousin"],
        "aunts": ["aunt"],
        "uncles": ["uncle"],
        "in-laws": ["mother-in-law", "father-in-law"],
        "colleagues": ["colleague"],
        "coworkers": ["colleague"],
        "cofounders": ["cofounder"],
        "roommates": ["roommate"],
        "flatmates": ["roommate"],
        "neighbours": ["neighbour"],
        "neighbors": ["neighbour"],
    ]

    /// Fact keys that hold a relationship.
    static func isRelationshipKey(_ key: String) -> Bool {
        let k = key.lowercased()
        return k == "relationship" || k == "relation" || k == "relationships" || k == "relationship to me"
    }

    static func canonical(_ word: String) -> String? {
        synonyms[word.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    static func pluralMembers(_ word: String) -> Set<String>? {
        plurals[word.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Canonical relationships found in a fact value such as "older sister"
    /// or "Mum". Each word (and two-word phrase) is checked.
    static func canonicalForms(inValue value: String) -> Set<String> {
        let lower = value.lowercased()
        var result = Set<String>()
        if let whole = canonical(lower) { result.insert(whole) }
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
        for (i, w) in words.enumerated() {
            if let c = canonical(w) { result.insert(c) }
            if i + 1 < words.count, let c = canonical(w + " " + words[i + 1]) { result.insert(c) }
        }
        return result
    }

    /// All kin words, longest first, for building patterns.
    static var allWords: [String] {
        (Array(synonyms.keys) + Array(plurals.keys)).sorted { $0.count > $1.count }
    }
}

// MARK: - Vocabulary references
// What the parser knows about the user's people and groups. Value types so
// the parser stays free of SwiftData.

struct PersonRef: Equatable {
    var name: String
    /// Learned phrases that mean this person ("mama", "the boss").
    var aliases: [String] = []
    /// Canonical relationships from the "relationship" fact ("sister").
    var relationships: Set<String> = []
}

struct GroupRef: Equatable {
    var name: String
    var aliases: [String] = []

    /// Words that identify the group on their own: "Three Siblings" → ["siblings"].
    var keywords: [String] {
        let skip: Set<String> = ["the", "my", "our", "a", "an", "of", "and", "&", "with", "for",
                                 "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                 "group", "chat"]
        return name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" })
            .map(String.init)
            .filter { !skip.contains($0) && Int($0) == nil && $0.count >= 3 }
    }
}
