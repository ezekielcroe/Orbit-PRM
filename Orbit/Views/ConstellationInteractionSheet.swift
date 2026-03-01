//
//  ConstellationInteractionSheet.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 27/2/26.
//


import SwiftUI
import SwiftData

struct ConstellationInteractionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    let constellation: Constellation

    @State private var impulse = ""
    @State private var content = ""
    @State private var date = Date()
    @State private var tagString = ""

    private let commonImpulses = ["Call", "Coffee", "Dinner", "Text", "Meeting", "Lunch", "Walk", "Video Call", "Email"]
    
    @Query(sort: \Tag.name) private var allTags: [Tag]

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Notes (optional)") {
                    TextField("What did you talk about?", text: $content, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Tags") {
                    TextField("Comma-separated tags", text: $tagString)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }
            }
            .navigationTitle("Log Group Interaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveInteraction()
                        dismiss()
                    }
                    .disabled(impulse.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var currentTagList: [String] {
        tagString.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func saveInteraction() {
            let activeMembers = (constellation.contacts ?? []).filter { !$0.isArchived }
            let batchID = UUID() // Shared across all interactions in this group log
            
            for contact in activeMembers {
                let interaction = Interaction(
                    impulse: impulse.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces),
                    date: date,
                    batchID: batchID
                )
                interaction.tagNames = tagString.trimmingCharacters(in: .whitespaces)
                interaction.contact = contact
                
                modelContext.insert(interaction)
                contact.refreshCachedFields()
                spotlightIndexer.index(contact: contact)
            }
        
        // Ensure any new tag names are added to the registry
        for tagName in currentTagList {
            ensureTagExists(named: tagName)
        }

        try? modelContext.save()
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
