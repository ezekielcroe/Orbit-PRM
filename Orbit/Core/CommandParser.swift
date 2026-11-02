import Foundation

// MARK: - CommandParser
// The expert ("sigil") syntax for the command palette. Plain-language input
// goes through NaturalLanguageParser instead; CaptureParser picks between them.
//
//   @ → contact          * → group          ! → action
//   # → tag              > → fact           ^ → time
//   "..." → note (unquoted leftover text is also kept as the note)
//
// Operators are only recognised at the start of a word, so values like
// tom@gmail.com, "Rock & Roll!" or a t-shirt size keep their characters.

final class CommandParser {

    /// Known contact names. When provided, an unquoted `@Sarah coffee` is split
    /// into the longest known name ("Sarah") plus leftover text ("coffee").
    var knownNames: [String]
    var dates: DatePhraseParser

    init(knownNames: [String] = [], dates: DatePhraseParser = DatePhraseParser()) {
        self.knownNames = knownNames
        self.dates = dates
    }

    // MARK: - Mode detection

    /// True when the text uses sigil syntax: an operator at the start of a word.
    /// `#tag` alone does not count — plain-language input may contain tags.
    static func looksLikeSigilSyntax(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "!undo" { return true }
        var previous: Character = " "
        for char in trimmed {
            if previous.isWhitespace, "@!>^*".contains(char) { return true }
            previous = char
        }
        return false
    }

    // MARK: - Tokenization

    /// Tokenize raw input into a list of tokens.
    /// Called on every keystroke (debounced) for syntax highlighting.
    func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var current = input.startIndex
        let end = input.endIndex

        while current < end {
            let char = input[current]

            switch char {
            case "@":
                tokens.append(contentsOf: readEntityTokens(input: input, from: current))
                current = tokens.last!.range.upperBound

            case "!":
                let token = readPrefixedToken(input: input, from: current, kind: .impulse)
                tokens.append(token)
                current = token.range.upperBound

            case "#":
                let token = readPrefixedToken(input: input, from: current, kind: .tag)
                tokens.append(token)
                current = token.range.upperBound

            case ">":
                let artifactTokens = readArtifactExpression(input: input, from: current)
                tokens.append(contentsOf: artifactTokens)
                current = artifactTokens.last?.range.upperBound ?? input.index(after: current)

            case "^":
                let token = readTimeToken(input: input, from: current)
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
                current = input.index(after: current)

            default:
                let token = readPlainText(input: input, from: current)
                tokens.append(token)
                current = token.range.upperBound
            }
        }

