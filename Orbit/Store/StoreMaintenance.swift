import Foundation
import SwiftData

// MARK: - One-time and launch-time maintenance

extension OrbitStore {

    private static let normalizedKey = "orbit.didNormalizeV2"

    /// One-time cleanup for data created before the V2 overhaul:
    ///  • merge action spellings ("Text"/"texted" → "Message", case fixes)
    ///  • lowercase, trim and de-duplicate interaction tags and the tag registry
    ///  • backfill search text and parsed date facts
    /// Safe to run more than once; guarded by a UserDefaults flag.
    func runV2MaintenanceIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.normalizedKey) else { return }

        let interactions = (try? context.fetch(FetchDescriptor<Interaction>())) ?? []
        var known: [String] = []
        for interaction in interactions {
            let canonical = ActionVocabulary.canonical(interaction.impulse, known: known)
            if !canonical.isEmpty, !known.contains(canonical) { known.append(canonical) }
            if canonical != interaction.impulse && !canonical.isEmpty { interaction.impulse = canonical }
            interaction.setTags(interaction.tagList)
        }

        // Tag registry: one lowercase entry per name.
        let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var seen = Set<String>()
        for tag in tags {
            let lower = tag.name.trimmingCharacters(in: .whitespaces).lowercased()
            if lower.isEmpty || !seen.insert(lower).inserted {
                context.delete(tag)
            } else if tag.name != lower {
                tag.name = lower
                tag.searchableName = lower
            }
        }

        for contact in activeContacts(includeArchived: true) {
            contact.refreshCachedFields()
            contact.refreshArtifactCache()
        }

        if save("V2 maintenance") {
            defaults.set(true, forKey: Self.normalizedKey)
        }
    }
}

// MARK: - Attention snapshot

extension Contact {
    var attentionInput: AttentionInput {
        AttentionInput(
            id: id,
            name: name,
            orbit: targetOrbit,
            lastContact: lastContactDate,
            interactionCount: cachedInteractionCount,
            momentum: cachedMomentum,
            observedCadenceDays: cachedCadenceDays,
            snoozedUntil: snoozedUntil,
            closenessConfirmed: closenessConfirmed,
            isArchived: isArchived
        )
    }

    /// Plain-language status for detail headers ("It's been 6 weeks…").
    var attentionReason: String? {
        AttentionEngine.evaluate(attentionInput, now: Date())?.reason
    }
}
