import Foundation
import CoreSpotlight
import SwiftData

// MARK: - SpotlightIndexer
// Indexes Orbit contacts into CoreSpotlight so they appear in
// system-wide search (Spotlight on iOS/macOS).
//
// Design decisions:
// - Index contact name, orbit zone, tags, and key artifact values
// - Re-index on contact save/modify, de-index on archive/delete
// - Use contact UUID as the unique Spotlight identifier
// - Batch operations for initial indexing after import

@Observable
final class SpotlightIndexer {

    private let searchableIndex = CSSearchableIndex.default()
    static let domainIdentifier = "com.orbit.contacts"

    // MARK: - Index a Single Contact

    func index(contact: Contact) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .contact)

        attributeSet.displayName = contact.name
        attributeSet.contentDescription = buildDescription(for: contact)

        // Keywords from aggregated interaction tags and artifact values
        var keywords = contact.tagNames
        keywords.append(contact.orbitZoneName)
        keywords.append(contentsOf: contact.constellations.map(\.name))
        for artifact in contact.artifacts {
            keywords.append(artifact.key)
            if !artifact.isArray {
                keywords.append(artifact.value)
            }
        }
        attributeSet.keywords = keywords

        attributeSet.supportsNavigation = true

        let item = CSSearchableItem(
            uniqueIdentifier: contact.id.uuidString,
            domainIdentifier: SpotlightIndexer.domainIdentifier,
            attributeSet: attributeSet
        )

        item.expirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())

        searchableIndex.indexSearchableItems([item]) { error in
            if let error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remove a Contact from Index

    func deindex(contact: Contact) {
        searchableIndex.deleteSearchableItems(
            withIdentifiers: [contact.id.uuidString]
        ) { error in
            if let error {
                print("Spotlight de-indexing error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Batch Index All Contacts

    func reindexAll(from context: ModelContext) {
        searchableIndex.deleteSearchableItems(
            withDomainIdentifiers: [SpotlightIndexer.domainIdentifier]
        ) { [weak self] error in
            if let error {
                print("Spotlight clear error: \(error.localizedDescription)")
                return
            }

            let predicate = #Predicate<Contact> { !$0.isArchived }
            let descriptor = FetchDescriptor<Contact>(predicate: predicate)

            guard let contacts = try? context.fetch(descriptor) else { return }

            let items = contacts.map { contact -> CSSearchableItem in
                let attributeSet = CSSearchableItemAttributeSet(contentType: .contact)
                attributeSet.displayName = contact.name
                attributeSet.contentDescription = self?.buildDescription(for: contact)

                var keywords = contact.tagNames
                keywords.append(contact.orbitZoneName)
                keywords.append(contentsOf: contact.constellations.map(\.name))
                attributeSet.keywords = keywords

                let item = CSSearchableItem(
                    uniqueIdentifier: contact.id.uuidString,
                    domainIdentifier: SpotlightIndexer.domainIdentifier,
                    attributeSet: attributeSet
                )
                item.expirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())
                return item
            }

            self?.searchableIndex.indexSearchableItems(items) { error in
                if let error {
                    print("Spotlight batch indexing error: \(error.localizedDescription)")
                } else {
                    print("Spotlight: indexed \(items.count) contacts")
                }
            }
        }
    }

    // MARK: - Handle Spotlight Tap

    static func contactID(from userActivity: NSUserActivity) -> UUID? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }
        return UUID(uuidString: identifier)
    }

    // MARK: - Helpers

    private func buildDescription(for contact: Contact) -> String {
        var parts: [String] = []

        parts.append(contact.orbitZoneName)

        if let days = contact.daysSinceLastContact {
            parts.append("Last contact: \(days)d ago")
        }

        // Tags from interactions
        let tagDisplay = contact.aggregatedTags.prefix(3).map { "#\($0.name)" }.joined(separator: " ")
        if !tagDisplay.isEmpty {
            parts.append(tagDisplay)
        }

        // Constellations
        let constellationDisplay = contact.constellations.prefix(2).map { $0.name }.joined(separator: ", ")
        if !constellationDisplay.isEmpty {
            parts.append("★ \(constellationDisplay)")
        }

        // Key artifacts
        let keyArtifacts = contact.artifacts
            .filter { ["company", "city", "role", "spouse"].contains($0.searchableKey) }
            .prefix(2)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " · ")

        if !keyArtifacts.isEmpty {
            parts.append(keyArtifacts)
        }

        return parts.joined(separator: " · ")
    }
}