        return tokens
    }

    // MARK: - Command Parsing

    func parse(_ input: String, now: Date = Date()) -> ParsedCommand {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if trimmed.lowercased() == "!undo" {
            return .undo
        }

        let tokens = tokenize(trimmed)

        // Unknown time modifiers are an error — never silently "now".
        var date: Date?
        if let timeToken = tokens.first(where: { $0.kind == .timeModifier }) {
            guard let resolved = dates.resolveShorthand(timeToken.value, now: now) else {
                return .invalid(reason: "I don't understand ^\(timeToken.value). Try ^yesterday, ^3d, ^2w or ^last-monday.")
            }
            date = resolved
        }

        let tags = tokens.filter { $0.kind == .tag }.map(\.value).filter { !$0.isEmpty }
        let note = noteText(from: tokens)

        // Group-first command: *GroupName !Action #tag "note" ^time
        let hasEntity = tokens.contains(where: { $0.kind == .entity })
        if !hasEntity, let constellationToken = tokens.first(where: { $0.kind == .constellation }) {
            let constellationName = constellationToken.value
            if constellationName.isEmpty || constellationName.hasPrefix("-") {
                return .invalid(reason: "Group name required after *")
            }

            if let impulseToken = tokens.first(where: { $0.kind == .impulse }) {
                guard !impulseToken.value.isEmpty else { return .invalid(reason: "Action required after !") }
                return .logConstellationInteraction(
                    constellationName: constellationName,
                    impulse: impulseToken.value,
                    tags: tags,
                    note: note,
                    date: date
                )
            }

            return .searchConstellation(name: constellationName)
        }

        let entityTokens = tokens.filter { $0.kind == .entity }
        guard !entityTokens.isEmpty else {
            return .invalid(reason: "No contact specified. Use @Name (e.g. @Sarah or @\"Sarah Connor\"), or just type in plain words.")
        }

        let contactNames = entityTokens.map(\.value).filter { !$0.isEmpty }
        guard let contactName = contactNames.first else {
            return .invalid(reason: "Type a name after @")
        }

        if let impulseToken = tokens.first(where: { $0.kind == .impulse }) {
            switch impulseToken.value.lowercased() {
            case "archive": return .archiveContact(contactNames: contactNames)
            case "restore": return .restoreContact(contactNames: contactNames)
            default: break
            }
        }

        if let constellationToken = tokens.first(where: { $0.kind == .constellation }) {
            let value = constellationToken.value
            if value.hasPrefix("-") {
                let name = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
                if name.isEmpty { return .invalid(reason: "Group name required after *-") }
                return .removeFromConstellation(contactNames: contactNames, constellationName: name)
            } else {
                if value.isEmpty { return .invalid(reason: "Group name required after *") }
                return .addToConstellation(contactNames: contactNames, constellationName: value)
            }
        }

        if tokens.contains(where: { $0.kind == .artifactKey }) {
            return parseArtifactCommand(contactNames: contactNames, tokens: tokens)
        }

        if let impulseToken = tokens.first(where: { $0.kind == .impulse }) {
            guard !impulseToken.value.isEmpty else { return .invalid(reason: "Action required after !") }
            return .logInteraction(
                contactNames: contactNames,
                impulse: impulseToken.value,
                tags: tags,
                note: note,
                date: date
            )
        }

        // No action: leftover text is handed back so CaptureParser can try
        // reading it as plain language ("@Sarah coffee yesterday").
        let leftover = tokens
            .filter { $0.kind == .text || $0.kind == .quotedText }
            .map(\.value)
            .joined(separator: " ")
        var query = leftover
        if let timeToken = tokens.first(where: { $0.kind == .timeModifier }) {
            query += (query.isEmpty ? "" : " ") + "^" + timeToken.value
        }
        return .searchContact(name: contactName, query: query)
    }

    /// Quoted text plus any unquoted leftover words, in the order typed.
    private func noteText(from tokens: [Token]) -> String? {
        let parts = tokens
            .filter { $0.kind == .quotedText || $0.kind == .text }
            .map { $0.value.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    // MARK: - Tokenizer Helpers

    private func isOperator(_ char: Character) -> Bool {
        char == "@" || char == "!" || char == "#" || char == ">" || char == "^" || char == "*"
    }

    /// An operator only starts a new token when it begins a word.
    private func isOperatorBoundary(_ input: String, _ index: String.Index) -> Bool {
        guard isOperator(input[index]) else { return false }
        if index == input.startIndex { return true }
        return input[input.index(before: index)].isWhitespace
    }

    /// Entity: @"Sarah Connor", @Sarah, or @Sarah Connor (unquoted, runs to the
    /// next operator). With `knownNames`, an unquoted run is trimmed to the
    /// longest leading words that match a known contact and the rest becomes text.
    private func readEntityTokens(input: String, from start: String.Index) -> [Token] {
        let afterAt = input.index(after: start)
        let end = input.endIndex

        guard afterAt < end else {
            return [Token(kind: .entity, value: "", range: start..<afterAt)]
        }

        if input[afterAt] == "\"" {
            let quoteStart = input.index(after: afterAt)
            var current = quoteStart
            while current < end && input[current] != "\"" {
                current = input.index(after: current)
            }
            let value = String(input[quoteStart..<current])
            if current < end { current = input.index(after: current) }
            return [Token(kind: .entity, value: value, range: start..<current)]
        }

        var current = afterAt
        while current < end {
            if input[current] == "\"" || (input[current].isWhitespace == false && isOperatorBoundary(input, current)) {
                break
            }
            // An operator preceded by whitespace ends the name.
            if input[current].isWhitespace {
                let next = input.index(after: current)
                if next < end, isOperator(input[next]) || input[next] == "\"" { break }
            }
            current = input.index(after: current)
        }

        let raw = String(input[afterAt..<current])
        let value = raw.trimmingCharacters(in: .whitespaces)

        guard !knownNames.isEmpty, value.contains(" ") else {
            return [Token(kind: .entity, value: value, range: start..<current)]
        }

        // Longest leading word sequence that matches a known contact.
        let candidates = knownNames.map { NameCandidate(id: UUID(), name: $0) }
        let words = value.split(separator: " ", omittingEmptySubsequences: true)
        for count in stride(from: words.count, through: 1, by: -1) {
            let attempt = words.prefix(count).joined(separator: " ")
            if NameMatcher.match(attempt, in: candidates) != .none {
                if count == words.count {
                    return [Token(kind: .entity, value: value, range: start..<current)]
                }
                // Find where the matched words end in the original string.
                var scan = afterAt
                var seen = 0
                var inWord = false
                while scan < current {
                    let isSpace = input[scan].isWhitespace
                    if !isSpace && !inWord { inWord = true }
                    if isSpace && inWord { inWord = false; seen += 1; if seen == count { break } }
                    scan = input.index(after: scan)
                }
                let entity = Token(kind: .entity, value: attempt, range: start..<scan)
                var rest = scan
                while rest < current, input[rest].isWhitespace { rest = input.index(after: rest) }
                let restValue = String(input[rest..<current]).trimmingCharacters(in: .whitespaces)
                guard !restValue.isEmpty else { return [entity] }
                return [entity, Token(kind: .text, value: restValue, range: rest..<current)]
            }
        }
        return [Token(kind: .entity, value: value, range: start..<current)]
    }

    /// !Action, #Tag — runs until whitespace.
    private func readPrefixedToken(input: String, from start: String.Index, kind: Token.Kind) -> Token {
        var current = input.index(after: start)
        let end = input.endIndex
        while current < end && !input[current].isWhitespace && input[current] != "\"" {
            current = input.index(after: current)
        }
        let valueStart = input.index(after: start)
        return Token(kind: kind, value: String(input[valueStart..<current]), range: start..<current)
    }

    /// ^yesterday, ^3d, ^last-monday, or ^"last monday".
    private func readTimeToken(input: String, from start: String.Index) -> Token {
        let afterCaret = input.index(after: start)
        if afterCaret < input.endIndex && input[afterCaret] == "\"" {
            let quoted = readQuotedText(input: input, from: afterCaret)
            return Token(kind: .timeModifier, value: quoted.value, range: start..<quoted.range.upperBound)
        }
        return readPrefixedToken(input: input, from: start, kind: .timeModifier)
    }

    private func readQuotedText(input: String, from start: String.Index) -> Token {
        var current = input.index(after: start)
        let end = input.endIndex
        while current < end && input[current] != "\"" {
            current = input.index(after: current)
        }
        let valueStart = input.index(after: start)
        let value = String(input[valueStart..<current])
        if current < end { current = input.index(after: current) }
        return Token(kind: .quotedText, value: value, range: start..<current)
    }

    /// Plain text — one word, up to whitespace or a quote.
    private func readPlainText(input: String, from start: String.Index) -> Token {
        var current = start
        let end = input.endIndex
        while current < end && !input[current].isWhitespace && input[current] != "\"" {
            current = input.index(after: current)
        }
        if current == start { current = input.index(after: start) }
        return Token(kind: .text, value: String(input[start..<current]), range: start..<current)
    }

    /// *GroupName, *-GroupName, *"Group Name", *-"Group Name"
    private func readConstellationToken(input: String, from start: String.Index) -> Token {
        let afterStar = input.index(after: start)
        let end = input.endIndex

        guard afterStar < end else {
            return Token(kind: .constellation, value: "", range: start..<afterStar)
        }

        var valueStart = afterStar
        let isRemoval = input[afterStar] == "-"
        if isRemoval && input.index(after: afterStar) < end {
            valueStart = input.index(after: afterStar)
        }

        if valueStart < end && input[valueStart] == "\"" {
            let quoted = readQuotedText(input: input, from: valueStart)
            let value = isRemoval ? "-\(quoted.value)" : quoted.value
            return Token(kind: .constellation, value: value, range: start..<quoted.range.upperBound)
        }

        var current = afterStar
        while current < end && !input[current].isWhitespace {
            current = input.index(after: current)
        }
        return Token(kind: .constellation, value: String(input[afterStar..<current]), range: start..<current)
    }

    /// > key: value, > key + value, > key - value, > category/key: value
    /// A `-` only acts as the remove operator when it follows whitespace, so
    /// "t-shirt size" is a valid key.
    private func readArtifactExpression(input: String, from start: String.Index) -> [Token] {
        var tokens: [Token] = []
        var current = skipWhitespace(in: input, from: input.index(after: start))
        let keyStart = current

        func isKeyTerminator(_ i: String.Index) -> Bool {
            let c = input[i]
            if c == ":" || c == "+" { return true }
            if c == "-" { return i > keyStart && input[input.index(before: i)].isWhitespace }
            return isOperatorBoundary(input, i)
        }

        while current < input.endIndex && !isKeyTerminator(current) {
            current = input.index(after: current)
        }

        let keyValue = String(input[keyStart..<current]).trimmingCharacters(in: .whitespaces)
        if !keyValue.isEmpty {
            tokens.append(Token(kind: .artifactKey, value: keyValue, range: start..<current))
        }

        if current < input.endIndex {
            let opChar = input[current]
            if opChar == ":" || opChar == "+" || opChar == "-" {
                let opStart = current
                current = input.index(after: current)
                tokens.append(Token(kind: .artifactOp, value: String(opChar), range: opStart..<current))

                current = skipWhitespace(in: input, from: current)

                // Value runs to the next operator that begins a word.
                let valueStart = current
                while current < input.endIndex && !isOperatorBoundary(input, current) {
                    current = input.index(after: current)
                }

                let rawValue = String(input[valueStart..<current]).trimmingCharacters(in: .whitespaces)
                if !rawValue.isEmpty {
                    let kind: Token.Kind = rawValue.lowercased() == "void" ? .void_ : .artifactValue
                    tokens.append(Token(kind: kind, value: rawValue, range: valueStart..<current))
                }
            }
        }

        if tokens.isEmpty {
            tokens.append(Token(kind: .artifactKey, value: "", range: start..<input.index(after: start)))
        }
        return tokens
    }

    private func skipWhitespace(in input: String, from start: String.Index) -> String.Index {
        var current = start
        while current < input.endIndex && input[current].isWhitespace {
            current = input.index(after: current)
        }
        return current
    }

    // MARK: - Artifact Command Resolution

    private func parseArtifactCommand(contactNames: [String], tokens: [Token]) -> ParsedCommand {
        guard let keyToken = tokens.first(where: { $0.kind == .artifactKey }), !keyToken.value.isEmpty else {
            return .invalid(reason: "A fact needs a name, e.g. > birthday: 3 March")
        }

        let opToken = tokens.first(where: { $0.kind == .artifactOp })
        let valueToken = tokens.first(where: { $0.kind == .artifactValue || $0.kind == .void_ })

        let key = keyToken.value
        let op = opToken?.value ?? ":"

        if valueToken?.kind == .void_ {
            return .deleteArtifact(contactNames: contactNames, key: key)
        }

        guard let value = valueToken?.value, !value.isEmpty else {
            return .invalid(reason: "Add a value after the \(op), e.g. > \(key): something")
        }

        switch op {
        case "+": return .appendArtifact(contactNames: contactNames, key: key, value: value, forceConvert: false)
        case "-": return .removeArtifact(contactNames: contactNames, key: key, value: value)
        default:  return .setArtifact(contactNames: contactNames, key: key, value: value)
        }
    }
}
