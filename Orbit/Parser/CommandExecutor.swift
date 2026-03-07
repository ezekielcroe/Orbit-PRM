import Foundation
import SwiftData

// MARK: - CommandExecutor
// Takes a ParsedCommand and executes it against the SwiftData ModelContext.
// This is the bridge between the text parser and the data layer.
// It returns a CommandResult so the UI can show confirmation or errors.
//

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
    
    /// The last save error, if any. UI can observe this.
    private(set) var lastSaveError: String?

    // MARK: - Execute
    
    func execute(_ command: ParsedCommand, in context: ModelContext) -> CommandResult {
        let result: CommandResult
        
        switch command {
        case .logInteraction(let names, let impulse, let tags, let note, let timeMod):
            result = executeLogInteraction(
                contactNames: names,
                impulse: impulse,
                tags: tags,
                note: note,
                timeModifier: timeMod,
                in: context
            )
            
        case .setArtifact(let names, let key, let value):
            result = executeSetArtifact(contactNames: names, key: key, value: value, in: context)
            
        case .appendArtifact(let names, let key, let value, let forceConvert):
            result = executeAppendArtifact(contactNames: names, key: key, value: value, forceConvert: forceConvert, in: context)
            
        case .removeArtifact(let names, let key, let value):
            result = executeRemoveArtifact(contactNames: names, key: key, value: value, in: context)
            
        case .deleteArtifact(let names, let key):
            result = executeDeleteArtifact(contactNames: names, key: key, in: context)
            
        case .archiveContact(let names):
            result = executeArchive(contactNames: names, archive: true, in: context)
            
        case .restoreContact(let names):
            result = executeArchive(contactNames: names, archive: false, in: context)
            
        case .addToConstellation(let names, let constellationName):
            result = executeAddToConstellation(contactNames: names, constellationName: constellationName, in: context)
            
        case .removeFromConstellation(let names, let constellationName):
            result = executeRemoveFromConstellation(contactNames: names, constellationName: constellationName, in: context)
            
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
            
        case .searchConstellation:
            result = CommandResult(success: true, message: "Navigating to constellation", affectedContact: nil)
            
        case .undo:
            result = executeUndo(in: context)
            
        case .invalid(let reason):
            result = CommandResult(success: false, message: reason, affectedContact: nil)
        }
        
        // Single save point with error capture.
        if result.success {
            if !PersistenceHelper.saveWithLogging(context, operation: "execute command") {
                lastSaveError = "Changes may not have been saved."
            } else {
                lastSaveError = nil
            }
        }
        
        lastResult = result
        return result
    }
    
    // MARK: - Interaction Logging
    
    private func executeLogInteraction(
        contactNames: [String],
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToLog: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(
                    success: false,
                    message: ambiguity ?? "Contact '\(name)' not found. Create them first.",
                    affectedContact: nil
                )
            }
            contactsToLog.append(contact)
        }
        
        let date = CommandParser.resolveTimeModifier(timeModifier)
        let batchID = contactsToLog.count > 1 ? UUID() : nil
        
        for contact in contactsToLog {
            let interaction = Interaction(
                impulse: impulse,
                content: note ?? "",
                date: date,
                batchID: batchID
            )
            interaction.tagNames = tags.joined(separator: ", ")
            interaction.contact = contact
            context.insert(interaction)
            
            contact.refreshCachedFields()
            lastCreatedInteraction = interaction
        }
        
        TagRegistry.ensureTagsExist(named: tags, in: context)
        
        let dateStr = timeModifier != nil ? " on \(date.formatted(date: .abbreviated, time: .omitted))" : ""
        let namesString = contactsToLog.count == 1 ? contactsToLog[0].name : "\(contactsToLog.count) contacts"
        
        return CommandResult(
            success: true,
            message: "Logged \(impulse) with \(namesString)\(dateStr)",
            affectedContact: contactsToLog.first
        )
    }
    
    // MARK: - Artifact Operations
    
    private func executeSetArtifact(
        contactNames: [String],
        key: String,
        value: String,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        let (parsedCategory, parsedKey) = parseCategoryAndKey(from: key)
        
        for contact in contactsToUpdate {
            if let existing = contact.artifacts?.first(where: { $0.searchableKey == parsedKey.lowercased() }) {
                existing.setValue(value)
                if let newCategory = parsedCategory { existing.category = newCategory }
            } else {
                let artifact = Artifact(key: parsedKey, value: value, category: parsedCategory)
                artifact.contact = contact
                context.insert(artifact)
            }
            contact.refreshArtifactCache()
        }
        
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(
            success: true,
            message: "Set \(parsedKey) to \(value) for \(namesString)",
            affectedContact: contactsToUpdate.first
        )
    }
    
    private func executeAppendArtifact(
        contactNames: [String],
        key: String,
        value: String,
        forceConvert: Bool,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        let (parsedCategory, parsedKey) = parseCategoryAndKey(from: key)
        
        // Check for conversion requirement across all targets first
        for contact in contactsToUpdate {
            if let existing = contact.artifacts?.first(where: { $0.searchableKey == parsedKey.lowercased() }) {
                if !existing.isArray && !forceConvert {
                    let retryCommand = ParsedCommand.appendArtifact(contactNames: contactNames, key: key, value: value, forceConvert: true)
                    return CommandResult(success: false, message: "Requires conversion confirmation.", affectedContact: nil, requiresConversionPrompt: retryCommand)
                }
            }
        }
        
        for contact in contactsToUpdate {
            if let existing = contact.artifacts?.first(where: { $0.searchableKey == parsedKey.lowercased() }) {
                existing.appendValue(value)
                if let newCategory = parsedCategory { existing.category = newCategory }
            } else {
                let artifact = Artifact(key: parsedKey, value: "", isArray: true, category: parsedCategory)
                artifact.contact = contact
                context.insert(artifact)
                artifact.appendValue(value)
            }
            contact.refreshArtifactCache()
        }
        
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(success: true, message: "Added \(value) to \(parsedKey) for \(namesString)", affectedContact: contactsToUpdate.first)
    }
    
    private func executeRemoveArtifact(
        contactNames: [String],
        key: String,
        value: String,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        for contact in contactsToUpdate {
            guard let existing = contact.artifacts?.first(where: { $0.searchableKey == key.lowercased() }) else {
                continue
            }
            existing.removeValue(value)
        }
        
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(
            success: true,
            message: "Removed \(value) from \(key) for \(namesString)",
            affectedContact: contactsToUpdate.first
        )
    }
    
    private func executeDeleteArtifact(
        contactNames: [String],
        key: String,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        for contact in contactsToUpdate {
            if let existing = contact.artifacts?.first(where: { $0.searchableKey == key.lowercased() }) {
                context.delete(existing)
                contact.refreshArtifactCache()
            }
        }
        
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(
            success: true,
            message: "Deleted \(key) for \(namesString)",
            affectedContact: contactsToUpdate.first
        )
    }
    
    // MARK: - Archive / Restore
    
    private func executeArchive(
        contactNames: [String],
        archive: Bool,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, includeArchived: true, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        for contact in contactsToUpdate {
            contact.isArchived = archive
            contact.modifiedAt = Date()
        }
        
        let action = archive ? "archived" : "restored"
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(
            success: true,
            message: "\(namesString) \(action)",
            affectedContact: contactsToUpdate.first
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
        var constellationAmbiguity: String?
        guard let constellation = findConstellation(named: constellationName, in: context, ambiguityMessage: &constellationAmbiguity) else {
                return CommandResult(
                    success: false,
                    message: constellationAmbiguity ?? "Constellation '\(constellationName)' not found.",
                    affectedContact: nil
                )
            }
        
        let members = (constellation.contacts ?? []).filter { !$0.isArchived }
        guard !(members.isEmpty) else {
            return CommandResult(
                success: false,
                message: "✦ \(constellation.name) has no active contacts.",
                affectedContact: nil
            )
        }
        
        let date = CommandParser.resolveTimeModifier(timeModifier)
        let batchID = UUID()
        
        for contact in members {
            let interaction = Interaction(
                impulse: impulse,
                content: note ?? "",
                date: date,
                batchID: batchID
            )
            interaction.tagNames = tags.joined(separator: ", ")
            interaction.contact = contact
            context.insert(interaction)
            
            contact.refreshCachedFields()
        }
        
        TagRegistry.ensureTagsExist(named: tags, in: context)
        
        let dateStr = timeModifier != nil ? " on \(date.formatted(date: .abbreviated, time: .omitted))" : ""
        return CommandResult(
            success: true,
            message: "Logged \(impulse) with \(members.count) contacts in ✦ \(constellation.name)\(dateStr)",
            affectedContact: members.first
        )
    }
    
    private func executeAddToConstellation(
        contactNames: [String],
        constellationName: String,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        let constellation = findOrCreateConstellation(named: constellationName, in: context)
        
        for contact in contactsToUpdate {
            if contact.constellations?.contains(where: { $0.id == constellation.id }) ?? false {
                continue
            }
            if contact.constellations == nil { contact.constellations = [] }
            contact.constellations?.append(constellation)
            contact.modifiedAt = Date()
        }
        
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(
            success: true,
            message: "Added \(namesString) to ✦ \(constellation.name)",
            affectedContact: contactsToUpdate.first
        )
    }
    
    private func executeRemoveFromConstellation(
        contactNames: [String],
        constellationName: String,
        in context: ModelContext
    ) -> CommandResult {
        var contactsToUpdate: [Contact] = []
        var ambiguity: String?

        for name in contactNames {
            guard let contact = findContact(named: name, in: context, ambiguityMessage: &ambiguity) else {
                return CommandResult(success: false, message: ambiguity ?? "Contact '\(name)' not found.", affectedContact: nil)
            }
            contactsToUpdate.append(contact)
        }
        
        let searchName = constellationName.lowercased()
        var matchedConstellationName = constellationName
        
        for contact in contactsToUpdate {
            let memberships = contact.constellations ?? []
            let exactIndex = memberships.firstIndex(where: { $0.searchableName == searchName })
            let prefixIndex = memberships.firstIndex(where: { $0.searchableName.hasPrefix(searchName) })
            let substringIndex = memberships.firstIndex(where: { $0.searchableName.contains(searchName) })
            
            if let index = exactIndex ?? prefixIndex ?? substringIndex {
                matchedConstellationName = contact.constellations?[index].name ?? "Unknown"
                contact.constellations?.remove(at: index)
                contact.modifiedAt = Date()
            }
        }
        
        let namesString = contactsToUpdate.count == 1 ? contactsToUpdate[0].name : "\(contactsToUpdate.count) contacts"
        return CommandResult(
            success: true,
            message: "Removed \(namesString) from ✦ \(matchedConstellationName)",
            affectedContact: contactsToUpdate.first
        )
    }
    
    private func findOrCreateConstellation(named name: String, in context: ModelContext) -> Constellation {
        var ambiguity: String?
        if let existing = findConstellation(named: name, in: context, ambiguityMessage: &ambiguity) {
            return existing
        }

        let exactName = name.lowercased()
        let exactPredicate = #Predicate<Constellation> { $0.searchableName == exactName }
        var exactDescriptor = FetchDescriptor<Constellation>(predicate: exactPredicate)
        exactDescriptor.fetchLimit = 1
        if let exact = try? context.fetch(exactDescriptor).first {
            return exact
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
        
        interaction.isDeleted = true
        interaction.contact?.refreshCachedFields()
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
    
    func findContact(
        named name: String,
        in context: ModelContext,
        includeArchived: Bool = false,
        ambiguityMessage: inout String?
    ) -> Contact? {
        let searchName = name.lowercased()
        
        // Tier 1: Exact match
        let exactPredicate: Predicate<Contact>
        if includeArchived {
            exactPredicate = #Predicate<Contact> { contact in
                contact.searchableName == searchName
            }
        } else {
            exactPredicate = #Predicate<Contact> { contact in
                contact.searchableName == searchName && contact.isArchived == false
            }
        }
        
        var exactDescriptor = FetchDescriptor<Contact>(predicate: exactPredicate)
        exactDescriptor.fetchLimit = 1
        
        if let exactMatch = try? context.fetch(exactDescriptor).first {
            return exactMatch
        }
        
        // Tier 2: Prefix match
        let prefixPredicate: Predicate<Contact>
        if includeArchived {
            prefixPredicate = #Predicate<Contact> { contact in
                contact.searchableName.starts(with: searchName)
            }
        } else {
            prefixPredicate = #Predicate<Contact> { contact in
                contact.searchableName.starts(with: searchName) && contact.isArchived == false
            }
        }
        
        let prefixResults = (try? context.fetch(FetchDescriptor<Contact>(predicate: prefixPredicate))) ?? []
        
        if prefixResults.count == 1 {
            return prefixResults[0]
        }
        if prefixResults.count > 1 {
            let names = prefixResults.prefix(5).map(\.name).joined(separator: ", ")
            ambiguityMessage = "Multiple contacts match '\(name)': \(names). Be more specific."
            return nil
        }
        
        // Tier 3: Substring match
        let substringPredicate: Predicate<Contact>
        if includeArchived {
            substringPredicate = #Predicate<Contact> { contact in
                contact.searchableName.contains(searchName)
            }
        } else {
            substringPredicate = #Predicate<Contact> { contact in
                contact.searchableName.contains(searchName) && contact.isArchived == false
            }
        }
        
        let substringResults = (try? context.fetch(FetchDescriptor<Contact>(predicate: substringPredicate))) ?? []
        
        if substringResults.count == 1 {
            return substringResults[0]
        }
        if substringResults.count > 1 {
            let names = substringResults.prefix(5).map(\.name).joined(separator: ", ")
            ambiguityMessage = "Multiple contacts match '\(name)': \(names). Be more specific."
            return nil
        }
        
        return nil
    }
    
    func findContact(named name: String, in context: ModelContext, includeArchived: Bool = false) -> Contact? {
        var ambiguity: String?
        return findContact(named: name, in: context, includeArchived: includeArchived, ambiguityMessage: &ambiguity)
    }
    
    func findContactMatches(prefix: String, in context: ModelContext, limit: Int = 5) -> [Contact] {
        let searchTerm = prefix.lowercased()
        
        let predicate = #Predicate<Contact> { contact in
            contact.searchableName.contains(searchTerm) && contact.isArchived == false
        }
        var descriptor = FetchDescriptor<Contact>(predicate: predicate)
        descriptor.fetchLimit = limit * 2
        
        let results = (try? context.fetch(descriptor)) ?? []
        
        let ranked = results.sorted { a, b in
            let aPrefix = a.searchableName.hasPrefix(searchTerm)
            let bPrefix = b.searchableName.hasPrefix(searchTerm)
            if aPrefix != bPrefix { return aPrefix }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }
    
    private func findConstellation(
        named name: String,
        in context: ModelContext,
        ambiguityMessage: inout String?
    ) -> Constellation? {
        let searchName = name.lowercased()

        let exactPredicate = #Predicate<Constellation> { $0.searchableName == searchName }
        var exactDescriptor = FetchDescriptor<Constellation>(predicate: exactPredicate)
        exactDescriptor.fetchLimit = 1

        if let exact = try? context.fetch(exactDescriptor).first {
            return exact
        }

        let prefixPredicate = #Predicate<Constellation> { $0.searchableName.starts(with: searchName) }
        let prefixResults = (try? context.fetch(FetchDescriptor<Constellation>(predicate: prefixPredicate))) ?? []

        if prefixResults.count == 1 { return prefixResults[0] }
        if prefixResults.count > 1 {
            let names = prefixResults.prefix(5).map(\.name).joined(separator: ", ")
            ambiguityMessage = "Multiple constellations match '\(name)': \(names). Be more specific."
            return nil
        }

        let substringPredicate = #Predicate<Constellation> { $0.searchableName.contains(searchName) }
        let substringResults = (try? context.fetch(FetchDescriptor<Constellation>(predicate: substringPredicate))) ?? []

        if substringResults.count == 1 { return substringResults[0] }
        if substringResults.count > 1 {
            let names = substringResults.prefix(5).map(\.name).joined(separator: ", ")
            ambiguityMessage = "Multiple constellations match '\(name)': \(names). Be more specific."
            return nil
        }

        return nil
    }
}
