import SwiftUI
import SwiftData

// MARK: - LogComposer
// The one logging form. Replaces QuickInteractionSheet,
// ConstellationInteractionSheet and InteractionEditSheet, so logging from a
// contact, a group, Today or the Activity list always offers the same fields:
// people, action (from one shared vocabulary), note, tags, date *and* time.

struct LogComposer: View {
    enum Mode {
        case new(contacts: [Contact], group: Constellation?, action: String?)
        case edit(Interaction)
    }

    @Environment(OrbitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var people: [Contact]
    @State private var group: Constellation?
    @State private var action: String
    @State private var note: String
    @State private var tags: [String]
    @State private var tagDraft = ""
    @State private var date: Date
    @State private var applyToBatch = true
    @State private var showPeoplePicker = false
    @State private var showDeleteConfirm = false
    @FocusState private var noteFocused: Bool

    @Query(sort: \Tag.name) private var allTags: [Tag]

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case let .new(contacts, group, action):
            _people = State(initialValue: contacts)
            _group = State(initialValue: group)
            _action = State(initialValue: action ?? "")
            _note = State(initialValue: "")
            _tags = State(initialValue: [])
            _date = State(initialValue: Date())
        case .edit(let interaction):
            _people = State(initialValue: interaction.contact.map { [$0] } ?? [])
            _group = State(initialValue: nil)
            _action = State(initialValue: interaction.impulse)
            _note = State(initialValue: interaction.content)
            _tags = State(initialValue: interaction.tagList)
            _date = State(initialValue: interaction.date)
        }
    }

    private var editing: Interaction? {
        if case .edit(let i) = mode { return i }
        return nil
    }

    private var siblingCount: Int {
        guard let editing, editing.batchID != nil else { return 1 }
        return store.batchSiblings(of: editing).count
    }

    private var canSave: Bool {
        !action.trimmingCharacters(in: .whitespaces).isEmpty && (group != nil || !people.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                whoSection
                whatSection
                Section("Note") {
                    TextField("What did you talk about?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                }
                tagsSection
                Section {
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                if editing != nil {
                    Section {
                        Button(siblingCount > 1 && applyToBatch ? "Delete for all \(siblingCount) people" : "Delete log", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Log" : "Edit log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPeoplePicker) {
                ContactPickerSheet(selection: $people)
            }
            .confirmationDialog("Delete this log?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editing { store.delete(editing, includeBatch: applyToBatch) }
                    dismiss()
                }
            } message: {
                Text("You can undo this from the banner that appears.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: Sections

    @ViewBuilder
    private var whoSection: some View {
        Section("With") {
            if let group {
                HStack {
                    Text("✦ \(group.name)").font(OrbitTypography.bodyMedium)
                    Spacer()
                    Text("\((group.contacts ?? []).filter { !$0.isArchived }.count) people")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !people.isEmpty {
                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(people) { person in
                            PersonChip(name: person.name, removable: editing == nil) {
                                people.removeAll { $0.id == person.id }
                            }
                        }
                    }
                    .padding(.vertical, OrbitSpacing.xs)
                }
                if editing == nil {
                    Button(people.isEmpty ? "Choose people…" : "Add someone…", systemImage: "person.badge.plus") {
                        showPeoplePicker = true
                    }
                }
            }
            if let editing, editing.batchID != nil, siblingCount > 1 {
                Toggle("Apply changes to all \(siblingCount) people in this log", isOn: $applyToBatch)
            }
        }
    }

    private var whatSection: some View {
        Section("What happened") {
            TextField("Action, e.g. Coffee", text: $action)
                .autocorrectionDisabled()
            FlowLayout(spacing: OrbitSpacing.sm) {
                ForEach(store.actionSuggestions(limit: 8), id: \.self) { suggestion in
                    Button(suggestion) { action = suggestion }
                        .buttonStyle(.bordered)
                        .tint(action.lowercased() == suggestion.lowercased() ? .accentColor : .secondary)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, OrbitSpacing.xs)
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            if !tags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(tags, id: \.self) { tag in
                        PersonChip(name: "#\(tag)", removable: true) { tags.removeAll { $0 == tag } }
                    }
                }
                .padding(.vertical, OrbitSpacing.xs)
            }
            HStack {
                TextField("Add a tag", text: $tagDraft)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(addDraftTag)
                if !tagDraft.isEmpty {
                    Button("Add", action: addDraftTag)
                }
            }
            let suggestions = allTags
                .map(\.name)
                .filter { name in !tags.contains(name.lowercased()) && (tagDraft.isEmpty || name.lowercased().contains(tagDraft.lowercased())) }
                .prefix(10)
            if !suggestions.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(Array(suggestions), id: \.self) { name in
                        Button("#\(name)") {
                            tags.append(name.lowercased())
                            tagDraft = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.secondary)
                    }
                }
                .padding(.vertical, OrbitSpacing.xs)
            }
        }
    }

    private func addDraftTag() {
        let cleaned = tagDraft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
            .filter { !$0.isEmpty }
        for t in cleaned where !tags.contains(t) { tags.append(t) }
        tagDraft = ""
    }

    // MARK: Save

    private func save() {
        if !tagDraft.isEmpty { addDraftTag() }
        if let editing {
            store.update(editing, action: action, note: note, tags: tags, date: date, applyToBatch: applyToBatch)
        } else if let group {
            store.log(group: group, action: action, note: note, tags: tags, date: date)
        } else {
            store.log(contacts: people, action: action, note: note, tags: tags, date: date)
        }
        dismiss()
    }
}

// MARK: - PersonChip

struct PersonChip: View {
    let name: String
    var removable: Bool = false
    var onRemove: () -> Void = {}

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(OrbitTypography.captionMedium)
            if removable {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(name)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

// MARK: - ContactPickerSheet
// Searchable multi-select list of people. Used by the composer and the palette.

struct ContactPickerSheet: View {
    @Binding var selection: [Contact]
    var allowsMultiple: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name) private var contacts: [Contact]
    @State private var search = ""

    private var filtered: [Contact] {
        search.isEmpty ? contacts : contacts.filter { $0.matchesSearch(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { contact in
                Button {
                    toggle(contact)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).foregroundStyle(.primary)
                            Text(contact.orbitZoneName)
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection.contains(where: { $0.id == contact.id }) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search people")
            .navigationTitle("Choose people")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 440)
        #endif
    }

    private func toggle(_ contact: Contact) {
        if let index = selection.firstIndex(where: { $0.id == contact.id }) {
            selection.remove(at: index)
        } else if allowsMultiple {
            selection.append(contact)
        } else {
            selection = [contact]
            dismiss()
        }
    }
}
