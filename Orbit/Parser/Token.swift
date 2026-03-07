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
        case impulse        // !Action
        case tag            // #Topic
        case constellation  // *GroupName
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
        contactNames: [String],
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?
    )

    /// Set a singleton artifact: @Name1 @Name2 > key: value
    case setArtifact(contactNames: [String], key: String, value: String)

    /// Append to an array artifact: @Name1 @Name2 > key + value
    case appendArtifact(contactNames: [String], key: String, value: String, forceConvert: Bool)

    /// Remove from an array artifact: @Name1 @Name2 > key - value
    case removeArtifact(contactNames: [String], key: String, value: String)

    /// Delete an artifact key: @Name1 @Name2 > key: void
    case deleteArtifact(contactNames: [String], key: String)

    /// Add contacts to a constellation: @Name1 @Name2 *GroupName
    case addToConstellation(contactNames: [String], constellationName: String)

    /// Remove contacts from a constellation: @Name1 @Name2 *-GroupName
    case removeFromConstellation(contactNames: [String], constellationName: String)

    /// Archive contacts: @Name1 @Name2 !archive
    case archiveContact(contactNames: [String])

    /// Restore contacts from archive: @Name1 @Name2 !restore
    case restoreContact(contactNames: [String])

    /// Log an interaction for every contact in a constellation: *GroupName !Action #tag "note"
    case logConstellationInteraction(
        constellationName: String,
        impulse: String,
        tags: [String],
        note: String?,
        timeModifier: String?
    )

    /// Search within a contact's artifacts: @Name searchquery
    case searchContact(name: String, query: String)
    
    /// Search/Navigate to a constellation: *GroupName
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
        case impulse
        case tag
        case constellation
        case artifactKey
        case command
    }
}
