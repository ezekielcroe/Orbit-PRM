import Foundation

// MARK: - CommandParser
// A single-pass hand-written tokenizer. This approach is:
// - O(n) performance
// - Zero dependencies
// - Trivial to debug and extend
// - Directly outputs the token types Orbit needs
//
// The parser maps operator characters to token types:
//   @ → entity (contact name)
//   * → constellation (group name)
//   ! → impulse (action/verb)
//   # → tag
//   > → artifact assignment
//   ^ → time modifier
//   "..." → quoted free text
//

final class CommandParser {

    // MARK: - Tokenization

    /// Tokenize raw input into a list of tokens.
    /// Called on every keystroke (with debounce) for real-time syntax highlighting.
    func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var current = input.startIndex
        let end = input.endIndex

        while current < end {
            let char = input[current]

            switch char {
            case "@":
                let token = readEntityToken(input: input, from: current)
                tokens.append(token)
                current = token.range.upperBound

            case "!":
                let token = readPrefixedToken(input: input, from: current, kind: .impulse)
                tokens.append(token)
                current = token.range.upperBound

            case "#":
                let token = readPrefixedToken(input: input, from: current, kind: .tag)
                tokens.append(token)
                current = token.range.upperBound

            case ">":
                // Artifact mode: parse > key[: or + or -]value
                let artifactTokens = readArtifactExpression(input: input, from: current)
                tokens.append(contentsOf: artifactTokens)
                if let last = artifactTokens.last {
                    current = last.range.upperBound
                } else {
                    current = input.index(after: current)
                }

            case "^":
                let token = readPrefixedToken(input: input, from: current, kind: .timeModifier)
                tokens.append(token)
                current = token.range.upperBound

            case "*":
                let token = readConstellationToken(input: input, from: current)
                tokens.append(token)
                current = token.range.upperBound

            case "\"":
                let token = readQuotedText(input: input, from: current)
                tokens.append(token)
                current = token.range.upperBound

            case " ", "\t":
                // Skip whitespace
                current = input.index(after: current)

            default:
                // Plain text — accumulate until next operator or whitespace
                let token = readPlainText(input: input, from: current)
                tokens.append(token)
                current = token.range.upperBound
            }
        }

