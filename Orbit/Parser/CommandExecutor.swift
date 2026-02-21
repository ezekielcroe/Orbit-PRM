import Foundation
import SwiftData

// MARK: - CommandExecutor
// Takes a ParsedCommand and executes it against the SwiftData ModelContext.
// This is the bridge between the text parser and the data layer.
// It returns a CommandResult so the UI can show confirmation or errors.

struct CommandResult {
    let success: Bool
    let message: String
    let affectedContact: Contact?
    var requiresConversionPrompt: ParsedCommand? = nil
}

@Observable
final class CommandExecutor {

    // Tracks the most recent interaction for undo support
    private(set) var lastCreatedInteraction: Interaction?
    private(set) var lastResult: CommandResult?

    // MARK: - Execute

    func execute(_ command: ParsedCommand, in context: ModelContext) -> CommandResult {
        let result: CommandResult

        switch command {
        case .logInteraction(let name, let impulse, let tags, let note, let timeMod):
            result = executeLogInteraction(
                contactName: name,
                impulse: impulse,
                tags: tags,
                note: note,
                timeModifier: timeMod,
                in: context
            )

        case .setArtifact(let name, let key, let value):
            result = executeSetArtifact(contactName: name, key: key, value: value, in: context)

        case .appendArtifact(let name, let key, let value, let forceConvert):
            result = executeAppendArtifact(contactName: name, key: key, value: value, forceConvert: forceConvert, in: context)

        case .removeArtifact(let name, let key, let value):
            result = executeRemoveArtifact(contactName: name, key: key, value: value, in: context)

        case .deleteArtifact(let name, let key):
            result = executeDeleteArtifact(contactName: name, key: key, in: context)

        case .archiveContact(let name):
            result = executeArchive(contactName: name, archive: true, in: context)

        case .restoreContact(let name):
            result = executeArchive(contactName: name, archive: false, in: context)

        case .addToConstellation(let name, let constellationName):
            result = executeAddToConstellation(contactName: name, constellationName: constellationName, in: context)

        case .removeFromConstellation(let name, let constellationName):
            result = executeRemoveFromConstellation(contactName: name, constellationName: constellationName, in: context)

        case .logConstellationInteraction(let constellationName, let impulse, let tags, let note, let timeMod):
            result = executeLogConstellationInteraction(
                constellationName: constellationName,
                impulse: impulse,
                tags: tags,
                note: note,
                timeModifier: timeMod,
                in: context
            )

        case .searchContact:
            // Search is handled by the UI layer, not the executor
            result = CommandResult(success: true, message: "Navigating to search", affectedContact: nil)

        case .undo:
            result = executeUndo(in: context)

        case .invalid(let reason):
            result = CommandResult(success: false, message: reason, affectedContact: nil)
        }

        lastResult = result
        return result
    }

    // MARK: - Interaction Logging

