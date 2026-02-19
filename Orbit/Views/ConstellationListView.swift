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
                            }
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
        .sheet(isPresented: $showAddSheet) {
            ConstellationFormSheet()
        }
        .sheet(item: $selectedConstellation) { constellation in
            ConstellationDetailSheet(constellation: constellation)
        }
    }
}

// MARK: - Constellation Form Sheet

struct ConstellationFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g., College Friends)", text: $name)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .navigationTitle("New Constellation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let constellation = Constellation(name: name, notes: notes)
                        modelContext.insert(constellation)
                        dismiss()
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
