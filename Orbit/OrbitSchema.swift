import Foundation
import SwiftUI
import SwiftData

// MARK: - Models

// MARK: - AggregatedTag
// Represents a tag name and how many times it appears across a contact's interactions.
// Not a SwiftData model — a plain value type returned by computed properties.

struct AggregatedTag: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

// MARK: - Contact
@Model
final class Contact {
    // Identity
    var id: UUID = UUID()
    var name: String = ""
    var searchableName: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    // State
    var isArchived: Bool = false

    // Phase 3 Foundations
    var targetOrbit: Int = 2
    var gravityScore: Double = 5.0
    var cachedMomentum: Double = 0.0
    var cachedCadenceDays: Double = 0.0
    var lastContactDate: Date?

    /// Number of non-deleted interactions. Used by PeopleView filters
    /// ("Has Logs" / "No Logs") without faulting the relationship.
    var cachedInteractionCount: Int = 0

    /// Comma-separated top tag names (max 5) for display in list rows
    /// and for filter matching. Updated by refreshCachedFields().
    var cachedTagSummary: String = ""

    /// Whether this contact has any artifacts. Used by PeopleView
    /// "Has Artifacts" filter without faulting the relationship.
    var cachedHasArtifacts: Bool = false

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Interaction.contact)
    var interactions: [Interaction]?

    @Relationship(deleteRule: .cascade, inverse: \Artifact.contact)
    var artifacts: [Artifact]?

    // Tags are interaction-level only — no Contact ↔ Tag relationship.
    // Use aggregatedTags to see which tags appear across this contact's interactions.

    @Relationship(inverse: \Constellation.contacts)
    var constellations: [Constellation]?

    init(name: String, notes: String = "", targetOrbit: Int = 2) {
        self.id = UUID()
        self.name = name
        self.searchableName = name.lowercased()
        self.notes = notes
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isArchived = false
        self.targetOrbit = targetOrbit
        self.gravityScore = 5.0
        self.cachedMomentum = 0.0
        self.cachedCadenceDays = 0.0
        self.cachedInteractionCount = 0
        self.cachedTagSummary = ""
        self.cachedHasArtifacts = false
    }

    var orbitZoneName: String {
        switch targetOrbit {
        case 0: return "Inner Circle"
        case 1: return "Near Orbit"
        case 2: return "Mid Orbit"
        case 3: return "Outer Orbit"
        case 4: return "Deep Space"
        default: return "Unknown"
        }
    }

    var daysSinceLastContact: Int? {
        guard let last = lastContactDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    func updateSearchableName() {
        searchableName = name.lowercased()
    }

    // ┌─────────────────────────────────────────────────────────────┐
    // │ FIX P0-1.1: refreshCachedFields() replaces the old         │
    // │ refreshLastContactDate(). Updates ALL cached fields in one  │
    // │ pass through the interaction graph.                          │
    // │                                                             │
    // │ Call this whenever interactions change:                      │
    // │   - After logging an interaction                             │
    // │   - After deleting/undeleting an interaction                 │
    // │   - After editing interaction tags                           │
    // │   - During data integrity checks                             │
    // └─────────────────────────────────────────────────────────────┘

    func refreshCachedFields() {
        let active = (interactions ?? []).filter { !$0.isDeleted }

        // 1. Last contact date
        lastContactDate = active.map(\.date).max()

        // 2. Active interaction count (for "Has Logs" / "No Logs" filters)
        cachedInteractionCount = active.count

        // 3. Tag summary (for list display and tag filter matching)
        //    Compute aggregated tags in a single pass
        var tagCounts: [String: Int] = [:]
        for interaction in active {
            for tag in interaction.tagList {
                let key = tag.lowercased()
                tagCounts[key, default: 0] += 1
            }
        }
        let topTags = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
        cachedTagSummary = topTags.joined(separator: ",")

        // 4. Artifact presence
        cachedHasArtifacts = !(artifacts ?? []).isEmpty

        // 5. Timestamp
        modifiedAt = Date()
    }

    /// Convenience: refresh just the artifact cache flag.
    /// Call after adding/removing artifacts without touching interactions.
    func refreshArtifactCache() {
        cachedHasArtifacts = !(artifacts ?? []).isEmpty
        modifiedAt = Date()
    }

    // MARK: - Backward Compatibility
    // These keep existing call sites working during the transition.
    // TODO: Remove once all callers migrate to refreshCachedFields().

    func refreshLastContactDate() {
        refreshCachedFields()
    }

    // MARK: - Aggregated Interaction Tags
    // Tags live on interactions, not contacts. These computed properties
    // aggregate tag usage across all active interactions for display and filtering.
    //
    // ⚠️ PERFORMANCE NOTE: These traverse all interactions. Use them in detail views,
    //    NOT in list rows. For list rows, use cachedTagSummary instead.

    /// All tags from this contact's interactions, counted and sorted by frequency.
    /// Expensive — traverses all active interactions. Use in detail views only.
    var aggregatedTags: [AggregatedTag] {
        let allTagNames = activeInteractions.flatMap { $0.tagList }
        guard !allTagNames.isEmpty else { return [] }

        var counts: [String: Int] = [:]
        for tag in allTagNames {
            let key = tag.lowercased()
            counts[key, default: 0] += 1
        }

        return counts
            .map { AggregatedTag(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Tag names as a flat array (for Spotlight indexing, export, etc.)
    var tagNames: [String] {
        aggregatedTags.map(\.name)
    }

    /// Check if this contact has any interaction with the given tag.
    /// For list-level filtering, prefer checking cachedTagSummary.contains() instead.
    func hasInteractionTag(_ tagName: String) -> Bool {
        let search = tagName.lowercased()
        return aggregatedTags.contains { $0.name == search }
    }

    /// Fast tag check using the cached summary. O(1) string search
    /// instead of O(n) interaction traversal.
    func hasCachedTag(_ tagName: String) -> Bool {
        let search = tagName.lowercased()
        return cachedTagSummary.lowercased().split(separator: ",").contains { $0 == Substring(search) }
    }

    // MARK: - Drift Detection (single source of truth)

    /// Expected maximum days between interactions for this contact's orbit zone
    var cadenceThreshold: Int {
        switch targetOrbit {
        case 0: return 7      // Inner Circle: weekly
        case 1: return 30     // Near Orbit: monthly
        case 2: return 90     // Mid Orbit: quarterly
        case 3: return 365    // Outer Orbit: yearly
        case 4: return Int.max // Deep Space: no threshold
        default: return 90
        }
    }

    /// Whether this contact has exceeded the cadence threshold for their orbit zone
    var isDrifting: Bool {
        guard targetOrbit < 4 else { return false }
        guard let days = daysSinceLastContact else {
            return true // Never contacted and not Deep Space
        }
        return days > cadenceThreshold
    }

    /// How severely this contact is drifting (>1 means past threshold)
    var driftRatio: Double {
        guard let days = daysSinceLastContact else { return 2.0 }
        let threshold = Double(cadenceThreshold)
        guard threshold > 0 else { return 0 }
        return Double(days) / threshold
    }

    /// Priority score for sorting drifting contacts. Higher = more urgent.
    var driftPriority: Double {
        let threshold = Double(cadenceThreshold)
        let days = Double(daysSinceLastContact ?? 999)
        let orbitWeight = Double(5 - targetOrbit)
        return max(0, (days - threshold) / max(threshold, 1)) * orbitWeight
    }

    /// Colour representing drift severity
    var driftColor: Color {
        if driftRatio > 3.0 { return .red }
        if driftRatio > 1.5 { return .orange }
        if isDrifting { return .yellow }
        return .secondary
    }

    /// Active (non-deleted) interactions, sorted most recent first.
    /// ⚠️ PERFORMANCE: Filters and sorts on every access. Cache the result
    ///    in a local variable if you need to access it multiple times in one scope.
    var activeInteractions: [Interaction] {
            (interactions ?? [])
                .filter { !$0.isDeleted }
                .sorted { $0.date > $1.date }
    }

    /// Human-readable recency description
    var recencyDescription: String {
        guard let days = daysSinceLastContact else { return "No interactions" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        case 7...13: return "Last week"
        case 14...29: return "\(days / 7) weeks ago"
        case 30...59: return "Last month"
        case 60...364: return "\(days / 30) months ago"
        default: return "Over a year ago"
        }
    }
}

// MARK: - Interaction
@Model
final class Interaction {
    var id: UUID = UUID()
    var date: Date = Date()
    var impulse: String = ""
    var content: String = ""
    var isDeleted: Bool = false
    var contact: Contact?
    var tagNames: String = ""

    init(impulse: String, content: String = "", date: Date = Date()) {
        self.id = UUID()
        self.impulse = impulse
        self.content = content
        self.date = date
        self.isDeleted = false
    }

    var tagList: [String] {
        tagNames.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Artifact
@Model
final class Artifact {
    var id: UUID = UUID()
    var key: String = ""
    var searchableKey: String = ""
    var value: String = ""
    var isArray: Bool = false
    var category: String?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var contact: Contact?

    init(key: String, value: String, isArray: Bool = false, category: String? = nil) {
        self.id = UUID()
        self.key = key
        self.searchableKey = key.lowercased()
        self.value = value
        self.isArray = isArray
        self.category = category
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Decode array values. Caches would be nice here, but SwiftData models
    /// can't hold non-persistent stored properties easily. Keep call sites aware.
    var listValues: [String] {
        guard isArray else { return [value] }
        return (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? [value]
    }

    func appendValue(_ newValue: String) {
        var items = listValues
        if !isArray {
            items = value.isEmpty ? [] : [value]
            isArray = true
        }
        items.append(newValue)
        if let data = try? JSONEncoder().encode(items), let str = String(data: data, encoding: .utf8) {
            value = str
        }
        modifiedAt = Date()
    }

    func removeValue(_ target: String) {
        guard isArray else { return }
        var items = listValues
        items.removeAll { $0.lowercased() == target.lowercased() }
        if let data = try? JSONEncoder().encode(items), let str = String(data: data, encoding: .utf8) {
            value = str
        }
        modifiedAt = Date()
    }

    func setValue(_ newValue: String) {
        isArray = false
        value = newValue
        modifiedAt = Date()
    }

    var isDateType: Bool {
        let dateKeys = ["birthday", "anniversary", "born", "dob", "date"]
        return dateKeys.contains(where: { searchableKey.contains($0) })
    }

    var isLocationType: Bool {
        let locationKeys = ["address", "city", "location", "hometown", "country"]
        return locationKeys.contains(where: { searchableKey.contains($0) })
    }
}

// MARK: - Tag
// Tag is a name registry for autocomplete in the command palette.
// Tags are NOT linked to contacts. They exist so the palette can suggest
// previously-used tag names. Actual tag data lives on Interaction.tagNames.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var searchableName: String = ""
    var createdAt: Date = Date()

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.searchableName = name.lowercased()
        self.createdAt = Date()
    }
}

// MARK: - Constellation
@Model
final class Constellation {
    var id: UUID = UUID()
    var name: String = ""
    var searchableName: String = ""
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship
    var contacts: [Contact]?

    init(name: String, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.searchableName = name.lowercased()
        self.notes = notes
        self.createdAt = Date()
    }
}


// ┌─────────────────────────────────────────────────────────────────┐
// │ FIX P0-2.5: Versioned Schema & Migration Plan                   │
// │                                                                  │
// │ V1 is the original schema (pre-release). Since the app has not  │
// │ shipped yet (v1.0 in About), we add cached fields directly to   │
// │ V1. Once V1 ships, it must be LOCKED — never modified again.    │
// │                                                                  │
// │ Future changes go in V2 with a lightweight migration stage.     │
// │ The template below shows exactly how to do this.                │
// └─────────────────────────────────────────────────────────────────┘

// MARK: - Versioned Schema

enum OrbitSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Contact.self, Interaction.self, Artifact.self, Tag.self, Constellation.self]
    }
}

// MARK: - Migration Plan

enum OrbitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OrbitSchemaV1.self]
        // When V2 ships, add it here:
        // [OrbitSchemaV1.self, OrbitSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // When V2 ships, add migration here:
        // [migrateV1toV2]
        []
    }

    // ┌─────────────────────────────────────────────────────────────┐
    // │ TEMPLATE: How to add a migration when V2 is needed          │
    // │                                                              │
    // │ 1. Create OrbitSchemaV2 with the new models                  │
    // │ 2. Add it to the schemas array above                        │
    // │ 3. Uncomment and implement the migration stage below         │
    // │ 4. NEVER modify OrbitSchemaV1 after it ships                │
    // └─────────────────────────────────────────────────────────────┘
    //
    // static let migrateV1toV2 = MigrationStage.lightweight(
    //     fromVersion: OrbitSchemaV1.self,
    //     toVersion: OrbitSchemaV2.self
    // )
    //
    // For complex migrations that need data transformation:
    //
    // static let migrateV1toV2 = MigrationStage.custom(
    //     fromVersion: OrbitSchemaV1.self,
    //     toVersion: OrbitSchemaV2.self,
    //     willMigrate: { context in
    //         // Pre-migration: transform data in V1 format
    //     },
    //     didMigrate: { context in
    //         // Post-migration: populate new V2 fields
    //         // e.g., backfill cachedInteractionCount for all contacts
    //         let descriptor = FetchDescriptor<Contact>()
    //         if let contacts = try? context.fetch(descriptor) {
    //             for contact in contacts {
    //                 contact.refreshCachedFields()
    //             }
    //             try? context.save()
    //         }
    //     }
    // )
}
