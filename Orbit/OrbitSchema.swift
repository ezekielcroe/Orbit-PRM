// This file provides the OrbitSchemaV1 schema for the Orbit app's SwiftData store.
// If a more complete model definition exists, this should be replaced, but this will resolve the immediate error.

// This file provides the OrbitSchemaV1 schema for the Orbit app's SwiftData store.

import Foundation
import SwiftData

// MARK: - Models
// Defined at the top level so they're accessible throughout the module.
// CloudKit sync requires: no .unique attributes, no .deny delete rules,
// all properties must be optional or have default values.

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

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Interaction.contact)
    var interactions: [Interaction] = []

    @Relationship(deleteRule: .cascade, inverse: \Artifact.contact)
    var artifacts: [Artifact] = []

    @Relationship(inverse: \Tag.contacts)
    var tags: [Tag] = []

    @Relationship(inverse: \Constellation.contacts)
    var constellations: [Constellation] = []

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

    func refreshLastContactDate() {
        lastContactDate = interactions
            .filter { !$0.isDeleted }
            .map(\.date)
            .max()
        modifiedAt = Date()
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
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var contact: Contact?

    init(key: String, value: String, isArray: Bool = false) {
        self.id = UUID()
        self.key = key
        self.searchableKey = key.lowercased()
        self.value = value
        self.isArray = isArray
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

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
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var searchableName: String = ""
    var createdAt: Date = Date()

    @Relationship
    var contacts: [Contact] = []

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
    var contacts: [Contact] = []

    init(name: String, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.searchableName = name.lowercased()
        self.notes = notes
        self.createdAt = Date()
    }
}

// MARK: - Versioned Schema
// References the top-level models. When you need to migrate,
// create OrbitSchemaV2, copy the models with changes, and add
// migration stages to the plan.

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
    }

    static var stages: [MigrationStage] {
        []
    }
}
