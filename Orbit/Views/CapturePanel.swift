import SwiftUI
import SwiftData

// MARK: - CapturePanel
// The capture surface: type what happened in plain words, see what Orbit
// understood, fix anything in place, save. Used in two places:
//   • `.sheet`  — the ⌘K palette on iPad and Mac (input on top)
//   • `.docked` — the bottom of the Log tab (input at the bottom, by the thumb)
//
// Flow: text → CaptureParser (or Apple Intelligence on "Re-read") →
//       CaptureIntent → names resolved via OrbitStore → preview → commit.
// Corrections teach the parser: picking who "my sister" or "Mama" is, or
// which group "siblings" means, is remembered for next time.

struct CapturePanel: View {
    enum Style { case sheet, docked }

    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router

    var style: Style = .sheet
    var seed: String = ""
    /// Called after opening a contact or group, so a sheet can close itself.
    var onOpen: () -> Void = {}

    @State private var inputText = ""
    @State private var intent: CaptureIntent = .empty
    @State private var tokens: [Token] = []
    @State private var suggestions: [CommandSuggestion] = []
    @State private var parseTask: Task<Void, Never>?

    // Corrections, keyed by the phrase as parsed (lowercased).
    @State private var picked: [String: [Contact]] = [:]
    @State private var excluded: Set<String> = []
    @State private var extraPeople: [Contact] = []
    @State private var actionOverride: String?
    @State private var dateOverride: Date?
    @State private var chosenGroup: Constellation?
    @State private var acceptedSuggestions: Set<FactDraft> = []
    @State private var rejectedFacts: Set<FactDraft> = []

    // Re-read with Apple Intelligence
    @State private var reader: (any CaptureReader)? = CaptureReaders.makeDefault()
    @State private var modelIntent: CaptureIntent?
    @State private var isReading = false
    @State private var readerMessage: String?

    @State private var lastResult: (text: String, canUndo: Bool, isError: Bool)?
    @State private var pendingConversion: ParsedCommand?
    @State private var pickTarget: PickTarget?
    @State private var lastPickKey: String?
    @State private var contentHeight: CGFloat = 0
    @State private var pickSelection: [Contact] = []
    @State private var showExtraPicker = false
    @State private var showSyntax = false