    private func executeLogInteraction(
        contactName: String,
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(
                success: false,
                message: "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }

        let date = CommandParser.resolveTimeModifier(timeModifier)

        let interaction = Interaction(
            impulse: impulse,
            content: note ?? "",
            date: date
        )
        interaction.tagNames = tags.joined(separator: ", ")
        interaction.contact = contact

        context.insert(interaction)
        contact.refreshLastContactDate()

        // Ensure tag names exist in the tag registry (for autocomplete).
        // Tags are NOT linked to contacts — they live on interactions only.
        for tagName in tags {
            ensureTagExists(named: tagName, in: context)
        }

        lastCreatedInteraction = interaction

        let dateStr = timeModifier != nil ? " on \(date.formatted(date: .abbreviated, time: .omitted))" : ""
        return CommandResult(
            success: true,
            message: "Logged \(impulse) with \(contact.name)\(dateStr)",
            affectedContact: contact
        )
    }

    // MARK: - Artifact Operations

    private func executeSetArtifact(
        contactName: String,
        key: String,
        value: String,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        // Find existing artifact with this key, or create new
        if let existing = contact.artifacts.first(where: { $0.searchableKey == key.lowercased() }) {
            existing.setValue(value)
        } else {
            let artifact = Artifact(key: key, value: value)
            artifact.contact = contact
            context.insert(artifact)
        }

        contact.modifiedAt = Date()

        return CommandResult(
            success: true,
            message: "Set \(contact.name)'s \(key) to \(value)",
            affectedContact: contact
        )
    }

    private func executeAppendArtifact(
        contactName: String,
        key: String,
        value: String,
        forceConvert: Bool,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        let (parsedCategory, parsedKey) = parseCategoryAndKey(from: key)

        if let existing = contact.artifacts.first(where: { $0.searchableKey == parsedKey.lowercased() }) {
            if !existing.isArray && !forceConvert {
                let retryCommand = ParsedCommand.appendArtifact(contactName: contactName, key: key, value: value, forceConvert: true)
                return CommandResult(success: false, message: "Requires conversion confirmation.", affectedContact: nil, requiresConversionPrompt: retryCommand)
            }
            existing.appendValue(value)
            if let newCategory = parsedCategory { existing.category = newCategory }
        } else {
            let artifact = Artifact(key: parsedKey, value: "", isArray: true, category: parsedCategory)
            artifact.contact = contact
            context.insert(artifact)
            artifact.appendValue(value)
        }

        contact.modifiedAt = Date()
        return CommandResult(success: true, message: "Added \(value) to \(contact.name)'s \(parsedKey)", affectedContact: contact)
    }

    private func executeRemoveArtifact(
        contactName: String,
        key: String,
        value: String,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        guard let existing = contact.artifacts.first(where: { $0.searchableKey == key.lowercased() }) else {
            return CommandResult(success: false, message: "\(contact.name) has no '\(key)' artifact.", affectedContact: contact)
        }

        existing.removeValue(value)

        return CommandResult(
            success: true,
            message: "Removed \(value) from \(contact.name)'s \(key)",
            affectedContact: contact
        )
    }

    private func executeDeleteArtifact(
        contactName: String,
        key: String,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        guard let existing = contact.artifacts.first(where: { $0.searchableKey == key.lowercased() }) else {
            return CommandResult(success: false, message: "\(contact.name) has no '\(key)' artifact.", affectedContact: contact)
        }

        context.delete(existing)

        return CommandResult(
            success: true,
            message: "Deleted \(contact.name)'s \(key)",
            affectedContact: contact
        )
    }

    // MARK: - Archive / Restore

    private func executeArchive(
        contactName: String,
        archive: Bool,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context, includeArchived: true) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        contact.isArchived = archive
        contact.modifiedAt = Date()

        let action = archive ? "archived" : "restored"
        return CommandResult(
            success: true,
            message: "\(contact.name) \(action)",
            affectedContact: contact
        )
    }

    // MARK: - Constellation Operations

    private func executeLogConstellationInteraction(
        constellationName: String,
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?,
        in context: ModelContext
    ) -> CommandResult {
        let searchName = constellationName.lowercased()
        let predicate = #Predicate<Constellation> { $0.searchableName == searchName }
        var descriptor = FetchDescriptor<Constellation>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let constellation = try? context.fetch(descriptor).first else {
            return CommandResult(
                success: false,
                message: "Constellation '\(constellationName)' not found.",
                affectedContact: nil
            )
        }

        let members = constellation.contacts.filter { !$0.isArchived }
        guard !members.isEmpty else {
            return CommandResult(
                success: false,
                message: "✦ \(constellation.name) has no active contacts.",
                affectedContact: nil
            )
        }

        let date = CommandParser.resolveTimeModifier(timeModifier)

        for contact in members {
            let interaction = Interaction(
                impulse: impulse,
                content: note ?? "",
                date: date
            )
            interaction.tagNames = tags.joined(separator: ", ")
            interaction.contact = contact
            context.insert(interaction)
            contact.refreshLastContactDate()
        }

        // Ensure tag names exist in registry
        for tagName in tags {
            ensureTagExists(named: tagName, in: context)
        }

        let dateStr = timeModifier != nil ? " on \(date.formatted(date: .abbreviated, time: .omitted))" : ""
        return CommandResult(
            success: true,
            message: "Logged \(impulse) with \(members.count) contacts in ✦ \(constellation.name)\(dateStr)",
            affectedContact: members.first
        )
    }

    private func executeAddToConstellation(
        contactName: String,
        constellationName: String,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        let constellation = findOrCreateConstellation(named: constellationName, in: context)

        // Check if already a member
        if contact.constellations.contains(where: { $0.id == constellation.id }) {
            return CommandResult(
                success: true,
                message: "\(contact.name) is already in ✦ \(constellation.name)",
                affectedContact: contact
            )
        }

        contact.constellations.append(constellation)
        contact.modifiedAt = Date()

        return CommandResult(
            success: true,
            message: "Added \(contact.name) to ✦ \(constellation.name)",
            affectedContact: contact
        )
    }

