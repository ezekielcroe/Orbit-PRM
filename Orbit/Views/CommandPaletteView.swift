import SwiftUI
import SwiftData

// MARK: - CommandPaletteView
// The heart of Orbit's hybrid UI. A Spotlight/VS-Code-style command palette
// with real-time syntax highlighting and contextual autocomplete.
//
// Flow:
// 1. User types using operators (@, !, #, >, ^)
// 2. Tokenizer runs on every keystroke (debounced)
// 3. Autocomplete suggestions appear based on current token context
// 4. On submit, the parser resolves a ParsedCommand
// 5. CommandExecutor performs the action against SwiftData

struct CommandPaletteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CommandExecutor.self) private var executor

    @Binding var isPresented: Bool
    var onNavigateToContact: ((Contact) -> Void)?

    @State private var inputText = ""
    @State private var tokens: [Token] = []
    @State private var suggestions: [CommandSuggestion] = []
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var debounceTask: Task<Void, Never>?

    @FocusState private var isInputFocused: Bool

    private let parser = CommandParser()

    // Fetch contacts and tags for autocomplete
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    @Query(sort: \Tag.name)
    private var tags: [Tag]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Input area
                inputSection

                Divider()

                // Suggestions / result
                if let message = resultMessage {
                    resultView(message: message)
                } else if !suggestions.isEmpty {
                    suggestionList
                } else {
                    syntaxHelp
                }

                Spacer()
            }
            .navigationTitle("Command Palette")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    operatorButtons
                }
            }
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
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            // Token-highlighted display of parsed input
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

            #if os(macOS)
            // Operator buttons as a toolbar on macOS too
            HStack(spacing: OrbitSpacing.sm) {
                operatorButtons
            }
            .padding(.horizontal, OrbitSpacing.md)
            #endif
        }
    }

    // MARK: - Operator Quick-Insert Buttons (Accessory Rail)

    @ViewBuilder
    private var operatorButtons: some View {
        Group {
            operatorButton("@", label: "Contact", color: OrbitColors.syntaxEntity)
            operatorButton("!", label: "Action", color: OrbitColors.syntaxImpulse)
            operatorButton("#", label: "Tag", color: OrbitColors.syntaxTag)
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
        case .entity: return "@\(token.value)"
        case .impulse: return "!\(token.value)"
        case .tag: return "#\(token.value)"
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
        case .artifactKey, .artifactOp, .artifactValue: return OrbitColors.syntaxArtifact
        case .timeModifier: return OrbitColors.syntaxTime
        case .quotedText: return OrbitColors.syntaxQuote
        case .text: return OrbitColors.textSecondary
        case .void_: return OrbitColors.error
        }
    }

    // MARK: - Suggestions

    private var suggestionList: some View {
        List {
            ForEach(suggestions) { suggestion in
                Button {
                    applySuggestion(suggestion)
                } label: {
                    Label(suggestion.label, systemImage: suggestion.icon)
                        .font(OrbitTypography.commandSuggestion)
                }
            }
        }
        .listStyle(.plain)
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
                syntaxHelpRow("@Tom > likes + Jazz", "Add Jazz to Tom's likes")
                syntaxHelpRow("@Tom > wife: Elena", "Set Tom's wife to Elena")
                syntaxHelpRow("@Sarah !Call ^yesterday", "Log a call from yesterday")
                syntaxHelpRow("@Sarah !Meeting #Work \"Discussed merger\"", "Detailed log with tag and note")
                syntaxHelpRow("@Sarah", "Open Sarah's contact page")
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

    private func updateSuggestions() {
        suggestions = []

        // Find the last token being typed to determine context
        guard let lastToken = tokens.last else { return }

        switch lastToken.kind {
        case .entity:
            // Suggest matching contacts
            let prefix = lastToken.value.lowercased()
            suggestions = contacts
                .filter { $0.searchableName.hasPrefix(prefix) || prefix.isEmpty }
                .prefix(6)
                .map { contact in
                    CommandSuggestion(
                        icon: "person",
                        label: contact.name,
                        insertion: "@\(contact.name) ",
                        kind: .contact
                    )
                }

        case .impulse:
            // Suggest common impulse types
            let prefix = lastToken.value.lowercased()
            let commonImpulses = ["Call", "Coffee", "Dinner", "Text", "Meeting", "Lunch", "Walk", "Video Call", "Email"]
            suggestions = commonImpulses
                .filter { $0.lowercased().hasPrefix(prefix) || prefix.isEmpty }
                .map { imp in
                    CommandSuggestion(
                        icon: "bolt",
                        label: imp,
                        insertion: "!\(imp) ",
                        kind: .impulse
                    )
                }

        case .tag:
            // Suggest existing tags
            let prefix = lastToken.value.lowercased()
            suggestions = tags
                .filter { $0.searchableName.hasPrefix(prefix) || prefix.isEmpty }
                .prefix(6)
                .map { tag in
                    CommandSuggestion(
                        icon: "tag",
                        label: tag.name,
                        insertion: "#\(tag.name) ",
                        kind: .tag
                    )
                }

        case .artifactKey:
            // Suggest existing artifact keys for the selected contact
            if let entityToken = tokens.first(where: { $0.kind == .entity }),
               let contact = executor.findContact(named: entityToken.value, in: modelContext) {
                let prefix = lastToken.value.lowercased()
                let existingKeys = contact.artifacts.map(\.key)
                suggestions = existingKeys
                    .filter { $0.lowercased().hasPrefix(prefix) || prefix.isEmpty }
                    .map { key in
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

    private func applySuggestion(_ suggestion: CommandSuggestion) {
        // Replace the text from the last operator to the cursor with the suggestion
        // For simplicity in Phase 1, we replace based on the suggestion kind
        switch suggestion.kind {
        case .contact:
            // Replace everything up to and including the @token
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

    private func executeCommand() {
        let command = parser.parse(inputText)

        // FIX 1: Handle navigation directly in the UI layer.
        // The executor is for data mutations; navigation is a UI concern.
        if case .searchContact(let name, _) = command {
            if let contact = executor.findContact(named: name, in: modelContext) {
                onNavigateToContact?(contact)
                isPresented = false
            } else {
                resultMessage = "Contact '\(name)' not found."
                resultIsError = true
            }
            return
        }

        let result = executor.execute(command, in: modelContext)

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
