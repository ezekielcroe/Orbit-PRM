import Foundation
import SwiftData

// MARK: - CommandExecutor
// Runs the non-logging sigil commands (facts, groups, archive) once the palette
// has resolved every name to a real contact. All writes go through OrbitStore,
// so they get the same cache refresh, save handling and undo as everything else.
// Logging doesn't come through here: it uses CaptureDraft → OrbitStore.log.

enum CommandExecutor {

    enum Outcome: Equatable {
        case done
        /// The fact holds one value; ask before turning it into a list, then
        /// re-run this command.
        case needsListConversion(ParsedCommand)
        case failed(String)
    }

    static func execute(_ command: ParsedCommand, contacts: [Contact], store: OrbitStore) -> Outcome {
        guard !contacts.isEmpty || command.contactNames.isEmpty else {
            return .failed("Pick who this is for first.")
        }

        switch command {
        case let .setArtifact(_, key, value):
            store.changeFact(key, .set(value), for: contacts)
            return .done

        case let .appendArtifact(names, key, value, forceConvert):
            let result = store.changeFact(key, .append(value), for: contacts, convertToList: forceConvert)
            if result == .needsListConversion {
                return .needsListConversion(.appendArtifact(contactNames: names, key: key, value: value, forceConvert: true))
            }
            return .done

        case let .removeArtifact(_, key, value):
            let (_, plainKey) = OrbitStore.parseCategoryAndKey(key)
            guard contacts.contains(where: { store.fact(plainKey, on: $0) != nil }) else {
                return .failed("No “\(plainKey)” fact to remove from.")
            }
            store.changeFact(key, .remove(value), for: contacts)
            return .done

        case let .deleteArtifact(_, key):
            let (_, plainKey) = OrbitStore.parseCategoryAndKey(key)
            guard contacts.contains(where: { store.fact(plainKey, on: $0) != nil }) else {
                return .failed("No “\(plainKey)” fact to delete.")
            }
            store.deleteFact(key, for: contacts)
            return .done

        case let .addToConstellation(_, groupName):
            store.addToGroup(contacts, groupName: groupName)
            return .done

        case let .removeFromConstellation(_, groupName):
            switch store.resolveGroup(groupName) {
            case .resolved(let group):
                store.removeFromGroup(contacts, group: group)
                return .done
            case .ambiguous(let groups):
                return .failed("Which group? \(groups.prefix(5).map(\.name).joined(separator: ", "))")
            case .notFound:
                return .failed("No group called “\(groupName)”.")
            }

        case .archiveContact:
            store.setArchived(true, for: contacts)
            return .done

        case .restoreContact:
            store.setArchived(false, for: contacts)
            return .done

        case .undo:
            store.undo()
            return .done

        case .invalid(let reason):
            return .failed(reason)

        case .logInteraction, .logConstellationInteraction, .searchContact, .searchConstellation:
            return .failed("Not a command.")
        }
    }

    /// Short preview sentence for the palette's confirm row.
    static func describe(_ command: ParsedCommand, people: String) -> String {
        switch command {
        case let .setArtifact(_, key, value): return "Set \(key) to “\(value)” for \(people)"
        case let .appendArtifact(_, key, value, _): return "Add “\(value)” to \(key) for \(people)"
        case let .removeArtifact(_, key, value): return "Remove “\(value)” from \(key) for \(people)"
        case let .deleteArtifact(_, key): return "Delete \(key) for \(people)"
        case let .addToConstellation(_, g): return "Add \(people) to ✦ \(g)"
        case let .removeFromConstellation(_, g): return "Remove \(people) from ✦ \(g)"
        case .archiveContact: return "Archive \(people)"
        case .restoreContact: return "Restore \(people)"
        default: return ""
        }
    }
}