    @FocusState private var inputFocused: Bool

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]
    @Query(sort: \Constellation.name)
    private var groups: [Constellation]
    @Query(sort: \Tag.name)
    private var tags: [Tag]

    private struct PickTarget: Identifiable {
        let id: String        // the phrase key
        let title: String
        let multiple: Bool
    }

    /// The intent being previewed: Apple Intelligence's reading if requested.
    private var current: CaptureIntent { modelIntent ?? intent }

    // MARK: - Body

    var body: some View {
        Group {
            switch style {
            case .sheet:
                VStack(spacing: 0) {
                    inputField
                    Divider()
                    ScrollView { panelContent.padding(OrbitSpacing.md) }
                }
            case .docked:
                VStack(spacing: 0) {
                    if hasPanelContent {
                        ScrollView {
                            panelContent
                                .padding(OrbitSpacing.md)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                                })
                        }
                        .frame(height: min(max(contentHeight, 44), 340))
                        .onPreferenceChange(PanelHeightKey.self) { contentHeight = $0 }
                        Divider()
                    }
                    inputField
                }
                .background(.bar)
            }
        }
        .onAppear {
            if !seed.isEmpty, inputText.isEmpty {
                inputText = seed
                reparse(immediately: true)
            }
            if style == .sheet || router.tab == .log { inputFocused = true }
        }
        .onChange(of: router.tab) { _, tab in
            if style == .docked && tab == .log { inputFocused = true }
        }
        .sheet(isPresented: $showExtraPicker) {
            ContactPickerSheet(selection: $extraPeople)
        }
        .sheet(item: $pickTarget, onDismiss: applyPick) { target in
            ContactPickerSheet(selection: $pickSelection, allowsMultiple: target.multiple, title: target.title)
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

    private var hasPanelContent: Bool {
        lastResult != nil || !suggestions.isEmpty || current != .empty
    }

    @ViewBuilder
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
            if let lastResult { resultBanner(lastResult) }
            if !suggestions.isEmpty { suggestionList }
            previewSection
            reReadSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input

    private var inputField: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            if isSigil, !tokens.isEmpty { highlightedTokens }
            HStack(spacing: OrbitSpacing.sm) {
                if style == .sheet {
                    Image(systemName: "text.cursor").foregroundStyle(.secondary)
                }
                TextField(style == .docked ? "What happened?" : "Coffee with Sarah yesterday, talked about her move",
                          text: $inputText)
                    .font(OrbitTypography.body)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(commit)
                    .onChange(of: inputText) { _, _ in
                        if lastResult?.isError == true { lastResult = nil }
                        modelIntent = nil
                        readerMessage = nil
                        reparse()
                    }
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .padding(.vertical, style == .docked ? 8 : 0)
                    .padding(.horizontal, style == .docked ? 12 : 0)
                    .background {
                        if style == .docked {
                            RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.12))
                        }
                    }
                if !inputText.isEmpty && style == .sheet {
                    Button { clearInput() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
                if style == .docked {
                    Button(action: commit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(canCommit ? Color.accentColor : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommit)
                    .accessibilityLabel("Save")
                }
            }
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, style == .docked ? OrbitSpacing.sm : OrbitSpacing.md)
    }

    private var isSigil: Bool { CommandParser.looksLikeSigilSyntax(inputText) }

    private var canCommit: Bool {
        switch current {
        case .empty, .invalid: return false
        case .undo: return store.canUndo
        case .openGroup: return true
        case .command(let cmd): return resolveAll(cmd.contactNames).blocker == nil
        case .facts(let facts): return factPlan(facts).isReady
        case .log(let draft):
            let plan = logPlan(for: draft)
            return plan.isReady || plan.openable != nil
        }
    }

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
        switch current {
        case .empty:
            if style == .sheet { helpSection }
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(OrbitTypography.body)
                .foregroundStyle(OrbitColors.warning)
            if style == .sheet { syntaxDisclosure }
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
        case .facts(let facts):
            factsPreview(facts)
        case .log(let draft):
            logPreview(draft)
        }
    }

    @ViewBuilder
    private func logPreview(_ draft: CaptureDraft) -> some View {
        let plan = logPlan(for: draft)
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            if modelIntent != nil { modelBadge }

            previewRow("With") {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    if let groupName = draft.group { groupChip(groupName) }
                    ForEach(draft.people, id: \.self) { name in personChip(for: name) }
                    ForEach(extraPeople) { person in
                        PersonChip(name: person.name, removable: true) {
                            extraPeople.removeAll { $0.id == person.id }
                        }
                    }
                    Button { showExtraPicker = true } label: {
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
                    Text(draft.note).font(OrbitTypography.body).foregroundStyle(.secondary)
                }
            }

            if !draft.tags.isEmpty {
                previewRow("Tags") {
                    Text(draft.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.caption)
                        .foregroundStyle(OrbitColors.syntaxTag)
                }
            }

            if !draft.suggestedFacts.isEmpty {
                previewRow("Also") {
                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        ForEach(draft.suggestedFacts, id: \.self) { fact in
                            checkbox(acceptedSuggestions.contains(fact), "Save \(fact.summary)") {
                                if acceptedSuggestions.contains(fact) { acceptedSuggestions.remove(fact) }
                                else { acceptedSuggestions.insert(fact) }
                            }
                        }
                    }
                }
            }

            if let blocker = plan.blocker {
                Text(blocker).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: OrbitSpacing.sm) {
                if let openable = plan.openable {
                    if plan.isReady {
                        Button("Open \(openable.name)") { open(openable) }.buttonStyle(.bordered)
                    } else {
                        Button("Open \(openable.name)") { open(openable) }.buttonStyle(.borderedProminent)
                    }
                }
                if style == .sheet && (plan.isReady || plan.openable == nil) {
                    Button(plan.buttonTitle) { commit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!plan.isReady)
                }
                Spacer()
            }
        }
    }

    // MARK: Facts preview

    @ViewBuilder
    private func factsPreview(_ facts: [FactDraft]) -> some View {
        let plan = factPlan(facts)
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            if modelIntent != nil { modelBadge }
            Text(facts.count == 1 ? "Save a fact" : "Save \(facts.count) facts")
                .font(OrbitTypography.footnote)
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            ForEach(facts, id: \.self) { fact in
                HStack(alignment: .center, spacing: OrbitSpacing.sm) {
                    checkbox(!rejectedFacts.contains(fact), nil) {
                        if rejectedFacts.contains(fact) { rejectedFacts.remove(fact) } else { rejectedFacts.insert(fact) }
                    }
                    personChip(for: fact.person)
                    Text(fact.summary).font(OrbitTypography.bodyMedium)
                    Spacer(minLength: 0)
                }
            }
            if let blocker = plan.blocker {
                Text(blocker).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            if style == .sheet {
                Button(plan.buttonTitle) { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!plan.isReady)
            }
        }
    }

    // MARK: Chips

    @ViewBuilder
    private func personChip(for name: String) -> some View {
        let key = name.lowercased()
        if excluded.contains(key) {
            EmptyView()
        } else if let chosen = picked[key], !chosen.isEmpty {
            PersonChip(name: store.names(chosen), removable: true) { picked[key] = nil }
        } else {
            switch store.resolveContact(name) {
            case .resolved(let contact):
                PersonChip(name: contact.name, removable: true) { exclude(key) }
            case .several(let people):
                PersonChip(name: "\(name) · \(store.names(people))", removable: true) { exclude(key) }
            case .ambiguous(let candidates):
                Menu {
                    ForEach(candidates) { c in Button(c.name) { picked[key] = [c] } }
                    Divider()
                    Button("Not a person here", role: .destructive) { exclude(key) }
                } label: {
                    Label("Which \(name)?", systemImage: "questionmark.circle").font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button).buttonStyle(.bordered).tint(.orange).controlSize(.small)
            case .unknownRelation(let term):
                Menu {
                    Button("Choose your \(term)…") {
                        startPick(PickTarget(id: key, title: "Who's your \(term)?", multiple: Relationships.pluralMembers(term) != nil))
                    }
                    Button("Not a person here", role: .destructive) { exclude(key) }
                } label: {
                    Label("Who's your \(term)?", systemImage: "questionmark.circle").font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button).buttonStyle(.bordered).tint(.orange).controlSize(.small)
            case .notFound:
                Menu {
                    Text("“\(Self.titleCased(name))” will be added as a new person")
                    Button("It's someone I've added…") {
                        startPick(PickTarget(id: key, title: "Who is “\(name)”?", multiple: false))
                    }
                    Button("Not a person here", role: .destructive) { exclude(key) }
                } label: {
                    Label("New: \(name)", systemImage: "person.badge.plus").font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button).buttonStyle(.bordered).tint(.accentColor).controlSize(.small)
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
                PersonChip(name: "✦ \(group.name)", removable: true) { exclude(name.lowercased()) }
            case .ambiguous(let candidates):
                Menu {
                    ForEach(candidates) { g in Button(g.name) { chosenGroup = g } }
                    Divider()
                    Button("Not a group here", role: .destructive) { exclude(name.lowercased()) }
                } label: {
                    Label("Which group?", systemImage: "questionmark.circle").font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button).buttonStyle(.bordered).tint(.orange).controlSize(.small)
            case .notFound:
                Menu {
                    ForEach(groups) { g in Button("✦ \(g.name)") { chosenGroup = g } }
                    Divider()
                    Button("Not a group here", role: .destructive) { exclude(name.lowercased()) }
                } label: {
                    Label("Which group is “\(name)”?", systemImage: "questionmark.circle").font(OrbitTypography.captionMedium)
                }
                .menuStyle(.button).buttonStyle(.bordered).tint(.orange).controlSize(.small)
            }
        }
    }

    /// "Not a person here": stop treating the phrase as a person or group and
    /// re-read, so the word goes back into the note.
    private func exclude(_ key: String) {
        excluded.insert(key)
        picked[key] = nil
        modelIntent = nil
        reparse(immediately: true)
    }

    private func startPick(_ target: PickTarget) {
        lastPickKey = target.id
        pickSelection = []
        pickTarget = target
    }

    /// The sheet clears `pickTarget` before onDismiss runs, so the phrase is
    /// kept separately.
    private func applyPick() {
        guard let key = lastPickKey else { return }
        if !pickSelection.isEmpty { picked[key] = pickSelection }
        pickSelection = []
        lastPickKey = nil
    }

    // MARK: Plans

    private struct LogPlan {
        var people: [Contact] = []
        var toCreate: [String] = []
        var group: Constellation?
        var action: String?
        var blocker: String?
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

        if let groupName = draft.group, !excluded.contains(groupName.lowercased()) {
            if let chosenGroup { plan.group = chosenGroup }
            else if case .resolved(let g) = store.resolveGroup(groupName) { plan.group = g }
            else { plan.blocker = "Pick which group this was." }
        }

        var unresolved: [String] = []
        for name in draft.people {
            let key = name.lowercased()
            guard !excluded.contains(key) else { continue }
            if let chosen = picked[key], !chosen.isEmpty { plan.people.append(contentsOf: chosen); continue }
            switch store.resolveContact(name) {
            case .resolved(let c): plan.people.append(c)
            case .several(let cs): plan.people.append(contentsOf: cs)
            case .ambiguous, .unknownRelation: unresolved.append(name)
            case .notFound(let n): plan.toCreate.append(Self.titleCased(n))
            }
        }
        for extra in extraPeople where !plan.people.contains(where: { $0.id == extra.id }) {
            plan.people.append(extra)
        }
        var seen = Set<UUID>()
        plan.people = plan.people.filter { seen.insert($0.id).inserted }

        if !unresolved.isEmpty {
            plan.blocker = "Pick who \(unresolved.joined(separator: ", ")) \(unresolved.count == 1 ? "is" : "are")."
        } else if plan.group == nil && plan.people.isEmpty && plan.toCreate.isEmpty && plan.blocker == nil {
            plan.blocker = "Who was this with?"
        }

        if plan.people.count == 1, plan.toCreate.isEmpty, plan.group == nil,
           actionOverride == nil, draft.action == nil, draft.note.isEmpty, draft.tags.isEmpty {
            plan.openable = plan.people.first
        }
        return plan
    }

    private struct FactPlan {
        var items: [(FactDraft, Contact?)] = []   // nil contact = create
        var blocker: String?
        var isReady: Bool { blocker == nil && !items.isEmpty }
        var buttonTitle: String { items.count == 1 ? "Save fact" : "Save \(items.count) facts" }
    }

    private func factPlan(_ facts: [FactDraft]) -> FactPlan {
        var plan = FactPlan()
        var unresolved: [String] = []
        for fact in facts where !rejectedFacts.contains(fact) {
            let key = fact.person.lowercased()
            if excluded.contains(key) { continue }
            if let chosen = picked[key]?.first { plan.items.append((fact, chosen)); continue }
            switch store.resolveContact(fact.person) {
            case .resolved(let c): plan.items.append((fact, c))
            case .several(let cs): for c in cs { plan.items.append((fact, c)) }
            case .ambiguous, .unknownRelation: unresolved.append(fact.person)
            case .notFound: plan.items.append((fact, nil))
            }
        }
        if !unresolved.isEmpty { plan.blocker = "Pick who \(unresolved.joined(separator: ", ")) is." }
        else if plan.items.isEmpty { plan.blocker = "Nothing selected." }
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
            if style == .sheet {
                Button("Do it") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(resolution.blocker != nil)
            }
        }
    }

    private func resolveAll(_ names: [String], includeArchived: Bool = true) -> (contacts: [Contact], blocker: String?) {
        var result: [Contact] = []
        var missing: [String] = []
        var unclear: [String] = []
        for name in names {
            let key = name.lowercased()
            if excluded.contains(key) { continue }
            if let chosen = picked[key], !chosen.isEmpty { result.append(contentsOf: chosen); continue }
            switch store.resolveContact(name, includeArchived: includeArchived) {
            case .resolved(let c): result.append(c)
            case .several(let cs): result.append(contentsOf: cs)
            case .ambiguous, .unknownRelation: unclear.append(name)
            case .notFound(let n): missing.append(n)
            }
        }
        if !missing.isEmpty { return (result, "No one called \(missing.joined(separator: ", ")). Add them first, or log with them in plain words.") }
        if !unclear.isEmpty { return (result, "Pick who \(unclear.joined(separator: ", ")) is.") }
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
                Button("Open") { open(group) }.buttonStyle(.borderedProminent)
            }
        case .ambiguous(let candidates):
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                Text("Which group?").font(OrbitTypography.caption).foregroundStyle(.secondary)
                ForEach(candidates) { g in Button("✦ \(g.name)") { open(g) } }
            }
        case .notFound:
            Text("No group called “\(name)”. Add people to one with @Name *\(name).")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Re-read with Apple Intelligence

    @ViewBuilder
    private var reReadSection: some View {
        if let reader, !isSigil, showsReRead {
            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                switch reader.availability {
                case .available:
                    HStack(spacing: OrbitSpacing.sm) {
                        Button {
                            Task { await reRead(with: reader) }
                        } label: {
                            Label(isReading ? "Reading…" : "Re-read with Apple Intelligence", systemImage: "sparkles")
                                .font(OrbitTypography.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isReading)
                        if isReading { ProgressView().controlSize(.small) }
                    }
                case .unavailable(let reason):
                    Label(reason, systemImage: "sparkles")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
                if let readerMessage {
                    Text(readerMessage).font(OrbitTypography.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var showsReRead: Bool {
        guard modelIntent == nil else { return false }
        switch intent {
        case .log, .facts, .invalid: return !inputText.trimmingCharacters(in: .whitespaces).isEmpty
        default: return false
        }
    }

    private var modelBadge: some View {
        HStack(spacing: OrbitSpacing.sm) {
            Label("Read by Apple Intelligence", systemImage: "sparkles")
                .font(OrbitTypography.footnote)
                .foregroundStyle(.secondary)
            Button("Use original") {
                modelIntent = nil
                resetCorrections()
            }
            .font(OrbitTypography.footnote)
            .buttonStyle(.borderless)
        }
    }

    private func reRead(with reader: any CaptureReader) async {
        let text = inputText
        isReading = true
        readerMessage = nil
        defer { isReading = false }
        let context = ReaderContext(
            people: CaptureReaders.candidatePeople(for: text, contacts: contacts),
            groups: groups.map(\.name),
            actions: store.actionSuggestions(limit: 10),
            today: Date()
        )
        do {
            let capture = try await reader.read(text, context: context)
            guard text == inputText else { return }   // the user kept typing
            let mapped = capture.toIntent(knownActions: store.knownActions())
            if mapped == .log(CaptureDraft()) {
                readerMessage = "Apple Intelligence couldn't find anything to add. The original reading is still shown."
                return
            }
            resetCorrections()
            modelIntent = mapped
        } catch {
            readerMessage = "Re-read didn't work this time (\(error.localizedDescription)). The original reading is still shown."
        }
    }

    // MARK: - Commit

    private func commit() {
        switch current {
        case .empty, .invalid:
            return
        case .openGroup(let name):
            if case .resolved(let g) = store.resolveGroup(name) { open(g) }
        case .undo:
            store.undo()
            finish(text: "Undone", canUndo: false)
        case .command(let command):
            runCommand(command)
        case .facts(let facts):
            commitFacts(facts)
        case .log(let draft):
            commitLog(draft)
        }
    }

    private func commitLog(_ draft: CaptureDraft) {
        let plan = logPlan(for: draft)
        guard plan.isReady, let action = plan.action else {
            if let openable = plan.openable { open(openable) }
            return
        }
        let date = dateOverride ?? draft.date ?? Date()
        let title = plan.buttonTitle
            .replacingOccurrences(of: "Create & log", with: "Logged")
            .replacingOccurrences(of: "Log ", with: "Logged ")
        let suggestions = draft.suggestedFacts.filter { acceptedSuggestions.contains($0) }

        store.grouped("Log \(action)", message: title) {
            var people = plan.people
            if let group = plan.group {
                store.log(group: group, action: action, note: draft.note, tags: draft.tags, date: date)
            } else {
                for name in plan.toCreate {
                    people.append(store.createContact(name: name, orbit: 2, closenessConfirmed: false))
                }
                store.log(contacts: people, action: action, note: draft.note, tags: draft.tags, date: date)
            }
            learnCorrections(groupPhrase: draft.group)
            if !suggestions.isEmpty, let person = people.first {
                store.saveFacts(suggestions.map { ($0, person) })
            }
        }
        finish(text: title + (suggestions.isEmpty ? "" : " · saved \(suggestions.count) fact\(suggestions.count == 1 ? "" : "s")"), canUndo: true)
    }

    private func commitFacts(_ facts: [FactDraft]) {
        let plan = factPlan(facts)
        guard plan.isReady else { return }
        let title = plan.items.count == 1
            ? "Saved \(plan.items[0].0.summary) for \(plan.items[0].1?.name ?? Self.titleCased(plan.items[0].0.person))"
            : "Saved \(plan.items.count) facts"
        store.grouped("Save facts", message: title) {
            var created: [String: Contact] = [:]
            var pairs: [(FactDraft, Contact)] = []
            for (fact, contact) in plan.items {
                if let contact {
                    pairs.append((fact, contact))
                } else {
                    let name = Self.titleCased(fact.person)
                    let c = created[name.lowercased()] ?? store.createContact(name: name, orbit: 2, closenessConfirmed: false)
                    created[name.lowercased()] = c
                    pairs.append((fact, c))
                }
            }
            store.saveFacts(pairs)
            learnCorrections(groupPhrase: nil)
        }
        finish(text: title, canUndo: true)
    }

    /// Remember the phrases the user resolved by hand.
    private func learnCorrections(groupPhrase: String?) {
        for (phrase, people) in picked where !people.isEmpty {
            store.learn(phrase, means: people)
        }
        if let chosenGroup, let phrase = groupPhrase, phrase.lowercased() != chosenGroup.name.lowercased() {
            store.learn(phrase, means: chosenGroup)
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

    private func open(_ contact: Contact) {
        router.open(contact)
        clearInput()
        onOpen()
    }

    private func open(_ group: Constellation) {
        router.open(group)
        clearInput()
        onOpen()
    }

    private func finish(text: String, canUndo: Bool) {
        // In the Log tab the new entry appears in the history; only show a
        // banner for things that don't (facts, commands).
        if style == .sheet || !text.hasPrefix("Logged") {
            lastResult = (text, canUndo, false)
        } else {
            lastResult = nil
        }
        clearInput()
        inputFocused = true
    }

    private func resetCorrections() {
        picked = [:]
        excluded = []
        extraPeople = []
        actionOverride = nil
        dateOverride = nil
        chosenGroup = nil
        acceptedSuggestions = []
        rejectedFacts = []
    }

    private func clearInput() {
        inputText = ""
        intent = .empty
        modelIntent = nil
        readerMessage = nil
        tokens = []
        suggestions = []
        resetCorrections()
    }

    // MARK: - Parsing & suggestions

    private func reparse(immediately: Bool = false) {
        parseTask?.cancel()
        let text = inputText
        parseTask = Task { @MainActor in
            if !immediately { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            let parser = CaptureParser(
                personRefs: contacts.map(\.personRef),
                groupRefs: groups.map(\.groupRef),
                actions: store.knownActions(),
                ignoring: excluded
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
        let ranked = NameMatcher.ranked(word, in: candidates, limit: 3)
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

    private func apply(_ suggestion: CommandSuggestion) {
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

    var helpSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            Text("Just type what happened.")
                .font(OrbitTypography.bodyMedium)
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                ForEach(CapturePanel.examples) { ex in
                    example(ex.text, note: ex.note)
                }
            }
            syntaxDisclosure
        }
    }

    struct Example: Identifiable {
        let text: String
        let note: String?
        var id: String { text }
    }

    static let examples: [Example] = [
        Example(text: "Coffee with Sarah yesterday, talked about her move", note: nil),
        Example(text: "Texted my siblings about Mum's trip", note: "relationship words and groups"),
        Example(text: "Dinner with Sam, Alex and Jo on Friday", note: nil),
        Example(text: "Sarah's birthday is 3 March", note: "save a fact"),
        Example(text: "Tom works at Google", note: "save a fact"),
        Example(text: "Sarah", note: "open someone's page"),
    ]

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

    private func checkbox(_ isOn: Bool, _ label: String?, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: OrbitSpacing.xs) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                if let label { Text(label).font(OrbitTypography.caption).foregroundStyle(.primary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

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

    static func titleCased(_ name: String) -> String {
        name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - CommandPaletteView
// The ⌘K sheet on iPad and Mac (and from Today's Log button anywhere).

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    var seed: String = ""

    var body: some View {
        NavigationStack {
            CapturePanel(style: .sheet, seed: seed, onOpen: { dismiss() })
                .navigationTitle("Log or find")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 460)
        #endif
    }
}
