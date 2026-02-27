//
//  ConstellationFormSheet.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 27/2/26.
//


import SwiftUI
import SwiftData

// MARK: - Constellation Form Sheet

struct ConstellationFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Query active contacts to allow assignment during creation
    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var allContacts: [Contact]

    @State private var name: String
    @State private var notes: String
    
    // Track selections by UUID for safe State management
    @State private var selectedContactIDs: Set<UUID>
    
    var editingConstellation: Constellation?

    init(editingConstellation: Constellation? = nil) {
        self.editingConstellation = editingConstellation
        if let constellation = editingConstellation {
            _name = State(initialValue: constellation.name)
            _notes = State(initialValue: constellation.notes)
            _selectedContactIDs = State(initialValue: Set(constellation.contacts.map(\.id)))
        } else {
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
            _selectedContactIDs = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g., College Friends)", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section {
                    NavigationLink {
                        ContactSelectionView(
                            allContacts: allContacts,
                            selectedContactIDs: $selectedContactIDs
                        )
                    } label: {
                        HStack {
                            Text("Members")
                            Spacer()
                            Text("\(selectedContactIDs.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Preview the selected members directly in the form
                    let selectedContacts = allContacts.filter { selectedContactIDs.contains($0.id) }
                    if !selectedContacts.isEmpty {
                        ForEach(selectedContacts.prefix(5)) { contact in
                            Text(contact.name)
                                .font(OrbitTypography.body)
                        }
                        
                        if selectedContacts.count > 5 {
                            Text("and \(selectedContacts.count - 5) more...")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle(editingConstellation == nil ? "New Constellation" : "Edit Constellation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingConstellation == nil ? "Create" : "Save") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func save() {
        let selectedContacts = allContacts.filter { selectedContactIDs.contains($0.id) }
        
        if let constellation = editingConstellation {
            constellation.name = name
            constellation.notes = notes
            
            // Safely compute additions and removals to update relationships
            let existingIDs = Set(constellation.contacts.map(\.id))
            
            let contactsToRemove = constellation.contacts.filter { !selectedContactIDs.contains($0.id) }
            let contactsToAdd = selectedContacts.filter { !existingIDs.contains($0.id) }
            
            for contact in contactsToRemove {
                constellation.contacts.removeAll(where: { $0.id == contact.id })
                contact.modifiedAt = Date()
            }
            
            for contact in contactsToAdd {
                constellation.contacts.append(contact)
                contact.modifiedAt = Date()
            }
            
        } else {
            let constellation = Constellation(name: name, notes: notes)
            constellation.contacts = selectedContacts
            
            for contact in selectedContacts {
                contact.modifiedAt = Date()
            }
            
            modelContext.insert(constellation)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Contact Selection Sub-View

struct ContactSelectionView: View {
    let allContacts: [Contact]
    @Binding var selectedContactIDs: Set<UUID>
    
    @State private var searchText = ""
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty { return allContacts }
        let query = searchText.lowercased()
        return allContacts.filter { $0.searchableName.contains(query) }
    }
    
    var body: some View {
        List {
            ForEach(filteredContacts) { contact in
                Button {
                    if selectedContactIDs.contains(contact.id) {
                        selectedContactIDs.remove(contact.id)
                    } else {
                        selectedContactIDs.insert(contact.id)
                    }
                } label: {
                    HStack(spacing: OrbitSpacing.md) {
                        Image(systemName: selectedContactIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedContactIDs.contains(contact.id) ? .blue : .tertiary)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(OrbitTypography.bodyMedium)
                                .foregroundStyle(.primary)
                            
                            Text(contact.orbitZoneName)
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search contacts...")
        .navigationTitle("Select Members")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}