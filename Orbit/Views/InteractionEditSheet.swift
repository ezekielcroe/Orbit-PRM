import SwiftUI
import SwiftData

// MARK: - InteractionEditSheet (Fix 5)
// Allows editing of existing interactions: impulse, content, date, and tags.
// Previously interactions were create-only with no edit capability.

struct InteractionEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Bindable var interaction: Interaction

    @State private var impulse: String
    @State private var content: String
    @State private var date: Date
    @State private var tagString: String
    @State private var showDeleteConfirmation = false

    @Query(sort: \Tag.name)
    private var allTags: [Tag]

    private let commonImpulses = ["Call", "Coffee", "Meal", "Message", "Meeting", "Play"]

    init(interaction: Interaction) {
        self.interaction = interaction
        _impulse = State(initialValue: interaction.impulse)
        _content = State(initialValue: interaction.content)
        _date = State(initialValue: interaction.date)
        _tagString = State(initialValue: interaction.tagNames)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Contact context
                if let contact = interaction.contact {
                    Section {
                        HStack {
                            Text(contact.name)
                                .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                            Spacer()
                            Text(contact.orbitZoneName)
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("What happened?") {
                    TextField("Action (e.g., Coffee, Call)", text: $impulse)

                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(commonImpulses, id: \.self) { imp in
                            Button(imp) {
                                impulse = imp
                            }
                            .buttonStyle(.bordered)
                            .tint(impulse == imp ? .orange : .secondary)
                            .controlSize(.small)
                        }
                    }
                }

                Section("Notes") {
                    TextField("What did you talk about?", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Tags") {
                    TextField("Comma-separated tags (e.g., work, project)", text: $tagString)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    // Tag suggestions from registry
                    if !allTags.isEmpty {
                        FlowLayout(spacing: OrbitSpacing.sm) {
                            ForEach(allTags.prefix(12)) { tag in
                                Button("#\(tag.name)") {
                                    addTag(tag.name)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(currentTagList.contains(tag.searchableName) ? .green : .secondary)
                            }
                        }
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }

                Section {
                    Text("Created: \(interaction.date.formatted(date: .long, time: .shortened))")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                } header: {
                    Text("Info")
                }

                Section {
                    Button("Delete Interaction", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Interaction")
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
                    .disabled(impulse.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Interaction?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteInteraction()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove this interaction. This action cannot be undone.")
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 550)
        #endif
    }

    // MARK: - Tag Helpers

    private var currentTagList: [String] {
        tagString.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func addTag(_ name: String) {
        let lower = name.lowercased()
        if currentTagList.contains(lower) {
            // Remove if already present (toggle)
            let tags = tagString.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { $0.lowercased() != lower }
            tagString = tags.joined(separator: ", ")
        } else {
            if tagString.trimmingCharacters(in: .whitespaces).isEmpty {
                tagString = name
            } else {
                tagString += ", \(name)"
            }
        }
    }

    // MARK: - Actions

    private func save() {
        // 1. Prepare formatted strings once to save processing time
        let formattedImpulse = impulse.trimmingCharacters(in: .whitespaces)
        let formattedContent = content.trimmingCharacters(in: .whitespaces)
        let formattedTags = tagString.trimmingCharacters(in: .whitespaces)
        
        // 2. Update the primary interaction
        interaction.impulse = formattedImpulse
        interaction.content = formattedContent
        interaction.date = date
        interaction.tagNames = formattedTags

        // Refresh the primary contact's metadata
        interaction.contact?.refreshLastContactDate()
        interaction.contact?.modifiedAt = Date()

        if let contact = interaction.contact {
            spotlightIndexer.index(contact: contact)
        }
        
        // 3. NEW: Batch Update Logic for Grouped Interactions
        if let batchID = interaction.batchID {
            let predicate = #Predicate<Interaction> { $0.batchID == batchID }
            let descriptor = FetchDescriptor<Interaction>(predicate: predicate)
            
            if let siblings = try? modelContext.fetch(descriptor) {
                for sibling in siblings {
                    // Skip the primary one we just updated above
                    if sibling.id == interaction.id { continue }
                    
                    // Apply exact same edits to the sibling
                    sibling.impulse = formattedImpulse
                    sibling.content = formattedContent
                    sibling.date = date
                    sibling.tagNames = formattedTags
                    
                    // Refresh the sibling contact's metadata and Spotlight index
                    sibling.contact?.refreshLastContactDate()
                    sibling.contact?.modifiedAt = Date()
                    
                    if let siblingContact = sibling.contact {
                        spotlightIndexer.index(contact: siblingContact)
                    }
                }
            }
        }

        // 4. Ensure any new tag names are in the registry
        for tagName in currentTagList {
            ensureTagExists(named: tagName)
        }

        // 5. Explicit save
        try? modelContext.save()
    }

    private func deleteInteraction() {
        // 1. Delete the primary interaction
        interaction.isDeleted = true
        interaction.contact?.refreshLastContactDate()
        interaction.contact?.modifiedAt = Date()

        if let contact = interaction.contact {
            spotlightIndexer.index(contact: contact)
        }
        
        // 2. NEW: Batch Delete Logic for Grouped Interactions
        if let batchID = interaction.batchID {
            let predicate = #Predicate<Interaction> { $0.batchID == batchID }
            let descriptor = FetchDescriptor<Interaction>(predicate: predicate)
            
            if let siblings = try? modelContext.fetch(descriptor) {
                for sibling in siblings {
                    if sibling.id == interaction.id { continue }
                    
                    // Soft-delete the sibling
                    sibling.isDeleted = true
                    
                    // Refresh the sibling contact's metadata and Spotlight index
                    sibling.contact?.refreshLastContactDate()
                    sibling.contact?.modifiedAt = Date()
                    
                    if let siblingContact = sibling.contact {
                        spotlightIndexer.index(contact: siblingContact)
                    }
                }
            }
        }

        try? modelContext.save()
        dismiss()
    }

    private func ensureTagExists(named name: String) {
        let searchName = name.lowercased()
        let predicate = #Predicate<Tag> { tag in
            tag.searchableName == searchName
        }
        var descriptor = FetchDescriptor<Tag>(predicate: predicate)
        descriptor.fetchLimit = 1

        if (try? modelContext.fetch(descriptor).first) == nil {
            let tag = Tag(name: name)
            modelContext.insert(tag)
        }
    }
}
