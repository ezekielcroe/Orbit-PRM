import Foundation

// MARK: - NameMatcher
// Resolves a typed name ("sam", "Connor", "Sarah Connor") against a list of
// known names. Pure Foundation so it can be unit-tested.
//
// Tiers, first non-empty tier wins:
//   1. exact (case/diacritic-insensitive)
//   2. full-name prefix        "sar"    → "Sarah Connor"
//   3. any-word prefix         "conn"   → "Sarah Connor"
//   4. substring               "onno"   → "Sarah Connor"
// A tier with one hit is a unique match; more than one is ambiguous and the
// caller should offer a picker instead of guessing.

struct NameCandidate: Equatable, Hashable {
    let id: UUID
    let name: String
}

enum NameMatch: Equatable {
    case unique(UUID)
    case ambiguous([UUID])
    case none
}

enum NameMatcher {

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func match(_ query: String, in candidates: [NameCandidate]) -> NameMatch {
        let q = normalize(query)
        guard !q.isEmpty else { return .none }
        let normalized = candidates.map { (candidate: $0, name: normalize($0.name)) }

        let tiers: [(String) -> Bool] = [
            { $0 == q },
            { $0.hasPrefix(q) },
            { $0.split(separator: " ").contains(where: { $0.hasPrefix(q) }) },
            { $0.contains(q) },
        ]

        for test in tiers {
            let hits = normalized.filter { test($0.name) }.map(\.candidate.id)
            if hits.count == 1 { return .unique(hits[0]) }
            if hits.count > 1 { return .ambiguous(hits) }
        }
        return .none
    }

    /// Rank candidates for autocomplete. Lower rank is better; non-matches are dropped.
    static func ranked(_ query: String, in candidates: [NameCandidate], limit: Int = 6) -> [NameCandidate] {
        let q = normalize(query)
        guard !q.isEmpty else { return Array(candidates.prefix(limit)) }
        func rank(_ name: String) -> Int? {
            if name == q { return 0 }
            if name.hasPrefix(q) { return 1 }
            if name.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 2 }
            if name.contains(q) { return 3 }
            return nil
        }
        return candidates
            .compactMap { c -> (NameCandidate, Int)? in rank(normalize(c.name)).map { (c, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }
}
