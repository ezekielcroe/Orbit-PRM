import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Re-read with Apple Intelligence
// Optional second opinion for the palette. Uses Apple's on-device model
// (Foundation Models framework, iOS 26 / macOS 26) to read an entry into the
// same fields the rule-based parser fills. Nothing leaves the device.
//
// Builds with older SDKs (the code is compiled out) and runs on older OS
// versions (the reader reports itself unavailable).

enum CaptureReaders {
    /// The best reader for this device, if any.
    static func makeDefault() -> (any CaptureReader)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AppleIntelligenceReader()
        }
        #endif
        return nil
    }

    /// Pick up to `limit` people worth showing the model: anyone whose name
    /// or alias appears in the text first, then the most recently contacted.
    static func candidatePeople(for text: String, contacts: [Contact], limit: Int = 30) -> [String] {
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        func mentioned(_ c: Contact) -> Bool {
            let nameWords = c.name.lowercased().split(separator: " ").map(String.init)
            return nameWords.contains(where: words.contains)
                || c.aliasList.contains(where: { text.lowercased().contains($0) })
        }
        let first = contacts.filter(mentioned)
        let rest = contacts
            .filter { !mentioned($0) }
            .sorted { ($0.lastContactDate ?? .distantPast) > ($1.lastContactDate ?? .distantPast) }
        return Array((first + rest).prefix(limit)).map { c in
            var label = c.name
            let rel = c.relationshipValues
            if !rel.isEmpty { label += " (my \(rel.joined(separator: ", ")))" }
            return label
        }
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedCapture {
    @Guide(description: "Names of the people the user was in touch with. Empty if none.")
    var people: [String]

    @Guide(description: "A known group the user was in touch with as a whole, or empty.")
    var group: String

    @Guide(description: "What happened, one or two words, e.g. Message, Call, Coffee. Empty if this is only a fact.")
    var action: String

    @Guide(description: "When it happened as a short phrase like 'yesterday' or 'last Friday'. Empty if not stated.")
    var when: String

    @Guide(description: "What was discussed, in the user's words. Empty if nothing.")
    var note: String

    @Guide(description: "Lasting facts about people mentioned in the entry.")
    var facts: [GeneratedFact]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedFact {
    @Guide(description: "Who the fact is about.")
    var person: String

    @Guide(description: "Short lowercase key, e.g. birthday, city, company, role, likes, kids, allergies, relationship.")
    var key: String

    @Guide(description: "The value, e.g. '3 March', 'Berlin', 'jazz'.")
    var value: String

    @Guide(description: "True when the value adds to a list (likes, dislikes, allergies, kids, pets).")
    var addsToList: Bool
}

@available(iOS 26.0, macOS 26.0, *)
struct AppleIntelligenceReader: CaptureReader {

    var availability: ReaderAvailability {
        let model = SystemLanguageModel.default
        if case .available = model.availability { return .available }
        if case .unavailable(let reason) = model.availability {
            switch reason {
            case .deviceNotEligible:
                return .unavailable("This device doesn't support Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Turn on Apple Intelligence in Settings to use Re-read.")
            case .modelNotReady:
                return .unavailable("Apple Intelligence is still getting ready. Try again shortly.")
            @unknown default:
                return .unavailable("Apple Intelligence isn't available right now.")
            }
        }
        return .unavailable("Apple Intelligence isn't available right now.")
    }

    func read(_ text: String, context: ReaderContext) async throws -> ModelCapture {
        let session = LanguageModelSession(instructions: ModelCapture.instructions)
        let response = try await session.respond(
            to: ModelCapture.prompt(for: text, context: context),
            generating: GeneratedCapture.self
        )
        let g = response.content
        return ModelCapture(
            people: g.people.map(Self.stripRelationshipLabel),
            group: g.group.isEmpty ? nil : g.group,
            action: g.action.isEmpty ? nil : g.action,
            when: g.when.isEmpty ? nil : g.when,
            note: g.note,
            tags: [],
            facts: g.facts.map { ModelFact(person: Self.stripRelationshipLabel($0.person), key: $0.key, value: $0.value, addsToList: $0.addsToList) }
        )
    }

    /// The prompt labels people as "Sarah (my sister)"; drop the label if echoed back.
    private static func stripRelationshipLabel(_ name: String) -> String {
        guard let paren = name.firstIndex(of: "(") else { return name }
        return String(name[..<paren]).trimmingCharacters(in: .whitespaces)
    }
}

#endif
