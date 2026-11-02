import Foundation

// MARK: - Token
// Represents a single parsed element from the command palette input.
// Each token knows its type, raw text value, and position in the source string.
// The range is essential for syntax highlighting and for replacing the token
// the user is typing when they pick a suggestion.

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

    static func == (lhs: Token, rhs: Token) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.range == rhs.range
    }
}

// MARK: - Parsed Command
// Output of the sigil (expert) syntax. Names are still unresolved strings —
// the app resolves them against the store before anything is written, so
// ambiguous or unknown names can be shown to the user instead of failing.

enum ParsedCommand: Equatable {
    /// Log an interaction: @Name !Action #Tag "note" ^time
    /// `date == nil` means "now".
    case logInteraction(contactNames: [String], impulse: String, tags: [String], note: String?, date: Date?)

    /// Set a singleton fact: @Name1 @Name2 > key: value
    case setArtifact(contactNames: [String], key: String, value: String)

    /// Append to a list fact: @Name1 @Name2 > key + value
    case appendArtifact(contactNames: [String], key: String, value: String, forceConvert: Bool)

    /// Remove from a list fact: @Name1 @Name2 > key - value
    case removeArtifact(contactNames: [String], key: String, value: String)

    /// Delete a fact: @Name1 @Name2 > key: void
    case deleteArtifact(contactNames: [String], key: String)

    /// Add contacts to a group: @Name1 @Name2 *GroupName
    case addToConstellation(contactNames: [String], constellationName: String)

    /// Remove contacts from a group: @Name1 @Name2 *-GroupName
    case removeFromConstellation(contactNames: [String], constellationName: String)

    /// Archive contacts: @Name1 @Name2 !archive
    case archiveContact(contactNames: [String])

    /// Restore contacts from archive: @Name1 @Name2 !restore
    case restoreContact(contactNames: [String])

    /// Log an interaction for every member of a group: *GroupName !Action #tag "note"
    case logConstellationInteraction(constellationName: String, impulse: String, tags: [String], note: String?, date: Date?)

    /// Open a contact, optionally with trailing free text: @Name [text]
    case searchContact(name: String, query: String)

    /// Open a group: *GroupName
    case searchConstellation(name: String)

    /// Undo the last change
    case undo

    /// The input couldn't be parsed into a valid command
    case invalid(reason: String)

    /// Every contact name this command refers to.
    var contactNames: [String] {
        switch self {
        case .logInteraction(let n, _, _, _, _),
             .setArtifact(let n, _, _),
             .appendArtifact(let n, _, _, _),
             .removeArtifact(let n, _, _),
             .deleteArtifact(let n, _),
             .addToConstellation(let n, _),
             .removeFromConstellation(let n, _),
             .archiveContact(let n),
             .restoreContact(let n):
            return n
        case .searchContact(let name, _):
            return [name]
        case .logConstellationInteraction, .searchConstellation, .undo, .invalid:
            return []
        }
    }
}

// MARK: - Suggestion
// Used by the command palette's autocomplete dropdown.

struct CommandSuggestion: Identifiable {
    let id = UUID()
    let icon: String       // SF Symbol name
    let label: String      // Display text
    let insertion: String  // Text that replaces the token being typed
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
