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
        
        // FIX P1-2.1: Single save point with error capture.
        // All mutating methods above modify objects without saving.
        // We save once here, and capture any errors.
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
        contactName: String,
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?,
        in context: ModelContext
    ) -> CommandResult {
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
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
        
        // FIX P0-1.1: Use refreshCachedFields() to update all caches in one pass
        contact.refreshCachedFields()
        
        // FIX P2-3.5: Use consolidated TagRegistry
        TagRegistry.ensureTagsExist(named: tags, in: context)
        
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
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }
        
        let (parsedCategory, parsedKey) = parseCategoryAndKey(from: key)
        
        // Find existing artifact with this key, or create new
        if let existing = contact.artifacts?.first(where: { $0.searchableKey == parsedKey.lowercased() }) {
            existing.setValue(value)
            if let newCategory = parsedCategory { existing.category = newCategory }
        } else {
            let artifact = Artifact(key: parsedKey, value: value, category: parsedCategory)
            artifact.contact = contact
            context.insert(artifact)
        }
        
        contact.refreshArtifactCache()
        
        return CommandResult(
            success: true,
            message: "Set \(contact.name)'s \(parsedKey) to \(value)",
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
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }
        
        let (parsedCategory, parsedKey) = parseCategoryAndKey(from: key)
        
        if let existing = contact.artifacts?.first(where: { $0.searchableKey == parsedKey.lowercased() }) {
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
        
        contact.refreshArtifactCache()
        return CommandResult(success: true, message: "Added \(value) to \(contact.name)'s \(parsedKey)", affectedContact: contact)
    }
    
    private func executeRemoveArtifact(
        contactName: String,
        key: String,
        value: String,
        in context: ModelContext
    ) -> CommandResult {
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }
        
        guard let existing = contact.artifacts?.first(where: { $0.searchableKey == key.lowercased() }) else {
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
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }
        
        guard let existing = contact.artifacts?.first(where: { $0.searchableKey == key.lowercased() }) else {
            return CommandResult(success: false, message: "\(contact.name) has no '\(key)' artifact.", affectedContact: contact)
        }
        
        context.delete(existing)
        contact.refreshArtifactCache()
        
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
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, includeArchived: true, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
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
        let batchID = UUID() // Shared across all interactions in this constellation log
        
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
        
        // FIX P2-3.5: Use consolidated TagRegistry with batch insert
        TagRegistry.ensureTagsExist(named: tags, in: context)
        
        let dateStr = timeModifier != nil ? " on \(date.formatted(date: .abbreviated, time: .omitted))" : ""
        return CommandResult(
            success: true,
            message: "Logged \(impulse) with \(String(describing: members.count)) contacts in ✦ \(constellation.name)\(dateStr)",
            affectedContact: members.first
        )
    }
    
    private func executeAddToConstellation(
        contactName: String,
        constellationName: String,
        in context: ModelContext
    ) -> CommandResult {
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }
        
        let constellation = findOrCreateConstellation(named: constellationName, in: context)
        
        // Check if already a member
        if contact.constellations?.contains(where: { $0.id == constellation.id }) ?? false {
            return CommandResult(
                success: true,
                message: "\(contact.name) is already in ✦ \(constellation.name)",
                affectedContact: contact
            )
        }
        if contact.constellations == nil {
            contact.constellations = []
        }
        contact.constellations?.append(constellation)
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
        var ambiguity: String?
        guard let contact = findContact(named: contactName, in: context, ambiguityMessage: &ambiguity) else {
            return CommandResult(
                success: false,
                message: ambiguity ?? "Contact '\(contactName)' not found. Create them first.",
                affectedContact: nil
            )
        }
        
        let searchName = constellationName.lowercased()
        // Three-tier match on the contact's constellation memberships
        let memberships = contact.constellations ?? []
        let exactIndex = memberships.firstIndex(where: { $0.searchableName == searchName })
        let prefixIndex = memberships.firstIndex(where: { $0.searchableName.hasPrefix(searchName) })
        let substringIndex = memberships.firstIndex(where: { $0.searchableName.contains(searchName) })
        guard let index = exactIndex ?? prefixIndex ?? substringIndex else {
            return CommandResult(
                success: false,
                message: "\(contact.name) is not in a constellation named '\(constellationName)'.",
                affectedContact: contact
            )
        }
        
        let name = contact.constellations?[index].name ?? "Unknown"
        contact.constellations?.remove(at: index)
        contact.modifiedAt = Date()
        
        return CommandResult(
            success: true,
            message: "Removed \(contact.name) from ✦ \(name)",
            affectedContact: contact
        )
    }
    
    /// Find a constellation by name (with substring matching), or create one if not found.
    /// For creation, uses the original (un-lowercased) name.
    private func findOrCreateConstellation(named name: String, in context: ModelContext) -> Constellation {
        var ambiguity: String?
        if let existing = findConstellation(named: name, in: context, ambiguityMessage: &ambiguity) {
            return existing
        }

        // If ambiguous (multiple matches), don't create a new one — use exact match as tiebreaker.
        // This prevents accidentally creating "Family" when "Family Friends" and "Family" both exist.
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
        
        // Soft delete — preserves the record but hides it
        interaction.isDeleted = true
        // FIX P0-1.1: Update caches after undo
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
    
    /// Find a contact by name using three-tier matching:
    ///   1. Exact match (case-insensitive)
    ///   2. Prefix match
    ///   3. Substring match (e.g., "Connor" matches "Sarah Connor")
    ///
    /// If a tier produces exactly one result, it's returned.
    /// If a tier produces multiple results, nil is returned (ambiguous).
    /// The `ambiguityMessage` inout parameter is set when multiple
    /// matches are found, so the caller can surface a helpful error.
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
        
        // Tier 2: Prefix match (e.g., "sar" → "sarah connor")
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
        
        // Tier 3: Substring match (e.g., "connor" → "sarah connor")
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
    
    /// Convenience overload that discards the ambiguity message (backward compatible).
    func findContact(named name: String, in context: ModelContext, includeArchived: Bool = false) -> Contact? {
        var ambiguity: String?
        return findContact(named: name, in: context, includeArchived: includeArchived, ambiguityMessage: &ambiguity)
    }
    
    /// Fetch contacts matching a search string (for autocomplete).
    /// Uses substring matching and ranks results: prefix matches first, then substring.
    func findContactMatches(prefix: String, in context: ModelContext, limit: Int = 5) -> [Contact] {
        let searchTerm = prefix.lowercased()
        
        // Fetch all substring matches
        let predicate = #Predicate<Contact> { contact in
            contact.searchableName.contains(searchTerm) && contact.isArchived == false
        }
        var descriptor = FetchDescriptor<Contact>(predicate: predicate)
        descriptor.fetchLimit = limit * 2 // Fetch extra to allow ranking
        
        let results = (try? context.fetch(descriptor)) ?? []
        
        // Rank: prefix matches first, then substring-only matches
        let ranked = results.sorted { a, b in
            let aPrefix = a.searchableName.hasPrefix(searchTerm)
            let bPrefix = b.searchableName.hasPrefix(searchTerm)
            if aPrefix != bPrefix { return aPrefix }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }
    
    /// Find a constellation by name using three-tier matching:
    ///   1. Exact match (case-insensitive)
    ///   2. Prefix match
    ///   3. Substring match
    ///
    /// Returns nil if no match or ambiguous (multiple matches at same tier).
    private func findConstellation(
        named name: String,
        in context: ModelContext,
        ambiguityMessage: inout String?
    ) -> Constellation? {
        let searchName = name.lowercased()

        // Tier 1: Exact match
        let exactPredicate = #Predicate<Constellation> { $0.searchableName == searchName }
        var exactDescriptor = FetchDescriptor<Constellation>(predicate: exactPredicate)
        exactDescriptor.fetchLimit = 1

        if let exact = try? context.fetch(exactDescriptor).first {
            return exact
        }

        // Tier 2: Prefix match
        let prefixPredicate = #Predicate<Constellation> { $0.searchableName.starts(with: searchName) }
        let prefixResults = (try? context.fetch(FetchDescriptor<Constellation>(predicate: prefixPredicate))) ?? []

        if prefixResults.count == 1 { return prefixResults[0] }
        if prefixResults.count > 1 {
            let names = prefixResults.prefix(5).map(\.name).joined(separator: ", ")
            ambiguityMessage = "Multiple constellations match '\(name)': \(names). Be more specific."
            return nil
        }

        // Tier 3: Substring match
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
