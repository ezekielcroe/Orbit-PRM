//
//  TagRegistry.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 28/2/26.
//


import Foundation
import SwiftData

// MARK: - TagRegistry
// Single source of truth for tag registry operations.
//
// Previously `ensureTagExists(named:)` was duplicated identically in:
//   - CommandExecutor.swift
//   - InteractionsView.swift
//   - InteractionEditSheet.swift
//
// This consolidates it into one place to prevent drift.

enum TagRegistry {

    /// Ensure a tag name exists in the registry (for autocomplete).
    /// Tags are NOT linked to contacts — they live on interactions only.
    /// This just ensures the name appears in the autocomplete pool.
    static func ensureTagExists(named name: String, in context: ModelContext) {
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

    /// Batch-ensure multiple tag names exist. More efficient than calling
    /// ensureTagExists in a loop when you have many tags to register.
    static func ensureTagsExist(named names: [String], in context: ModelContext) {
        guard !names.isEmpty else { return }

        // Fetch all existing tags in one query
        let descriptor = FetchDescriptor<Tag>()
        let existingNames: Set<String>
        if let allTags = try? context.fetch(descriptor) {
            existingNames = Set(allTags.map(\.searchableName))
        } else {
            existingNames = []
        }

        for name in names {
            if !existingNames.contains(name.lowercased()) {
                let tag = Tag(name: name)
                context.insert(tag)
            }
        }
    }
}