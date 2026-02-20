import Foundation

// MARK: - Token
// Represents a single parsed element from the command palette input.
// Each token knows its type, raw text value, and position in the source string.
// The range is essential for syntax highlighting and cursor-aware autocomplete.

struct Token: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    let value: String
    let range: Range<String.Index>

    enum Kind: Equatable {
        case entity         // @Name
        case constellation  // *GroupName (Phase 2.5)
        case impulse        // !Action
        case tag            // #Topic
        case artifactKey    // > key (before the operator)
        case artifactOp     // : or + or - (the artifact operator itself)
        case artifactValue  // The value after the operator
        case timeModifier   // ^yesterday, ^2d
        case quotedText     // "free text note"
        case text           // Unrecognized plain text
        case void_          // The keyword "void" in artifact deletion
    }
}

// MARK: - Parsed Command
// The final output of command parsing — a fully resolved instruction
// that the CommandExecutor can act on.

enum ParsedCommand {
    /// Log an interaction: @Name !Action #Tag "note" ^time
    case logInteraction(
        contactName: String,
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?
    )

    /// Log an interaction for every member of a constellation:
    /// *Family !Call "Sunday check-in" #Weekly
    case logConstellationInteraction(
        constellationName: String,
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?
    )

    /// Set a singleton artifact: @Name > key: value
    case setArtifact(contactName: String, key: String, value: String)

    /// Append to an array artifact: @Name > key + value
    case appendArtifact(contactName: String, key: String, value: String, forceConvert: Bool)

    /// Remove from an array artifact: @Name > key - value
    case removeArtifact(contactName: String, key: String, value: String)

    /// Delete an artifact key: @Name > key: void
    case deleteArtifact(contactName: String, key: String)

    /// Archive a contact: @Name !archive
    case archiveContact(contactName: String)

    /// Restore a contact from archive: @Name !restore
    case restoreContact(contactName: String)

    /// Search within a contact's artifacts: @Name searchquery
    case searchContact(name: String, query: String)

    /// Navigate to a constellation: *Family
    case searchConstellation(name: String)

    /// Undo the last action
    case undo

    /// The input couldn't be parsed into a valid command
    case invalid(reason: String)
}

// MARK: - Suggestion
// Used by the command palette's autocomplete dropdown.

struct CommandSuggestion: Identifiable {
    let id = UUID()
    let icon: String       // SF Symbol name
    let label: String      // Display text
    let insertion: String  // Text to insert into the command field
    let kind: SuggestionKind

    enum SuggestionKind {
        case contact
        case constellation  // Phase 2.5
        case impulse
        case tag
        case artifactKey
        case command
    }
}
