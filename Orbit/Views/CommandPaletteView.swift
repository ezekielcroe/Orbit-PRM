import SwiftUI
import SwiftData

// MARK: - CommandPaletteView
// The heart of Orbit's hybrid UI. A Spotlight/VS-Code-style command palette
// with real-time syntax highlighting and contextual autocomplete.
//
// Flow:
// 1. User types using operators (@, *, !, #, >, ^)
// 2. Tokenizer runs on every keystroke (debounced)
// 3. Autocomplete suggestions appear based on current token context
// 4. On submit, the parser resolves a ParsedCommand
// 5. CommandExecutor performs the action against SwiftData
//
// FIX 2: Autocomplete now inserts @"Name" for multi-word contact names.

struct CommandPaletteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CommandExecutor.self) private var executor

    @Binding var isPresented: Bool
    var onNavigateToContact: ((Contact) -> Void)?
    var onNavigateToConstellation: ((Constellation) -> Void)?

    @State private var inputText = ""
    @State private var tokens: [Token] = []
    @State private var suggestions: [CommandSuggestion] = []
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var debounceTask: Task<Void, Never>?
    
    @State private var pendingCommand: ParsedCommand?
    @State private var showConversionAlert = false

    @FocusState private var isInputFocused: Bool

    private let parser = CommandParser()

    // Fetch contacts and tags for autocomplete
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    @Query(sort: \Tag.name)
    private var tags: [Tag]

    @Query(sort: \Constellation.name)
    private var constellations: [Constellation]

    var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    // Scrollable content area above input
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer()
                            
                            if let message = resultMessage {
                                resultView(message: message)
                            } else if !suggestions.isEmpty {
                                suggestionList
                            } else {
                                syntaxHelp
                            }
                        }
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(maxHeight: .infinity)

                    Divider()

                    // Input area always visible and pinned to bottom
                    inputSection
                }
                .navigationTitle("Command Palette")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isPresented = false
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Execute", systemImage: "return") {
                            executeCommand()
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
                .onAppear {
                    isInputFocused = true
                }
                
                .alert("Convert to List?", isPresented: $showConversionAlert) {
                    Button("Convert") {
                        if let cmd = pendingCommand {
                            executeCommand(commandToExecute: cmd)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        pendingCommand = nil
                    }
                } message: {
                    Text("This artifact holds a single value. Converting it allows multiple items.")
                }
            }
        }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            if !tokens.isEmpty {
                highlightedTokensView
                    .padding(.horizontal, OrbitSpacing.md)
            }

            HStack(spacing: OrbitSpacing.sm) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("@contact !action #tag \"note\"", text: $inputText)
                    .font(OrbitTypography.commandInput)
                    .focused($isInputFocused)
                    .onSubmit { executeCommand() }
                    .onChange(of: inputText) { _, newValue in
                        debounceTokenize(newValue)
                    }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                        tokens = []
                        suggestions = []
                        resultMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(OrbitSpacing.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, OrbitSpacing.md)
            .padding(.top, OrbitSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OrbitSpacing.sm) {
                    operatorButtons
                }
                .padding(.horizontal, OrbitSpacing.md)
            }
            .padding(.bottom, OrbitSpacing.md)
        }
    }

    // MARK: - Operator Quick-Insert Buttons (Accessory Rail)

    @ViewBuilder
    private var operatorButtons: some View {
        Group {
            operatorButton("@", label: "Contact", color: OrbitColors.syntaxEntity)
            operatorButton("!", label: "Action", color: OrbitColors.syntaxImpulse)
            operatorButton("#", label: "Tag", color: OrbitColors.syntaxTag)
            operatorButton("*", label: "Group", color: OrbitColors.syntaxConstellation)
            operatorButton(">", label: "Artifact", color: OrbitColors.syntaxArtifact)
            operatorButton("^", label: "Time", color: OrbitColors.syntaxTime)
            operatorButton("\"", label: "Note", color: OrbitColors.syntaxQuote)
        }
    }

    private func operatorButton(_ op: String, label: String, color: Color) -> some View {
        Button {
            // Add a space before the operator if input doesn't end with one
            if !inputText.isEmpty && !inputText.hasSuffix(" ") {
                inputText += " "
            }
            inputText += op
            debounceTokenize(inputText)
        } label: {
            Text(op)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(minWidth: 32, minHeight: 28)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Token Highlighting

    private var highlightedTokensView: some View {
        // Build an AttributedString-like view from tokens
        HStack(spacing: 2) {
            ForEach(tokens) { token in
                Text(tokenDisplayText(token))
                    .font(OrbitTypography.caption)
                    .foregroundStyle(colorForToken(token))
            }
        }
    }

    private func tokenDisplayText(_ token: Token) -> String {
        switch token.kind {
        case .entity:
            // FIX 2: Show quoted form if name contains spaces
            if token.value.contains(" ") {
                return "@\"\(token.value)\""
            }
            return "@\(token.value)"
        case .impulse: return "!\(token.value)"
        case .tag: return "#\(token.value)"
        case .constellation: return "*\(token.value)"
        case .artifactKey: return ">\(token.value)"
        case .artifactOp: return token.value
        case .artifactValue: return token.value
        case .timeModifier: return "^\(token.value)"
        case .quotedText: return "\"\(token.value)\""
        case .text: return token.value
        case .void_: return "void"
        }
    }

    private func colorForToken(_ token: Token) -> Color {
        switch token.kind {
        case .entity: return OrbitColors.syntaxEntity
        case .impulse: return OrbitColors.syntaxImpulse
        case .tag: return OrbitColors.syntaxTag
        case .constellation: return OrbitColors.syntaxConstellation
        case .artifactKey, .artifactOp, .artifactValue: return OrbitColors.syntaxArtifact
        case .timeModifier: return OrbitColors.syntaxTime
        case .quotedText: return OrbitColors.syntaxQuote
        case .text: return OrbitColors.textSecondary
        case .void_: return OrbitColors.error
        }
    }

    // MARK: - Suggestions

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.reversed()) { suggestion in
                Button {
                    applySuggestion(suggestion)
                } label: {
                    Label(suggestion.label, systemImage: suggestion.icon)
                        .font(OrbitTypography.commandSuggestion)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OrbitSpacing.md)
                        .padding(.vertical, OrbitSpacing.sm)
                }
                .buttonStyle(.plain)

                if suggestion.id != suggestions.first?.id {
                    Divider().padding(.leading, OrbitSpacing.md)
                }
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
    }

    // MARK: - Syntax Help

    private var syntaxHelp: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            Text("SYNTAX")
                .font(OrbitTypography.captionMedium)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Group {
                syntaxHelpRow("@Sarah !Coffee", "Log a coffee with Sarah")
                syntaxHelpRow("@\"Sarah Connor\" !Coffee", "Multi-word names use quotes")
                syntaxHelpRow("@Connor !Coffee", "Substring match — finds Sarah Connor")
                syntaxHelpRow("@Tom > likes + Jazz", "Add Jazz to Tom's likes")
                syntaxHelpRow("@Tom > likes - Jazz", "Remove Jazz from Tom's likes")
                syntaxHelpRow("@Sarah !Call ^yesterday", "Log a call from yesterday")
                syntaxHelpRow("@Sarah !Meeting #Work \"Discussed merger\"", "Detailed log with tag and note")
                syntaxHelpRow("@Sarah *Family", "Add Sarah to Family constellation")
                syntaxHelpRow("@Sarah *-Family", "Remove Sarah from Family")
                syntaxHelpRow("*Family !Call #chat", "Log a call for everyone in Family")
                syntaxHelpRow("@Sarah", "Search contacts matching 'Sarah'")
                syntaxHelpRow("!undo", "Undo the last logged interaction")
            }
        }
        .padding(OrbitSpacing.md)
    }

    private func syntaxHelpRow(_ command: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            Text(command)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
            Text(description)
                .font(OrbitTypography.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, OrbitSpacing.xs)
    }

    // MARK: - Result Display

    private func resultView(message: String) -> some View {
        HStack(spacing: OrbitSpacing.sm) {
            Image(systemName: resultIsError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(resultIsError ? OrbitColors.error : OrbitColors.success)

            Text(message)
                .font(OrbitTypography.body)

            Spacer()
        }
        .padding(OrbitSpacing.md)
    }

    // MARK: - Tokenization & Autocomplete

    private func debounceTokenize(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            tokens = parser.tokenize(text)
            updateSuggestions()
        }
    }

    /// FIX 2: Helper to format a contact name for insertion.
    /// Wraps in quotes if name contains spaces.
    private func formattedEntityInsertion(for name: String) -> String {
        if name.contains(" ") {
            return "@\"\(name)\" "
        }
        return "@\(name) "
    }

    /// FIX 2: Helper to format a constellation name for insertion.
    private func formattedConstellationInsertion(for name: String, removal: Bool) -> String {
        let prefix = removal ? "*-" : "*"
        if name.contains(" ") {
            return "\(prefix)\"\(name)\" "
        }
        return "\(prefix)\(name) "
    }

    private func updateSuggestions() {
        suggestions = []

        // Find the last token being typed to determine context
        guard let lastToken = tokens.last else { return }

        switch lastToken.kind {
        case .entity:
            // Suggest matching contacts — substring match, ranked by match quality
            let query = lastToken.value.lowercased()
            let matches: [Contact]

            if query.isEmpty {
                matches = Array(contacts.prefix(6))
            } else {
                matches = contacts.filter { $0.searchableName.contains(query) }
            }

            // Rank: exact match first, then prefix, then substring-only
            let ranked = matches.sorted { a, b in
                let aRank = matchRank(a.searchableName, query: query)
                let bRank = matchRank(b.searchableName, query: query)
                if aRank != bRank { return aRank < bRank }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            suggestions = ranked.prefix(6).map { contact in
                // Show which part matched for substring hits
                let subtitle = substringMatchHint(contact.searchableName, query: query, displayName: contact.name)
                return CommandSuggestion(
                    icon: "person",
                    label: subtitle ?? contact.name,
                    insertion: formattedEntityInsertion(for: contact.name),
                    kind: .contact
                )
            }

        case .impulse:
            // Suggest common impulse types — substring match
            let query = lastToken.value.lowercased()
            let commonImpulses = ["Call", "Coffee", "Meal", "Message", "Meeting", "Play"]

            let matches: [String]
            if query.isEmpty {
                matches = commonImpulses
            } else {
                matches = commonImpulses.filter { $0.lowercased().contains(query) }
            }

            let ranked = matches.sorted { a, b in
                let aRank = matchRank(a.lowercased(), query: query)
                let bRank = matchRank(b.lowercased(), query: query)
                if aRank != bRank { return aRank < bRank }
                return a < b
            }

            suggestions = ranked.map { imp in
                CommandSuggestion(
                    icon: "bolt",
                    label: imp,
                    insertion: "!\(imp) ",
                    kind: .impulse
                )
            }

        case .tag:
            // Suggest existing tags — substring match
            let query = lastToken.value.lowercased()
            let matches: [Tag]

            if query.isEmpty {
                matches = Array(tags.prefix(6))
            } else {
                matches = tags.filter { $0.searchableName.contains(query) }
            }

            let ranked = matches.sorted { a, b in
                let aRank = matchRank(a.searchableName, query: query)
                let bRank = matchRank(b.searchableName, query: query)
                if aRank != bRank { return aRank < bRank }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            suggestions = ranked.prefix(6).map { tag in
                CommandSuggestion(
                    icon: "tag",
                    label: tag.name,
                    insertion: "#\(tag.name) ",
                    kind: .tag
                )
            }

        case .constellation:
            // Suggest existing constellations — substring match
            let rawValue = lastToken.value
            let isRemoval = rawValue.hasPrefix("-")
            let query = (isRemoval ? String(rawValue.dropFirst()) : rawValue).lowercased()

            let matches: [Constellation]
            if query.isEmpty {
                matches = Array(constellations.prefix(6))
            } else {
                matches = constellations.filter { $0.searchableName.contains(query) }
            }

            let ranked = matches.sorted { a, b in
                let aRank = matchRank(a.searchableName, query: query)
                let bRank = matchRank(b.searchableName, query: query)
                if aRank != bRank { return aRank < bRank }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            suggestions = ranked.prefix(6).map { constellation in
                CommandSuggestion(
                    icon: "star.circle",
                    label: (isRemoval ? "Remove from " : "") + constellation.name,
                    insertion: formattedConstellationInsertion(for: constellation.name, removal: isRemoval),
                    kind: .constellation
                )
            }

        case .artifactKey:
            // Suggest existing artifact keys — substring match
            if let entityToken = tokens.first(where: { $0.kind == .entity }),
               let contact = executor.findContact(named: entityToken.value, in: modelContext) {
                let query = lastToken.value.lowercased()
                let existingKeys = (contact.artifacts ?? []).map(\.key)

                let matches: [String]
                if query.isEmpty {
                    matches = existingKeys
                } else {
                    matches = existingKeys.filter { $0.lowercased().contains(query) }
                }

                let ranked = matches.sorted { a, b in
                    let aRank = matchRank(a.lowercased(), query: query)
                    let bRank = matchRank(b.lowercased(), query: query)
                    if aRank != bRank { return aRank < bRank }
                    return a < b
                }

                suggestions = ranked.map { key in
                    CommandSuggestion(
                        icon: "key",
                        label: key,
                        insertion: "> \(key): ",
                        kind: .artifactKey
                    )
                }
            }

        default:
            break
        }
    }
    
    /// Returns a rank for how well `candidate` matches `query`.
    /// Lower is better: 0 = exact, 1 = prefix, 2 = word-boundary substring, 3 = substring.
    private func matchRank(_ candidate: String, query: String) -> Int {
        guard !query.isEmpty else { return 3 }
        if candidate == query { return 0 }
        if candidate.hasPrefix(query) { return 1 }

        // Check if query matches at a word boundary (e.g., "connor" in "sarah connor")
        // This handles the common case of searching by last name or second word.
        let words = candidate.split(separator: " ")
        if words.dropFirst().contains(where: { $0.hasPrefix(query) }) {
            return 2
        }

            return 3
        }

        /// For substring-only matches, returns a hint showing the match context.
        /// e.g., if query is "con" and name is "Sarah Connor", returns "Sarah Connor"
        ///        (no change needed — name is clear enough)
        /// Returns nil for exact/prefix matches where the name alone is sufficient.
        private func substringMatchHint(_ searchable: String, query: String, displayName: String) -> String? {
            guard !query.isEmpty else { return nil }
            // If it's a prefix match, the name alone is clear
            if searchable.hasPrefix(query) { return nil }
            // For substring matches, the name is still clear since we show the full name.
            // But we could add a match indicator in the future if needed.
            return nil
        }

    private func applySuggestion(_ suggestion: CommandSuggestion) {
        // Replace the text from the last operator to the cursor with the suggestion
        switch suggestion.kind {
        case .contact:
            if let range = inputText.range(of: "@", options: .backwards) {
                inputText = String(inputText[inputText.startIndex..<range.lowerBound]) + suggestion.insertion
            }
        case .impulse:
            if let range = inputText.range(of: "!", options: .backwards) {
                inputText = String(inputText[inputText.startIndex..<range.lowerBound]) + suggestion.insertion
            }
        case .tag:
            if let range = inputText.range(of: "#", options: .backwards) {
                inputText = String(inputText[inputText.startIndex..<range.lowerBound]) + suggestion.insertion
            }
        case .constellation:
            if let range = inputText.range(of: "*", options: .backwards) {
                inputText = String(inputText[inputText.startIndex..<range.lowerBound]) + suggestion.insertion
            }
        case .artifactKey:
            if let range = inputText.range(of: ">", options: .backwards) {
                inputText = String(inputText[inputText.startIndex..<range.lowerBound]) + suggestion.insertion
            }
        case .command:
            inputText = suggestion.insertion
        }

        suggestions = []
        debounceTokenize(inputText)
    }

    // MARK: - Command Execution

    private func executeCommand(commandToExecute: ParsedCommand? = nil) {
        let command = commandToExecute ?? parser.parse(inputText)

        // 1. Handle Contact Navigation
        if case .searchContact(let name, _) = command {
            let query = name.lowercased()
            // Bypass strict executor ambiguity. Grab the exact match, prefix match, or substring match.
            if let contact = contacts.first(where: { $0.searchableName == query }) ??
                             contacts.first(where: { $0.searchableName.hasPrefix(query) }) ??
                             contacts.first(where: { $0.searchableName.contains(query) }) {
                onNavigateToContact?(contact)
                isPresented = false
            } else {
                resultMessage = "Contact '\(name)' not found."
                resultIsError = true
            }
            return
        }
        
        // 2. NEW: Handle Constellation Navigation
        if case .searchConstellation(let name) = command {
            let query = name.lowercased()
            if let constellation = constellations.first(where: { $0.searchableName == query }) ??
                                   constellations.first(where: { $0.searchableName.hasPrefix(query) }) ??
                                   constellations.first(where: { $0.searchableName.contains(query) }) {
                onNavigateToConstellation?(constellation)
                isPresented = false
            } else {
                resultMessage = "Constellation '\(name)' not found."
                resultIsError = true
            }
            return
        }

        let result = executor.execute(command, in: modelContext)
            
            if let promptCommand = result.requiresConversionPrompt {
                pendingCommand = promptCommand
                showConversionAlert = true
                return
            }

            resultMessage = result.message
            resultIsError = !result.success

        if result.success {
            // If there's an affected contact, offer navigation
            if let contact = result.affectedContact {
                // Delay to show the result, then navigate
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onNavigateToContact?(contact)
                    isPresented = false
                }
            }

            // Clear input for next command
            inputText = ""
            tokens = []
            suggestions = []
        }
    }
}