        return tokens
    }

    // MARK: - Command Parsing

    /// Parse a complete input string into a structured command.
    /// Called when the user submits (hits Return).
    func parse(_ input: String) -> ParsedCommand {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Special case: bare !undo command
        if trimmed.lowercased() == "!undo" {
            return .undo
        }

        let tokens = tokenize(trimmed)

        // Constellation-first command: *GroupName !Action #tag "note" ^time
        // No @contact required — logs interaction for all members of the constellation.
        let hasEntity = tokens.contains(where: { $0.kind == .entity })
        if !hasEntity, let constellationToken = tokens.first(where: { $0.kind == .constellation }) {
            let constellationName = constellationToken.value
            if constellationName.isEmpty || constellationName.hasPrefix("-") {
                return .invalid(reason: "Constellation name required after *")
            }

            if let impulseToken = tokens.first(where: { $0.kind == .impulse }) {
                let tags = tokens.filter { $0.kind == .tag }.map(\.value)
                let note = tokens.first(where: { $0.kind == .quotedText })?.value
                let timeMod = tokens.first(where: { $0.kind == .timeModifier })?.value

                return .logConstellationInteraction(
                    constellationName: constellationName,
                    impulse: impulseToken.value,
                    tags: tags,
                    note: note,
                    timeModifier: timeMod
                )
            }

            return .invalid(reason: "Constellation command needs an action: *\(constellationName) !Action")
        }

        // Must have an entity (@contact)
        // FIX 2: Improved error message — the @ token doesn't need to be first
        let entityTokens = tokens.filter { $0.kind == .entity }
        guard !entityTokens.isEmpty else {
            return .invalid(reason: "No contact specified. Use @Name (e.g., @Sarah or @\"Sarah Connor\")")
        }

        let contactNames = entityTokens.map(\.value)
        let contactName = contactNames.first!

        // Check for archive/restore
        if let impulseToken = tokens.first(where: { $0.kind == .impulse }) {
            if impulseToken.value.lowercased() == "archive" {
                return .archiveContact(contactNames: contactNames)
            }
            if impulseToken.value.lowercased() == "restore" {
                return .restoreContact(contactNames: contactNames)
            }
        }

        // Check for constellation operations: *GroupName or *-GroupName
        if let constellationToken = tokens.first(where: { $0.kind == .constellation }) {
            let value = constellationToken.value
            if value.hasPrefix("-") {
                let name = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
                if name.isEmpty { return .invalid(reason: "Constellation name required after *-") }
                return .removeFromConstellation(contactNames: contactNames, constellationName: name)
            } else {
                if value.isEmpty { return .invalid(reason: "Constellation name required after *") }
                return .addToConstellation(contactNames: contactNames, constellationName: value)
            }
        }

        // Check for artifact operations
        if tokens.contains(where: { $0.kind == .artifactKey }) {
            return parseArtifactCommand(contactNames: contactNames, tokens: tokens)
        }

        // Check for interaction logging (has an impulse)
        if let impulseToken = tokens.first(where: { $0.kind == .impulse }) {
            let tags = tokens.filter { $0.kind == .tag }.map(\.value)
            let note = tokens.first(where: { $0.kind == .quotedText })?.value
            let timeMod = tokens.first(where: { $0.kind == .timeModifier })?.value

            return .logInteraction(
                contactNames: contactNames,
                impulse: impulseToken.value,
                tags: tags,
                note: note,
                timeModifier: timeMod
            )
        }

        // Fallback: treat remaining text as a search query
        let searchTerms = tokens
            .filter { $0.kind == .text }
            .map(\.value)
            .joined(separator: " ")

        if !searchTerms.isEmpty {
            return .searchContact(name: contactName, query: searchTerms)
        }

        // Just a bare @Name — treat as a lookup
        return .searchContact(name: contactName, query: "")
    }

    // MARK: - Private Tokenizer Helpers

    /// FIX 2: Read an entity token with multi-word support.
    /// Supports two forms:
    ///   @"Sarah Connor"  — quoted multi-word name
    ///   @Sarah           — single word (stops at space/operator)
    ///   @Sarah-Connor    — hyphenated (no spaces, works as before)
    private func readEntityToken(input: String, from start: String.Index) -> Token {
        let afterAt = input.index(after: start)
        let end = input.endIndex

        guard afterAt < end else {
            return Token(kind: .entity, value: "", range: start..<afterAt)
        }

        // Check for quoted form: @"Sarah Connor"
        if input[afterAt] == "\"" {
            let quoteStart = input.index(after: afterAt) // skip opening quote
            var current = quoteStart

            while current < end && input[current] != "\"" {
                current = input.index(after: current)
            }

            let value = String(input[quoteStart..<current])

            // Skip closing quote if present
            if current < end && input[current] == "\"" {
                current = input.index(after: current)
            }

            return Token(kind: .entity, value: value, range: start..<current)
        }

        // Unquoted form: consume until next operator character or end
        // FIX 2: For @entity, we consume until the next sigil operator,
        // trimming trailing whitespace. This allows "@Sarah Connor !Coffee"
        // to parse correctly as entity="Sarah Connor" impulse="Coffee".
        var current = afterAt

        while current < end {
            let char = input[current]
            if isOperator(char) || char == "\"" {
                break
            }
            current = input.index(after: current)
        }

        let rawValue = String(input[afterAt..<current])
        let value = rawValue.trimmingCharacters(in: .whitespaces)

        return Token(kind: .entity, value: value, range: start..<current)
    }

    /// Read a prefixed token (!Action, #Tag, ^yesterday)
    /// Accumulates characters after the prefix until whitespace or another operator.
    private func readPrefixedToken(input: String, from start: String.Index, kind: Token.Kind) -> Token {
        // Skip the operator character itself
        var current = input.index(after: start)
        let end = input.endIndex

        while current < end {
            let char = input[current]
            if char == " " || char == "\t" || isOperator(char) {
                break
            }
            current = input.index(after: current)
        }

        // The value excludes the prefix character
        let valueStart = input.index(after: start)
        let value = String(input[valueStart..<current])

        return Token(kind: kind, value: value, range: start..<current)
    }

    /// Read a quoted text block: "some free text here"
    private func readQuotedText(input: String, from start: String.Index) -> Token {
        var current = input.index(after: start) // Skip opening quote
        let end = input.endIndex

        while current < end && input[current] != "\"" {
            current = input.index(after: current)
        }

        let valueStart = input.index(after: start)
        let value = String(input[valueStart..<current])

        // Skip closing quote if present
        if current < end && input[current] == "\"" {
            current = input.index(after: current)
        }

        return Token(kind: .quotedText, value: value, range: start..<current)
    }

    /// Read plain text until the next operator or end of input
    private func readPlainText(input: String, from start: String.Index) -> Token {
        var current = start
        let end = input.endIndex

        while current < end {
            let char = input[current]
            if char == " " || char == "\t" || isOperator(char) || char == "\"" {
                break
            }
            current = input.index(after: current)
        }

        let value = String(input[start..<current])
        return Token(kind: .text, value: value, range: start..<current)
    }

    /// Read a constellation token: *GroupName or *-GroupName
    /// FIX 2: Also supports *"Group Name" quoted form for multi-word constellations
    private func readConstellationToken(input: String, from start: String.Index) -> Token {
        let afterStar = input.index(after: start) // Skip *
        let end = input.endIndex

        guard afterStar < end else {
            return Token(kind: .constellation, value: "", range: start..<afterStar)
        }

        // Check for removal prefix
        var valueStart = afterStar
        let isRemoval = input[afterStar] == "-"
        if isRemoval && input.index(after: afterStar) < end {
            valueStart = input.index(after: afterStar)
        }

        // Check for quoted form: *"Group Name" or *-"Group Name"
        if valueStart < end && input[valueStart] == "\"" {
            let quoteStart = input.index(after: valueStart)
            var current = quoteStart

            while current < end && input[current] != "\"" {
                current = input.index(after: current)
            }

            let name = String(input[quoteStart..<current])
            let value = isRemoval ? "-\(name)" : name

            if current < end && input[current] == "\"" {
                current = input.index(after: current)
            }

            return Token(kind: .constellation, value: value, range: start..<current)
        }

        // Unquoted: consume until space/operator
        var current = afterStar
        while current < end {
            let char = input[current]
            if char == " " || char == "\t" || isOperator(char) {
                break
            }
            current = input.index(after: current)
        }

        let value = String(input[afterStar..<current])
        return Token(kind: .constellation, value: value, range: start..<current)
    }

    /// Parse an artifact expression: > key: value, > key + value, > key - value
    private func readArtifactExpression(input: String, from start: String.Index) -> [Token] {
        var tokens: [Token] = []
        var current = input.index(after: start) // Skip >

        // Skip whitespace after >
        current = skipWhitespace(in: input, from: current)

        let keyStart = current

        // Read the key — until we hit :, +, -, or end
        while current < input.endIndex {
            let char = input[current]
            if char == ":" || char == "+" || char == "-" || isOperator(char) {
                break
            }
            if char == " " {
                // Could be space before operator or space in multi-word key
                // Peek ahead to see if next non-space char is an operator
                let afterSpace = skipWhitespace(in: input, from: input.index(after: current))
                if afterSpace < input.endIndex && (input[afterSpace] == ":" || input[afterSpace] == "+" || input[afterSpace] == "-") {
                    break
                }
            }
            current = input.index(after: current)
        }

        let keyValue = String(input[keyStart..<current]).trimmingCharacters(in: .whitespaces)
        if !keyValue.isEmpty {
            tokens.append(Token(kind: .artifactKey, value: keyValue, range: start..<current))
        }

        // Skip whitespace before operator
        current = skipWhitespace(in: input, from: current)

        // Read the artifact operator
        if current < input.endIndex {
            let opChar = input[current]
            if opChar == ":" || opChar == "+" || opChar == "-" {
                let opStart = current
                current = input.index(after: current)
                tokens.append(Token(kind: .artifactOp, value: String(opChar), range: opStart..<current))

                // Skip whitespace after operator
                current = skipWhitespace(in: input, from: current)

                // Read the value — everything remaining until next major operator or end
                let valueStart = current
                while current < input.endIndex && !isOperator(input[current]) {
                    current = input.index(after: current)
                }

                let rawValue = String(input[valueStart..<current]).trimmingCharacters(in: .whitespaces)
                if !rawValue.isEmpty {
                    let kind: Token.Kind = rawValue.lowercased() == "void" ? .void_ : .artifactValue
                    tokens.append(Token(kind: kind, value: rawValue, range: valueStart..<current))
                }
            }
        }

        return tokens
    }

    /// Check if a character is one of Orbit's command operators
    private func isOperator(_ char: Character) -> Bool {
        return char == "@" || char == "!" || char == "#" || char == ">" || char == "^" || char == "*"
    }

    /// Advance past whitespace characters
    private func skipWhitespace(in input: String, from start: String.Index) -> String.Index {
        var current = start
        while current < input.endIndex && (input[current] == " " || input[current] == "\t") {
            current = input.index(after: current)
        }
        return current
    }

    // MARK: - Artifact Command Resolution

    private func parseArtifactCommand(contactNames: [String], tokens: [Token]) -> ParsedCommand {
        guard let keyToken = tokens.first(where: { $0.kind == .artifactKey }) else {
            return .invalid(reason: "Artifact command requires a key")
        }

        let opToken = tokens.first(where: { $0.kind == .artifactOp })
        let valueToken = tokens.first(where: { $0.kind == .artifactValue || $0.kind == .void_ })

        let key = keyToken.value
        let op = opToken?.value ?? ":"
        let value = valueToken?.value ?? ""

        // Handle void deletion
        if valueToken?.kind == .void_ || value.lowercased() == "void" {
            return .deleteArtifact(contactNames: contactNames, key: key)
        }

        switch op {
            case ":": return .setArtifact(contactNames: contactNames, key: key, value: value)
            case "+": return .appendArtifact(contactNames: contactNames, key: key, value: value, forceConvert: false)
            case "-": return .removeArtifact(contactNames: contactNames, key: key, value: value)
            default:  return .setArtifact(contactNames: contactNames, key: key, value: value)
            }
    }

    // MARK: - Time Modifier Resolution

    /// Resolve a time modifier string (^yesterday, ^2d, ^3h) to a Date.
    /// Returns nil for unrecognized formats, defaulting to "now".
    static func resolveTimeModifier(_ modifier: String?) -> Date {
        guard let mod = modifier?.lowercased() else { return Date() }

        switch mod {
        case "yesterday":
            return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        case "today":
            return Date()
        default:
            // Parse patterns like "2d", "3h", "1w"
            let scanner = Scanner(string: mod)
            var number: Int = 0

            if scanner.scanInt(&number) {
                let remaining = String(mod.dropFirst(String(number).count))
                switch remaining {
                case "d": return Calendar.current.date(byAdding: .day, value: -number, to: Date()) ?? Date()
                case "h": return Calendar.current.date(byAdding: .hour, value: -number, to: Date()) ?? Date()
                case "w": return Calendar.current.date(byAdding: .weekOfYear, value: -number, to: Date()) ?? Date()
                case "m": return Calendar.current.date(byAdding: .month, value: -number, to: Date()) ?? Date()
                default: break
                }
            }

            return Date()
        }
    }
}
