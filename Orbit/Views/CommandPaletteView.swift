import SwiftUI
import SwiftData

// MARK: - CommandPaletteView
// Type what happened in plain words — "Coffee with Sarah yesterday, talked
// about her move" — and the palette shows what it understood before anything
// is saved. Ambiguous names get a picker, unknown names can be created inline,
// and the palette stays open after logging so several things can be entered in
// a row. The @ ! # * > ^ syntax still works for people who prefer it.
//
// Flow: input → CaptureParser → CaptureIntent → resolve names via OrbitStore
//       → preview → commit through OrbitStore (one undo step per commit).

struct CommandPaletteView: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var seed: String = ""

    @State private var inputText = ""
    @State private var intent: CaptureIntent = .empty
    @State private var tokens: [Token] = []
    @State private var suggestions: [CommandSuggestion] = []
    @State private var parseTask: Task<Void, Never>?

    // User choices that refine the parsed draft. Keyed by the typed name.
    @State private var chosen: [String: Contact] = [:]
    @State private var excluded: Set<String> = []
    @State private var extraPeople: [Contact] = []
    @State private var actionOverride: String?
    @State private var dateOverride: Date?
    @State private var chosenGroup: Constellation?

    @State private var lastResult: (text: String, canUndo: Bool, isError: Bool)?
    @State private var pendingConversion: ParsedCommand?
    @State private var showPicker = false
    @State private var showSyntax = false

    @FocusState private var inputFocused: Bool

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    @Query(sort: \Constellation.name)
    private var groups: [Constellation]

    @Query(sort: \Tag.name)
    private var tags: [Tag]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputField
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                        if let lastResult { resultBanner(lastResult) }
                        if !suggestions.isEmpty { suggestionList }
                        previewSection
                    }
                    .padding(OrbitSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Log or find")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !seed.isEmpty, inputText.isEmpty {
                    inputText = seed
                    reparse(immediately: true)
                }
                inputFocused = true
            }
            .sheet(isPresented: $showPicker) {
                ContactPickerSheet(selection: $extraPeople)
            }
            .alert("Turn into a list?", isPresented: Binding(get: { pendingConversion != nil }, set: { if !$0 { pendingConversion = nil } })) {
                Button("Make it a list") {
                    if let cmd = pendingConversion { runCommand(cmd) }
                    pendingConversion = nil
                }
                Button("Cancel", role: .cancel) { pendingConversion = nil }
            } message: {
                Text("This fact holds a single value. Making it a list keeps that value and adds the new one.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 460)
        #endif
    }

    // MARK: - Input

    private var inputField: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            HStack(spacing: OrbitSpacing.sm) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(.secondary)
                TextField("Coffee with Sarah yesterday, talked about her move", text: $inputText)
                    .font(OrbitTypography.body)
                    .focused($inputFocused)
                    .onSubmit(commit)
                    .onChange(of: inputText) { _, _ in
                        lastResultFadeOnEdit()
                        reparse()
                    }
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                if !inputText.isEmpty {
                    Button { clearInput() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            if isSigil, !tokens.isEmpty {
                highlightedTokens
            }
        }
        .padding(OrbitSpacing.md)
    }

    private var isSigil: Bool { CommandParser.looksLikeSigilSyntax(inputText) }

    private var highlightedTokens: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tokens) { token in
                    Text(tokenDisplayText(token))
                        .font(OrbitTypography.caption.monospaced())
                        .foregroundStyle(colorForToken(token))
                }
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        switch intent {
        case .empty:
            helpSection
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(OrbitTypography.body)
                .foregroundStyle(OrbitColors.warning)
            syntaxDisclosure
        case .undo:
            actionCard {
                Text(store.undoLabel.map { "Undo “\($0)”" } ?? "Nothing to undo")
                    .font(OrbitTypography.bodyMedium)
            } button: {
                Button("Undo") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canUndo)
            }
        case .openGroup(let name):
            groupOpenPreview(name)
        case .command(let command):
            commandPreview(command)
        case .log(let draft):
            logPreview(draft)
        }
    }

    // Log preview: who / what / when / note / tags, each fixable in place.
    @ViewBuilder
    private func logPreview(_ draft: CaptureDraft) -> some View {
        let plan = logPlan(for: draft)
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            previewRow("With") {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    if let groupName = draft.group {
                        groupChip(groupName)
                    }
                    ForEach(draft.people, id: \.self) { name in
                        personChip(for: name)
                    }
                    ForEach(extraPeople) { person in
                        PersonChip(name: person.name, removable: true) {
                            extraPeople.removeAll { $0.id == person.id }
                        }
                    }
                    Button { showPicker = true } label: {
                        Label(draft.hasTarget || !extraPeople.isEmpty ? "Add" : "Choose someone", systemImage: "plus")
                            .font(OrbitTypography.captionMedium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            previewRow("What") {
                VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                    if let action = plan.action {
                        Text(action).font(OrbitTypography.bodyMedium)
                    } else {
                        Text("What did you do? Pick one or type it.")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(store.actionSuggestions(limit: 7), id: \.self) { suggestion in
                            Button(suggestion) { actionOverride = suggestion }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(plan.action?.lowercased() == suggestion.lowercased() ? .accentColor : .secondary)
                        }
                    }
                }
            }

            previewRow("When") {
                HStack {
                    DatePicker("When", selection: Binding(
                        get: { dateOverride ?? draft.date ?? Date() },
                        set: { dateOverride = $0 }
                    ), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    if draft.date == nil && dateOverride == nil {
                        Text("now").font(OrbitTypography.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            if !draft.note.isEmpty {
                previewRow("Note") {
                    Text(draft.note)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                }
            }

            if !draft.tags.isEmpty {
                previewRow("Tags") {
                    Text(draft.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.caption)
                        .foregroundStyle(OrbitColors.syntaxTag)
                }
            }

            if let blocker = plan.blocker {
                Text(blocker)
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: OrbitSpacing.sm) {
                if let openable = plan.openable {
                    if plan.isReady {
                        Button("Open \(openable.name)") { router.open(openable); dismiss() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Open \(openable.name)") { router.open(openable); dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if plan.isReady || plan.openable == nil {
                    Button(plan.buttonTitle) { commit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!plan.isReady)
                }
                Spacer()
            }
            .padding(.top, OrbitSpacing.sm)
        }
    }

    @ViewBuilder
    private func personChip(for name: String) -> some View {
        let key = name.lowercased()
        if excluded.contains(key) {
            EmptyView()
        } else if let picked = chosen[key] {
            PersonChip(name: picked.name, removable: true) { excluded.insert(key) }
        } else {
            switch store.resolveContact(name) {
            case .resolved(let contact):
                PersonChip(name: contact.name, removable: true) { excluded.insert(key) }
            case .ambiguous(let candidates):
                Menu {
                    ForEach(candidates) { c in
                        Button(c.name) { chosen[key] = c }
                    }
                    Divider()
                    Button("Remove", role: .destructive) { excluded.insert(key) }
                } label: {
                    Label("Which \(name)?", systemImage: "questionmark.circle")
                        .font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
            case .notFound:
                Menu {
                    Text("“\(Self.titleCased(name))” will be added as a new person")
                    Button("Choose someone else…") {
                        excluded.insert(key)
                        showPicker = true
                    }
                    Button("Remove", role: .destructive) { excluded.insert(key) }
                } label: {
                    Label("New: \(name)", systemImage: "person.badge.plus")
                        .font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func groupChip(_ name: String) -> some View {
        if let group = chosenGroup {
            PersonChip(name: "✦ \(group.name)", removable: true) { chosenGroup = nil }
        } else {
            switch store.resolveGroup(name) {
            case .resolved(let group):
                PersonChip(name: "✦ \(group.name)")
            case .ambiguous(let candidates):
                Menu {
                    ForEach(candidates) { g in Button(g.name) { chosenGroup = g } }
                } label: {
                    Label("Which group?", systemImage: "questionmark.circle").font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button).buttonStyle(.bordered).tint(.orange).controlSize(.small)
            case .notFound:
                Label("No group “\(name)”", systemImage: "exclamationmark.circle")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(OrbitColors.warning)
            }
        }
    }

    // MARK: Log plan

    private struct LogPlan {
        var people: [Contact] = []
        var toCreate: [String] = []
        var group: Constellation?
        var action: String?
        var blocker: String?
        /// Exactly one person and nothing else typed → offer to open them.
        var openable: Contact?

        var isReady: Bool { blocker == nil && action != nil && (group != nil || !people.isEmpty || !toCreate.isEmpty) }

        var buttonTitle: String {
            guard let action else { return "Log" }
            let count = people.count + toCreate.count
            let who: String
            if let group { who = "✦ \(group.name)" }
            else if count == 1 { who = people.first?.name ?? toCreate.first ?? "" }
            else { who = "\(count) people" }
            return toCreate.isEmpty ? "Log \(action) with \(who)" : "Create & log \(action) with \(who)"
        }
    }

    private func logPlan(for draft: CaptureDraft) -> LogPlan {
        var plan = LogPlan()
        plan.action = actionOverride ?? draft.action

        if let groupName = draft.group {
            if let chosenGroup { plan.group = chosenGroup }
            else if case .resolved(let g) = store.resolveGroup(groupName) { plan.group = g }
            else { plan.blocker = "Pick which group this was." }
        }

        var unresolved: [String] = []
        for name in draft.people {
            let key = name.lowercased()
            guard !excluded.contains(key) else { continue }
            if let picked = chosen[key] { plan.people.append(picked); continue }
            switch store.resolveContact(name) {
            case .resolved(let c): plan.people.append(c)
            case .ambiguous: unresolved.append(name)
            case .notFound(let n): plan.toCreate.append(Self.titleCased(n))
            }
        }
        for extra in extraPeople where !plan.people.contains(where: { $0.id == extra.id }) {
            plan.people.append(extra)
        }

        if !unresolved.isEmpty {
            plan.blocker = "Pick which \(unresolved.joined(separator: ", ")) you mean."
        } else if plan.group == nil && plan.people.isEmpty && plan.toCreate.isEmpty && draft.group == nil {
            plan.blocker = "Who was this with?"
        }

        if plan.people.count == 1, plan.toCreate.isEmpty, plan.group == nil,
           actionOverride == nil, draft.action == nil, draft.note.isEmpty, draft.tags.isEmpty {
            plan.openable = plan.people.first
        }
        return plan
    }

    // MARK: Command preview

    @ViewBuilder
    private func commandPreview(_ command: ParsedCommand) -> some View {
        let resolution = resolveAll(command.contactNames)
        actionCard {
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(command.contactNames, id: \.self) { name in personChip(for: name) }
                }
                Text(CommandExecutor.describe(command, people: store.names(resolution.contacts)))
                    .font(OrbitTypography.bodyMedium)
                if let blocker = resolution.blocker {
                    Text(blocker).font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }
        } button: {
            Button("Do it") { commit() }
                .buttonStyle(.borderedProminent)
                .disabled(resolution.blocker != nil)
        }
    }

    private func resolveAll(_ names: [String], includeArchived: Bool = true) -> (contacts: [Contact], blocker: String?) {
        var result: [Contact] = []
        var missing: [String] = []
        var unclear: [String] = []
        for name in names {
            let key = name.lowercased()
            if excluded.contains(key) { continue }
            if let picked = chosen[key] { result.append(picked); continue }
            switch store.resolveContact(name, includeArchived: includeArchived) {
            case .resolved(let c): result.append(c)
            case .ambiguous: unclear.append(name)
            case .notFound(let n): missing.append(n)
            }
        }
        if !missing.isEmpty { return (result, "No one called \(missing.joined(separator: ", ")). Add them first, or log with them in plain words.") }
        if !unclear.isEmpty { return (result, "Pick which \(unclear.joined(separator: ", ")) you mean.") }
        if result.isEmpty { return (result, "Who is this for?") }
        return (result, nil)
    }

    @ViewBuilder
    private func groupOpenPreview(_ name: String) -> some View {
        switch store.resolveGroup(name) {
        case .resolved(let group):
            actionCard {
                Text("✦ \(group.name)").font(OrbitTypography.bodyMedium)
            } button: {
                Button("Open") { router.open(group); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .ambiguous(let candidates):
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                Text("Which group?").font(OrbitTypography.caption).foregroundStyle(.secondary)
                ForEach(candidates) { g in
                    Button("✦ \(g.name)") { router.open(g); dismiss() }
                }
            }
        case .notFound:
            Text("No group called “\(name)”. Add people to one with @Name *\(name).")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Commit

    private func commit() {
        switch intent {
        case .empty, .invalid, .openGroup:
            if case .openGroup(let name) = intent, case .resolved(let g) = store.resolveGroup(name) {
                router.open(g); dismiss()
            }
        case .undo:
            store.undo()
            finish(text: "Undone", canUndo: false)
        case .command(let command):
            runCommand(command)
        case .log(let draft):
            let plan = logPlan(for: draft)
            if !plan.isReady {
                if let openable = plan.openable { router.open(openable); dismiss() }
                return
            }
            guard let action = plan.action else { return }
            let date = dateOverride ?? draft.date ?? Date()
            let title = plan.buttonTitle.replacingOccurrences(of: "Create & log", with: "Logged").replacingOccurrences(of: "Log ", with: "Logged ")
            store.grouped("Log \(action)", message: title) {
                if let group = plan.group {
                    store.log(group: group, action: action, note: draft.note, tags: draft.tags, date: date)
                } else {
                    var people = plan.people
                    for name in plan.toCreate {
                        people.append(store.createContact(name: name, orbit: 2, closenessConfirmed: false))
                    }
                    store.log(contacts: people, action: action, note: draft.note, tags: draft.tags, date: date)
                }
            }
            finish(text: title, canUndo: true)
        }
    }

    private func runCommand(_ command: ParsedCommand) {
        let resolution = resolveAll(command.contactNames)
        guard resolution.blocker == nil || command.contactNames.isEmpty else { return }
        switch CommandExecutor.execute(command, contacts: resolution.contacts, store: store) {
        case .done:
            finish(text: store.toast?.text ?? "Done", canUndo: store.canUndo)
        case .needsListConversion(let retry):
            pendingConversion = retry
        case .failed(let reason):
            lastResult = (reason, false, true)
        }
    }

    private func finish(text: String, canUndo: Bool) {
        lastResult = (text, canUndo, false)
        clearInput()
        inputFocused = true
    }

    private func clearInput() {
        inputText = ""
        intent = .empty
        tokens = []
        suggestions = []
        chosen = [:]
        excluded = []
        extraPeople = []
        actionOverride = nil
        dateOverride = nil
        chosenGroup = nil
    }

    private func lastResultFadeOnEdit() {
        if !inputText.isEmpty, lastResult?.isError == true { lastResult = nil }
    }

    // MARK: - Parsing & suggestions

    private func reparse(immediately: Bool = false) {
        parseTask?.cancel()
        let text = inputText
        parseTask = Task { @MainActor in
            if !immediately { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            let parser = CaptureParser(
                people: contacts.map(\.name),
                groups: groups.map(\.name),
                actions: store.knownActions()
            )
            intent = parser.parse(text)
            tokens = CommandParser.looksLikeSigilSyntax(text) ? CommandParser(knownNames: contacts.map(\.name)).tokenize(text) : []
            updateSuggestions(for: text)
        }
    }

    private func updateSuggestions(for text: String) {
        suggestions = []
        if CommandParser.looksLikeSigilSyntax(text) {
            sigilSuggestions(text)
        } else {
            plainSuggestions(text)
        }
    }

    /// Plain mode: complete the last word to a full contact name.
    private func plainSuggestions(_ text: String) {
        guard !text.hasSuffix(" "), let lastWord = text.split(separator: " ").last, lastWord.count >= 2 else { return }
        let word = String(lastWord).trimmingCharacters(in: .punctuationCharacters)
        guard word.count >= 2 else { return }
        let candidates = contacts.map { NameCandidate(id: $0.id, name: $0.name) }
        let ranked = NameMatcher.ranked(word, in: candidates, limit: 4)
            .filter { $0.name.lowercased() != word.lowercased() && $0.name.lowercased().split(separator: " ").contains(where: { $0.hasPrefix(word.lowercased()) }) }
        suggestions = ranked.map {
            CommandSuggestion(icon: "person", label: $0.name, insertion: $0.name + " ", kind: .contact)
        }
    }

    private func sigilSuggestions(_ text: String) {
        guard let last = tokens.last, last.range.upperBound == text.endIndex else { return }
        let query = last.value.lowercased()

        switch last.kind {
        case .entity:
            let candidates = contacts.map { NameCandidate(id: $0.id, name: $0.name) }
            suggestions = NameMatcher.ranked(query, in: candidates).map {
                CommandSuggestion(icon: "person", label: $0.name, insertion: formattedEntity($0.name), kind: .contact)
            }
        case .impulse:
            let pool = store.actionSuggestions(limit: 12) + ["archive", "restore"]
            suggestions = pool
                .filter { query.isEmpty || $0.lowercased().hasPrefix(query) }
                .prefix(6)
                .map { CommandSuggestion(icon: "bolt", label: $0, insertion: "!\($0) ", kind: .impulse) }
        case .tag:
            suggestions = tags
                .filter { query.isEmpty || $0.searchableName.contains(query) }
                .prefix(6)
                .map { CommandSuggestion(icon: "tag", label: $0.name, insertion: "#\($0.name) ", kind: .tag) }
        case .constellation:
            let removal = last.value.hasPrefix("-")
            let q = removal ? String(query.dropFirst()) : query
            let candidates = groups.map { NameCandidate(id: $0.id, name: $0.name) }
            suggestions = NameMatcher.ranked(q, in: candidates).map {
                let name = $0.name.contains(" ") ? "\"\($0.name)\"" : $0.name
                return CommandSuggestion(icon: "star.circle", label: (removal ? "Remove from " : "") + $0.name, insertion: "*\(removal ? "-" : "")\(name) ", kind: .constellation)
            }
        case .artifactKey:
            if let entity = tokens.first(where: { $0.kind == .entity }),
               case .resolved(let contact) = store.resolveContact(entity.value) {
                suggestions = (contact.artifacts ?? [])
                    .map(\.key)
                    .filter { query.isEmpty || $0.lowercased().contains(query) }
                    .sorted()
                    .prefix(6)
                    .map { CommandSuggestion(icon: "key", label: $0, insertion: "> \($0): ", kind: .artifactKey) }
            }
        default:
            break
        }
    }

    private func formattedEntity(_ name: String) -> String {
        name.contains(" ") ? "@\"\(name)\" " : "@\(name) "
    }

    /// Replace the token (sigil mode) or word (plain mode) being typed.
    private func apply(_ suggestion: CommandSuggestion) {
        // Re-tokenize the current text so the range can't be stale.
        let fresh = isSigil ? CommandParser(knownNames: contacts.map(\.name)).tokenize(inputText) : []
        if let last = fresh.last, last.range.upperBound == inputText.endIndex {
            inputText.replaceSubrange(last.range, with: suggestion.insertion)
        } else if let space = inputText.lastIndex(of: " ") {
            inputText = String(inputText[...space]) + suggestion.insertion
        } else {
            inputText = suggestion.insertion
        }
        suggestions = []
        reparse(immediately: true)
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button { apply(suggestion) } label: {
                    Label(suggestion.label, systemImage: suggestion.icon)
                        .font(OrbitTypography.commandSuggestion)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, OrbitSpacing.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if suggestion.id != suggestions.last?.id { Divider() }
            }
        }
    }

    // MARK: - Help

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            Text("Just type what happened.")
                .font(OrbitTypography.bodyMedium)
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                example("Coffee with Sarah yesterday, talked about her move")
                example("Called Mum about her surgery #health")
                example("Dinner with Sam, Alex and Jo on Friday")
                example("Drinks with the Book Club last night")
                example("Sarah", note: "open someone's page")
            }
            syntaxDisclosure
        }
    }

    private func example(_ text: String, note: String? = nil) -> some View {
        Button {
            inputText = text
            reparse(immediately: true)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(OrbitTypography.body).foregroundStyle(.primary)
                if let note { Text(note).font(OrbitTypography.footnote).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var syntaxDisclosure: some View {
        DisclosureGroup("Shortcut syntax", isExpanded: $showSyntax) {
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                syntaxRow("@Sarah !Coffee \"note\" ^yesterday", "Log with exact syntax")
                syntaxRow("@Tom > birthday: 3 March", "Set a fact")
                syntaxRow("@Tom > likes + Jazz  ·  > likes - Jazz", "Add to / remove from a list fact")
                syntaxRow("@Tom > likes: void", "Delete a fact")
                syntaxRow("@Sarah *Family  ·  @Sarah *-Family", "Add to / remove from a group")
                syntaxRow("*Family !Call", "Log for everyone in a group")
                syntaxRow("@Sam !archive  ·  !restore", "Archive or restore")
                syntaxRow("^3d  ^2w  ^last-monday", "Times")
                syntaxRow("!undo", "Undo the last change")
            }
            .padding(.top, OrbitSpacing.sm)
        }
        .font(OrbitTypography.caption)
        .foregroundStyle(.secondary)
    }

    private func syntaxRow(_ command: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(command).font(.system(size: 13, design: .monospaced)).foregroundStyle(.primary)
            Text(description).font(OrbitTypography.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - Building blocks

    private func previewRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Text(label.uppercased())
                .font(OrbitTypography.footnote)
                .tracking(1.2)
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func actionCard<Content: View, ButtonContent: View>(@ViewBuilder content: () -> Content, @ViewBuilder button: () -> ButtonContent) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            content()
            HStack { button(); Spacer() }
        }
    }

    private func resultBanner(_ result: (text: String, canUndo: Bool, isError: Bool)) -> some View {
        HStack(spacing: OrbitSpacing.sm) {
            Image(systemName: result.isError ? "exclamationmark.triangle" : "checkmark.circle.fill")
                .foregroundStyle(result.isError ? OrbitColors.warning : OrbitColors.success)
            Text(result.text).font(OrbitTypography.body)
            Spacer()
            if result.canUndo && store.canUndo {
                Button("Undo") {
                    store.undo()
                    lastResult = ("Undone", false, false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(OrbitSpacing.sm)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Token display

    private func tokenDisplayText(_ token: Token) -> String {
        switch token.kind {
        case .entity: return token.value.contains(" ") ? "@\"\(token.value)\"" : "@\(token.value)"
        case .impulse: return "!\(token.value)"
        case .tag: return "#\(token.value)"
        case .constellation: return "*\(token.value)"
        case .artifactKey: return ">\(token.value)"
        case .artifactOp, .artifactValue, .text: return token.value
        case .timeModifier: return "^\(token.value)"
        case .quotedText: return "\"\(token.value)\""
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

    private static func titleCased(_ name: String) -> String {
        name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
