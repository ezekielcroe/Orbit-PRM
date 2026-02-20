import SwiftUI
import SwiftData

// MARK: - ContactListView
// A searchable, filterable list of all contacts.
// Supports sorting by name, orbit zone, or last contact date.
// Includes the "Add Contact" action — new contacts are created via form,
// not command palette, to reduce friction for the initial setup.

struct ContactListView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedContact: Contact?

    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var sortOrder: SortOrder = .name
    @State private var showArchived = false

    @Query(sort: [SortDescriptor(\Contact.name)])
    private var allContacts: [Contact]

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case orbit = "Orbit"
        case recent = "Recent"
    }

    private var filteredContacts: [Contact] {
        var result = allContacts

        // Filter by archive state
        if !showArchived {
            result = result.filter { !$0.isArchived }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { contact in
                contact.searchableName.contains(query)
                    || contact.tagNames.contains(where: { $0.contains(query) })
                    || contact.artifacts.contains(where: {
                        $0.value.lowercased().contains(query)
                        || $0.searchableKey.contains(query)
                    })
            }
        }

        // Sort
        switch sortOrder {
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .orbit:
            result.sort { $0.targetOrbit < $1.targetOrbit }
        case .recent:
            result.sort { ($0.lastContactDate ?? .distantPast) > ($1.lastContactDate ?? .distantPast) }
        }

        return result
    }

    var body: some View {
        List(selection: $selectedContact) {
            ForEach(filteredContacts) { contact in
                HStack {
                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        Text(contact.name)
                            .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                            .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                        if let days = contact.daysSinceLastContact {
                            Text(days == 0 ? "Today" : "\(days)d ago")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No interactions logged")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if !contact.aggregatedTags.isEmpty {
                        Text(contact.aggregatedTags.prefix(2).map(\.name).joined(separator: ", "))
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .tag(contact)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(contact.isArchived ? "Restore" : "Archive") {
                        contact.isArchived.toggle()
                        contact.modifiedAt = Date()
                    }
                    .tint(contact.isArchived ? .blue : .orange)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search contacts, tags, or artifacts")
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }

                    Divider()

                    Toggle("Show Archived", isOn: $showArchived)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }

                Button {
                    showAddContact = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .help("Add Contact")
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactFormSheet(mode: .add) { newContact in
                selectedContact = newContact
            }
        }
    }
}

