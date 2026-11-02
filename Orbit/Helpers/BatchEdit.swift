//
//  BatchEdit.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 28/2/26.
//

import SwiftUI
import SwiftData

// MARK: - Batch Edit State Model

struct BatchEdit {
    var orbitZone: Int? = nil
    var archiveStatus: ArchiveStatus = .noChange
    var constellationsToAdd: Set<Constellation.ID> = []
    var constellationsToRemove: Set<Constellation.ID> = []
    var deleteAll: Bool = false
    
    enum ArchiveStatus: String, CaseIterable {
        case noChange = "No Change"
        case archive = "Archive"
        case unarchive = "Unarchive"
    }
}

// MARK: - Batch Action Sheet View

struct BatchActionSheet: View {
    let selectedCount: Int
    let onApply: (BatchEdit) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Constellation.name) private var allConstellations: [Constellation]
    
    @State private var edit = BatchEdit()
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. Orbit Zone Change
                Section {
                    Picker("Closeness", selection: $edit.orbitZone) {
                        Text("No Change").tag(Int?.none)
                        Divider()
                        ForEach(OrbitZone.allZones, id: \.id) { zone in
                            Text("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))").tag(Int?.some(zone.id))
                        }
                    }
                } header: {
                    Text("Closeness")
                } footer: {
                    Text("Sets how often you'd like to be in touch with everyone selected.")
                }
                
                // 2. Archive Status Change
                Section("Status") {
                    Picker("Archive Status", selection: $edit.archiveStatus) {
                        ForEach(BatchEdit.ArchiveStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
                
                // 3. Constellation Management
                if !allConstellations.isEmpty {
                    Section("Groups") {
                        NavigationLink {
                            ConstellationSelectionList(
                                title: "Add to...",
                                all: allConstellations,
                                selection: $edit.constellationsToAdd
                            )
                        } label: {
                            HStack {
                                Text("Add to groups")
                                Spacer()
                                if !edit.constellationsToAdd.isEmpty {
                                    Text("\(edit.constellationsToAdd.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        NavigationLink {
                            ConstellationSelectionList(
                                title: "Remove from...",
                                all: allConstellations,
                                selection: $edit.constellationsToRemove
                            )
                        } label: {
                            HStack {
                                Text("Remove from groups")
                                Spacer()
                                if !edit.constellationsToRemove.isEmpty {
                                    Text("\(edit.constellationsToRemove.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // 4. Destructive Action
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete \(selectedCount) Contacts")
                            Spacer()
                        }
                    }
                }
            }
            // FIX: Applies standard system padding to the form on macOS
            .formStyle(.grouped)
            .navigationTitle("Edit \(selectedCount) Selected")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(edit)
                    }
                    // Prevent applying if no changes were actually made
                    .disabled(
                        edit.orbitZone == nil &&
                        edit.archiveStatus == .noChange &&
                        edit.constellationsToAdd.isEmpty &&
                        edit.constellationsToRemove.isEmpty
                    )
                }
            }
            .confirmationDialog(
                "Delete \(selectedCount) Contacts?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    var destructiveEdit = BatchEdit()
                    destructiveEdit.deleteAll = true
                    onApply(destructiveEdit)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone. It will permanently delete these contacts, their facts and their entire history.")
            }
        }
        #if os(macOS)
        // FIX: Anchors the sheet size so it doesn't shrink-wrap the form
        .frame(width: 450, height: 500)
        #endif
    }
}

// MARK: - Helper View for Constellation Selection

struct ConstellationSelectionList: View {
    let title: String
    let all: [Constellation]
    @Binding var selection: Set<Constellation.ID>
    
    var body: some View {
        List(all) { constellation in
            Button {
                if selection.contains(constellation.id) {
                    selection.remove(constellation.id)
                } else {
                    selection.insert(constellation.id)
                }
            } label: {
                HStack {
                    Text("✦ \(constellation.name)")
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(constellation.id) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // On macOS, lists inside navigation stacks benefit from this style
        .listStyle(.inset)
    }
}
