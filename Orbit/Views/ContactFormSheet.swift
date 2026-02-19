import SwiftUI
import SwiftData

// MARK: - ContactFormSheet (Phase 2)
// Updates from Phase 1:
// - Real-time duplicate detection as user types
// - Validation warnings (near-duplicate names)
// - Spotlight re-indexing on save
// - Orbit zone description shown for context

struct ContactFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Environment(DataValidator.self) private var validator

    let mode: Mode
    var onSave: ((Contact) -> Void)?

    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var targetOrbit: Int = 2
    @State private var validationIssues: [DataValidator.ValidationIssue] = []
    @State private var nameCheckTask: Task<Void, Never>?

    enum Mode {
        case add
        case edit(Contact)
    }

    init(mode: Mode, onSave: ((Contact) -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
            _targetOrbit = State(initialValue: 2)
        case .edit(let contact):
            _name = State(initialValue: contact.name)
            _notes = State(initialValue: contact.notes)
            _targetOrbit = State(initialValue: contact.targetOrbit)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                orbitSection
                notesSection

                // Validation warnings
                if !validationIssues.isEmpty {
                    validationSection
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "New Contact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || hasErrors)
                }
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        Section {
            TextField("Name", text: $name)
                .font(OrbitTypography.headline)
                .onChange(of: name) { _, newValue in
                    // Debounced validation
                    nameCheckTask?.cancel()
                    nameCheckTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        validateName(newValue)
                    }
                }
        } footer: {
            Text("The only required field. Everything else can be added later via artifacts.")
                .font(OrbitTypography.footnote)
        }
    }

    // MARK: - Orbit Section

    private var orbitSection: some View {
        Section("Orbit Zone") {
            Picker("Target Orbit", selection: $targetOrbit) {
                ForEach(OrbitZone.allZones, id: \.id) { zone in
                    Text(zone.name).tag(zone.id)
                }
            }
            .pickerStyle(.menu)

            // Zone description
            if let zone = OrbitZone.allZones.first(where: { $0.id == targetOrbit }) {
                Text(zone.description)
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.secondary)
            }

            // Typographic weight preview
            HStack {
                Text("Preview: ")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
                Text(name.isEmpty ? "Contact Name" : name)
                    .font(OrbitTypography.contactName(orbit: targetOrbit))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, OrbitSpacing.xs)

            // Cadence expectation
            Text("Expected cadence: \(cadenceDescription(for: targetOrbit))")
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section("Notes (optional)") {
            TextField("Any initial context about this person", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    // MARK: - Validation Section

    private var validationSection: some View {
        Section {
            ForEach(validationIssues) { issue in
                HStack(spacing: OrbitSpacing.sm) {
                    Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? .red : .yellow)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.message)
                            .font(OrbitTypography.caption)

                        if let suggestion = issue.suggestion {
                            Text(suggestion)
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var hasErrors: Bool {
        validationIssues.contains(where: { $0.severity == .error })
    }

    private var editingContactID: UUID? {
        if case .edit(let contact) = mode { return contact.id }
        return nil
    }

    private func validateName(_ name: String) {
        let result = validator.validateContactName(
            name,
            excluding: editingContactID,
            in: modelContext
        )
        validationIssues = result.issues
    }

    private func cadenceDescription(for orbit: Int) -> String {
        switch orbit {
        case 0: return "Weekly contact"
        case 1: return "Monthly contact"
        case 2: return "Quarterly contact"
        case 3: return "Yearly contact"
        case 4: return "No expected cadence"
        default: return "Quarterly contact"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let contact = Contact(name: trimmedName, notes: notes, targetOrbit: targetOrbit)
            modelContext.insert(contact)
            spotlightIndexer.index(contact: contact)
            onSave?(contact)

        case .edit(let contact):
            contact.name = trimmedName
            contact.updateSearchableName()
            contact.notes = notes
            contact.targetOrbit = targetOrbit
            contact.modifiedAt = Date()
            spotlightIndexer.index(contact: contact)
            onSave?(contact)
        }
    }
}
