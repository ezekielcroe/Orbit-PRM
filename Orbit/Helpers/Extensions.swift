import Foundation
import SwiftData

// MARK: - Date Extensions

extension Date {
    /// Relative description: "Today", "Yesterday", "3 days ago", etc.
    var relativeDescription: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: self, to: Date()).day ?? 0

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

    /// Short format for compact displays
    var shortRelative: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: self, to: Date()).day ?? 0

        switch days {
        case 0: return "today"
        case 1: return "1d"
        case 2...30: return "\(days)d"
        case 31...365: return "\(days / 30)mo"
        default: return "\(days / 365)y"
        }
    }
}

// MARK: - String Extensions

extension String {
    /// Truncate to a maximum length with ellipsis
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength - 1)) + "…"
    }
}

// MARK: - Export Helpers (Phase 2)
// Full data export with all relationships and metadata.
// JSON preserves everything; CSV provides a flat summary.

struct OrbitExporter {

    /// Export all contacts as comprehensive JSON
    static func exportJSON(from context: ModelContext) -> Data? {
        let descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\Contact.name)])
        guard let contacts = try? context.fetch(descriptor) else { return nil }

        var exportData: [[String: Any]] = []

        for contact in contacts {
            var entry: [String: Any] = [
                "name": contact.name,
                "notes": contact.notes,
                "targetOrbit": contact.targetOrbit,
                "targetOrbitName": contact.orbitZoneName,
                "isArchived": contact.isArchived,
                "gravityScore": contact.gravityScore,
                "createdAt": ISO8601DateFormatter().string(from: contact.createdAt),
                "modifiedAt": ISO8601DateFormatter().string(from: contact.modifiedAt),
            ]

            if let lastContact = contact.lastContactDate {
                entry["lastContactDate"] = ISO8601DateFormatter().string(from: lastContact)
                entry["daysSinceLastContact"] = contact.daysSinceLastContact
            }

            // Artifacts as structured key-value pairs
            var artifacts: [[String: Any]] = []
            for artifact in contact.artifacts {
                var artifactEntry: [String: Any] = [
                    "key": artifact.key,
                    "isArray": artifact.isArray,
                ]
                if artifact.isArray {
                    artifactEntry["values"] = artifact.listValues
                } else {
                    artifactEntry["value"] = artifact.value
                }
                artifacts.append(artifactEntry)
            }
            entry["artifacts"] = artifacts

            // Tags
            entry["tags"] = contact.tagNames

            // Constellations
            entry["constellations"] = contact.constellations.map(\.name)

            // Interactions (only non-deleted)
            let interactions = contact.interactions
                .filter { !$0.isDeleted }
                .sorted { $0.date > $1.date }
                .map { interaction -> [String: Any] in
                    var interactionEntry: [String: Any] = [
                        "date": ISO8601DateFormatter().string(from: interaction.date),
                        "impulse": interaction.impulse,
                    ]
                    if !interaction.content.isEmpty {
                        interactionEntry["content"] = interaction.content
                    }
                    if !interaction.tagNames.isEmpty {
                        interactionEntry["tags"] = interaction.tagList
                    }
                    return interactionEntry
                }
            entry["interactions"] = interactions
            entry["interactionCount"] = interactions.count

            exportData.append(entry)
        }

        // Wrap in a root object with metadata
        let exportRoot: [String: Any] = [
            "exportVersion": "2.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "contactCount": exportData.count,
            "contacts": exportData,
        ]

        return try? JSONSerialization.data(withJSONObject: exportRoot, options: [.prettyPrinted, .sortedKeys])
    }

    /// Export contacts as CSV with more columns than Phase 1
    static func exportCSV(from context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\Contact.name)])
        guard let contacts = try? context.fetch(descriptor) else { return "" }

        var csv = "Name,Orbit Zone,Target Orbit,Last Contact,Days Since Contact,Interaction Count,Tags,Constellations,Archived,Notes\n"

        for contact in contacts {
            let name = csvEscape(contact.name)
            let orbit = contact.orbitZoneName
            let targetOrbit = String(contact.targetOrbit)
            let lastContact = contact.lastContactDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
            let daysSince = contact.daysSinceLastContact.map(String.init) ?? "N/A"
            let interactionCount = String(contact.interactions.filter({ !$0.isDeleted }).count)
            let tags = csvEscape(contact.tagNames.joined(separator: "; "))
            let constellations = csvEscape(contact.constellations.map(\.name).joined(separator: "; "))
            let archived = contact.isArchived ? "Yes" : "No"
            let notes = csvEscape(contact.notes)

            csv += "\(name),\(orbit),\(targetOrbit),\(lastContact),\(daysSince),\(interactionCount),\(tags),\(constellations),\(archived),\(notes)\n"
        }

        return csv
    }

    /// Escape a field for CSV (wrap in quotes if it contains commas, quotes, or newlines)
    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
