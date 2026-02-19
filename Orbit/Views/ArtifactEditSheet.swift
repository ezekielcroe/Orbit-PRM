import SwiftUI
import SwiftData

// MARK: - ArtifactEditSheet (Phase 2)
// Updates from Phase 1:
// - Date format validation for birthday/anniversary keys
// - Spotlight re-indexing on save
// - Improved common key suggestions based on existing artifacts

struct ArtifactEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Environment(DataValidator.self) private var validator

    let contact: Contact
    let mode: Mode

    @State private var key: String = ""
    @State private var value: String = ""
    @State private var isArray: Bool = false
    @State private var arrayItems: [String] = []
    @State private var newArrayItem: String = ""
    @State private var validationWarning: String?

    enum Mode {
        case add
        case edit(Artifact)
    }

    init(contact: Contact, mode: Mode) {
        self.contact = contact
        self.mode = mode

        switch mode {
        case .add:
            _key = State(initialValue: "")
            _value = State(initialValue: "")
            _isArray = State(initialValue: false)
            _arrayItems = State(initialValue: [])
        case .edit(let artifact):
            _key = State(initialValue: artifact.key)
            _isArray = State(initialValue: artifact.isArray)
            if artifact.isArray {
                _value = State(initialValue: "")
                _arrayItems = State(initialValue: artifact.listValues)
            } else {
                _value = State(initialValue: artifact.value)
                _arrayItems = State(initialValue: [])
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("e.g., birthday, spouse, likes", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: key) { _, newKey in
                            // Auto-suggest array mode for list-like keys
                            let listKeys = ["likes", "children", "hobbies", "interests", "allergies", "skills"]
                            if listKeys.contains(newKey.lowercased()) && !isEditing {
                                isArray = true
                            }
                        }

                    if case .add = mode {
                        commonKeySuggestions
                    }
                }

                Section {
                    Toggle("List (multiple values)", isOn: $isArray)
                }

                if isArray {
                    arraySection
                } else {
                    Section("Value") {
                        TextField("Value", text: $value, axis: .vertical)
                            .lineLimit(1...4)
                            .onChange(of: value) { _, newValue in
                                validateValue(key: key, value: newValue)
                            }

                        // Date format hint for date-like keys
                        if isDateKey {
                            Text("Use format: MM/DD, YYYY-MM-DD, or Month Day")
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Validation warning
                if let warning = validationWarning {
                    Section {
                        HStack(spacing: OrbitSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(warning)
                                .font(OrbitTypography.caption)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Artifact" : "Add Artifact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            deleteArtifact()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Common Key Suggestions

    private var commonKeySuggestions: some View {
        let commonKeys = ["birthday", "spouse", "city", "company", "role",
                          "phone", "email", "likes", "children", "met_at",
                          "default_activity", "pronouns", "anniversary",
                          "hometown", "notes", "website"]
        let existingKeys = Set(contact.artifacts.map(\.searchableKey))
        let available = commonKeys.filter { !existingKeys.contains($0) }

        return Group {
            if !available.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(available.prefix(10), id: \.self) { suggestion in
                        Button(suggestion) {
                            key = suggestion
                            if ["likes", "children", "hobbies", "interests"].contains(suggestion) {
                                isArray = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Array Section

    private var arraySection: some View {
        Section("Values") {
            ForEach(arrayItems, id: \.self) { item in
                HStack {
                    Text(item)
                    Spacer()
                    Button {
                        arrayItems.removeAll { $0 == item }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onMove { indices, destination in
                arrayItems.move(fromOffsets: indices, toOffset: destination)
            }

            HStack {
                TextField("Add item", text: $newArrayItem)
                    .onSubmit { addArrayItem() }

                Button {
                    addArrayItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newArrayItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Validation

    private var isDateKey: Bool {
        let dateKeys = ["birthday", "anniversary", "born", "dob"]
        return dateKeys.contains(key.lowercased())
    }

    private func validateValue(key: String, value: String) {
        let result = validator.validateArtifact(key: key, value: value)
        validationWarning = result.issues.first?.message
    }

    // MARK: - Actions

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func addArrayItem() {
        let trimmed = newArrayItem.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        arrayItems.append(trimmed)
        newArrayItem = ""
    }

    private func save() {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let artifact = Artifact(key: trimmedKey, value: "", isArray: isArray)
            artifact.contact = contact
            modelContext.insert(artifact)

            if isArray {
                for item in arrayItems {
                    artifact.appendValue(item)
                }
            } else {
                artifact.setValue(value)
            }

        case .edit(let artifact):
            artifact.key = trimmedKey
            artifact.searchableKey = trimmedKey.lowercased()

            if isArray {
                artifact.isArray = true
                if let data = try? JSONEncoder().encode(arrayItems),
                   let str = String(data: data, encoding: .utf8) {
                    artifact.value = str
                }
            } else {
                artifact.isArray = false
                artifact.value = value
            }

            artifact.modifiedAt = Date()
        }

        contact.modifiedAt = Date()
        spotlightIndexer.index(contact: contact)
    }

    private func deleteArtifact() {
        if case .edit(let artifact) = mode {
            modelContext.delete(artifact)
            contact.modifiedAt = Date()
            spotlightIndexer.index(contact: contact)
        }
    }
}
