import SwiftUI
import SwiftData

// MARK: - ContactFormSheet (Phase 2 + Fix 1)
// FIX 1: Explicit modelContext.save() after creating or editing a contact.

struct ContactFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(OrbitStore.self) private var store
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

                if !validationIssues.isEmpty {
                    validationSection
                }
            }
            .formStyle(.grouped)
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
        #if os(macOS)
        .frame(width: 450, height: 550)
        #endif
    }

    private var nameSection: some View {
        Section {
            TextField("Name", text: $name)
                .font(OrbitTypography.headline)
                .onChange(of: name) { _, newValue in
                    nameCheckTask?.cancel()
                    nameCheckTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        validateName(newValue)
                    }
                }
        } footer: {
            Text("The only required field. Facts, groups and notes can be added any time.")
                .font(OrbitTypography.footnote)
        }
    }

    private var orbitSection: some View {
        Section("Closeness") {
            Picker("How close", selection: $targetOrbit) {
                ForEach(OrbitZone.allZones, id: \.id) { zone in
                    Text(zone.name).tag(zone.id)
                }
            }
            .pickerStyle(.menu)

            if let zone = OrbitZone.allZones.first(where: { $0.id == targetOrbit }) {
                Text(zone.description)
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Preview: ")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
                Text(name.isEmpty ? "Contact Name" : name)
                    .font(OrbitTypography.contactName(orbit: targetOrbit))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, OrbitSpacing.xs)

            Text("Orbit will suggest getting in touch: \(cadenceDescription(for: targetOrbit).lowercased())")
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var notesSection: some View {
        Section("Notes (optional)") {
            TextField("Any initial context about this person", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

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
        let result = validator.validateContactName(name, excluding: editingContactID, in: modelContext)
        validationIssues = result.issues
    }

    private func cadenceDescription(for orbit: Int) -> String {
        switch orbit {
        case 0: return "Weekly"
        case 1: return "Monthly"
        case 2: return "Every few months"
        case 3: return "Yearly"
        case 4: return "Never — no reminders"
        default: return "Every few months"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            // Choosing a closeness in the form counts as confirming it.
            let contact = store.createContact(name: trimmedName, orbit: targetOrbit, notes: notes, closenessConfirmed: true)
            onSave?(contact)
        case .edit(let contact):
            store.updateContact(contact, name: trimmedName, notes: notes, orbit: targetOrbit)
            onSave?(contact)
        }
    }
}