    private func executeRemoveFromConstellation(
        contactName: String,
        constellationName: String,
        in context: ModelContext
    ) -> CommandResult {
        guard let contact = findContact(named: contactName, in: context) else {
            return CommandResult(success: false, message: "Contact '\(contactName)' not found.", affectedContact: nil)
        }

        let searchName = constellationName.lowercased()
        guard let index = contact.constellations.firstIndex(where: { $0.searchableName == searchName }) else {
            return CommandResult(
                success: false,
                message: "\(contact.name) is not in a constellation named '\(constellationName)'.",
                affectedContact: contact
            )
        }

        let name = contact.constellations[index].name
        contact.constellations.remove(at: index)
        contact.modifiedAt = Date()

        return CommandResult(
            success: true,
            message: "Removed \(contact.name) from ✦ \(name)",
            affectedContact: contact
        )
    }

    /// Find a constellation by name, or create one if it doesn't exist.
    private func findOrCreateConstellation(named name: String, in context: ModelContext) -> Constellation {
        let searchName = name.lowercased()
        let predicate = #Predicate<Constellation> { $0.searchableName == searchName }
        var descriptor = FetchDescriptor<Constellation>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let constellation = Constellation(name: name)
        context.insert(constellation)
        return constellation
    }

    // MARK: - Undo

    private func executeUndo(in context: ModelContext) -> CommandResult {
        guard let interaction = lastCreatedInteraction else {
            return CommandResult(success: false, message: "Nothing to undo.", affectedContact: nil)
        }

        // Soft delete — preserves the record but hides it
        interaction.isDeleted = true
        interaction.contact?.refreshLastContactDate()
        lastCreatedInteraction = nil

        return CommandResult(
            success: true,
            message: "Undid last interaction log",
            affectedContact: interaction.contact
        )
    }
    
    // MARK: Artifact Category
    private func parseCategoryAndKey(from rawKey: String) -> (category: String?, key: String) {
        let components = rawKey.split(separator: "/", maxSplits: 1)
        if components.count == 2 {
            return (String(components[0]).trimmingCharacters(in: .whitespaces),
                    String(components[1]).trimmingCharacters(in: .whitespaces))
        }
        return (nil, rawKey)
    }

    // MARK: - Helpers

    /// Find a contact by name (case-insensitive fuzzy match).
    /// Returns the best match or nil.
    func findContact(named name: String, in context: ModelContext, includeArchived: Bool = false) -> Contact? {
        let searchName = name.lowercased()

        let predicate: Predicate<Contact>
        if includeArchived {
            predicate = #Predicate<Contact> { contact in
                contact.searchableName == searchName
            }
        } else {
            predicate = #Predicate<Contact> { contact in
                contact.searchableName == searchName && contact.isArchived == false
            }
        }

        var descriptor = FetchDescriptor<Contact>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let exactMatch = try? context.fetch(descriptor).first {
            return exactMatch
        }

        // Fallback: prefix match (e.g., "sar" matches "sarah")
        let prefixPredicate = #Predicate<Contact> { contact in
            contact.searchableName.starts(with: searchName) && contact.isArchived == false
        }
        var prefixDescriptor = FetchDescriptor<Contact>(predicate: prefixPredicate)
        prefixDescriptor.fetchLimit = 1

        return try? context.fetch(prefixDescriptor).first
    }

    /// Fetch contacts matching a search prefix (for autocomplete)
    func findContactMatches(prefix: String, in context: ModelContext, limit: Int = 5) -> [Contact] {
        let searchPrefix = prefix.lowercased()
        let predicate = #Predicate<Contact> { contact in
            contact.searchableName.starts(with: searchPrefix) && contact.isArchived == false
        }
        var descriptor = FetchDescriptor<Contact>(predicate: predicate)
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Ensure a tag name exists in the tag registry (for autocomplete).
    /// Does NOT link the tag to any contact — tags are interaction-level data.
    private func ensureTagExists(named name: String, in context: ModelContext) {
        let searchName = name.lowercased()
        let predicate = #Predicate<Tag> { tag in
            tag.searchableName == searchName
        }
        var descriptor = FetchDescriptor<Tag>(predicate: predicate)
        descriptor.fetchLimit = 1

        if (try? context.fetch(descriptor).first) == nil {
            let tag = Tag(name: name)
            context.insert(tag)
        }
    }
}
