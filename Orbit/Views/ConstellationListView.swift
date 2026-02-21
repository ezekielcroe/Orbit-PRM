import SwiftUI
import SwiftData

// MARK: - ConstellationListView
// Constellations are named groups of contacts — "College Friends",
// "Work Team", "Neighbors". They provide a way to view and manage
// related relationships together.

struct ConstellationListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Constellation.name)
    private var constellations: [Constellation]

    @State private var showAddSheet = false
    @State private var selectedConstellation: Constellation?
    @State private var constellationToEdit: Constellation?

    var body: some View {
        Group {
            if constellations.isEmpty {
                ContentUnavailableView(
                    "No Constellations",
                    systemImage: "star.circle",
                    description: Text("Group related contacts into constellations.")
                )
            } else {
                List(selection: $selectedConstellation) {
                    ForEach(constellations) { constellation in
                        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                            Text(constellation.name)
                                .font(OrbitTypography.bodyMedium)

                            Text("\(constellation.contacts.count) contact\(constellation.contacts.count == 1 ? "" : "s")")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)

                            if !constellation.notes.isEmpty {
                                Text(constellation.notes)
                                    .font(OrbitTypography.footnote)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(constellation)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                modelContext.delete(constellation)
                                try? modelContext.save()
                            }
                            
                            Button("Edit") {
                                constellationToEdit = constellation
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Constellations")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .background {
            Color.clear
                .sheet(isPresented: $showAddSheet) {
                    ConstellationFormSheet()
                }
        }
        .background {
            Color.clear
                .sheet(item: $selectedConstellation) { constellation in
                    ConstellationDetailSheet(constellation: constellation)
                }
        }
        .background {
            Color.clear
                .sheet(item: $constellationToEdit) { constellation in
                    ConstellationFormSheet(editingConstellation: constellation)
                }
        }
    }
}

// MARK: - Constellation Form Sheet

struct ConstellationFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    
    // 1. Hold the constellation being edited
    var editingConstellation: Constellation?

    // 2. Custom initializer to set up state based on the mode
    init(editingConstellation: Constellation? = nil) {
        self.editingConstellation = editingConstellation
        if let constellation = editingConstellation {
            _name = State(initialValue: constellation.name)
            _notes = State(initialValue: constellation.notes)
        } else {
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g., College Friends)", text: $name)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            // 3. Dynamic title
            .navigationTitle(editingConstellation == nil ? "New Constellation" : "Edit Constellation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 4. Dynamic button and save logic
                    Button(editingConstellation == nil ? "Create" : "Save") {
                        if let constellation = editingConstellation {
                            // Edit existing
                            constellation.name = name
                            constellation.notes = notes
                        } else {
                            // Create new
                            let constellation = Constellation(name: name, notes: notes)
                            modelContext.insert(constellation)
                        }
                        
                        try? modelContext.save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Constellation Detail Sheet

struct ConstellationDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var constellation: Constellation

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var allContacts: [Contact]

    var body: some View {
        NavigationStack {
            List {
                Section("Members") {
                    ForEach(constellation.contacts.sorted(by: { $0.name < $1.name })) { contact in
                        HStack {
                            Text(contact.name)
                                .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                            Spacer()
                            Button {
                                constellation.contacts.removeAll { $0.id == contact.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Add Members") {
                    let nonMembers = allContacts.filter { contact in
                        !constellation.contacts.contains(where: { $0.id == contact.id })
                    }

                    if nonMembers.isEmpty {
                        Text("All contacts are in this constellation.")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nonMembers) { contact in
                            HStack {
                                Text(contact.name)
                                    .font(OrbitTypography.body)
                                Spacer()
                                Button {
                                    constellation.contacts.append(contact)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(constellation.name)
        }
    }
}
