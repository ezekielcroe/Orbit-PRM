import SwiftUI
import SwiftData

// MARK: - TabularView
// Spreadsheet-like view for auditing and batch operations on contacts.
// From the spec: "Columns include Name, Orbit Zone, Last Contact Date, and Tags.
// Users can sort by any column to audit specific metrics."
//
// Also supports batch operations: select multiple contacts and apply
// a tag, change orbit zone, or archive in bulk.

struct TabularView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Contact.name)])
    private var allContacts: [Contact]

    @State private var sortColumn: SortColumn = .name
    @State private var sortAscending = true
    @State private var selectedContacts: Set<UUID> = []
    @State private var showBatchAction = false
    @State private var filterOrbit: Int?
    @State private var showArchived = false
    @State private var searchText = ""

    enum SortColumn: String, CaseIterable {
        case name = "Name"
        case orbit = "Orbit"
        case lastContact = "Last Contact"
        case interactions = "Interactions"
        case artifacts = "Artifacts"
        case tags = "Tags"
    }

    private var filteredAndSorted: [Contact] {
        var result = allContacts

        // Archive filter
        if !showArchived {
            result = result.filter { !$0.isArchived }
        }

        // Orbit filter
        if let orbit = filterOrbit {
            result = result.filter { $0.targetOrbit == orbit }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.searchableName.contains(query) }
        }

        // Sort
        result.sort { a, b in
            let comparison: Bool
            switch sortColumn {
            case .name:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .orbit:
                comparison = a.targetOrbit < b.targetOrbit
            case .lastContact:
                comparison = (a.lastContactDate ?? .distantPast) > (b.lastContactDate ?? .distantPast)
            case .interactions:
                comparison = a.interactions.filter({ !$0.isDeleted }).count > b.interactions.filter({ !$0.isDeleted }).count
            case .artifacts:
                comparison = a.artifacts.count > b.artifacts.count
            case .tags:
                comparison = a.tags.count > b.tags.count
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with filters and batch actions
            filterBar

            Divider()

            // Table
            if filteredAndSorted.isEmpty {
                ContentUnavailableView(
                    "No Matching Contacts",
                    systemImage: "tablecells",
                    description: Text("Adjust your filters or add contacts.")
                )
            } else {
                tableContent
            }
        }
        .navigationTitle("Table View")
        .searchable(text: $searchText, prompt: "Filter by name")
        .sheet(isPresented: $showBatchAction) {
            BatchActionSheet(
                selectedCount: selectedContacts.count,
                onApply: { action in
                    applyBatchAction(action)
                    showBatchAction = false
                }
            )
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OrbitSpacing.sm) {
                // Orbit zone filter
                Menu {
                    Button("All Orbits") { filterOrbit = nil }
                    Divider()
                    ForEach(OrbitZone.allZones, id: \.id) { zone in
                        Button(zone.name) { filterOrbit = zone.id }
                    }
                } label: {
                    Label(
                        filterOrbit != nil ? OrbitZone.name(for: filterOrbit!) : "All Orbits",
                        systemImage: "circle.dotted"
                    )
                    .font(OrbitTypography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Toggle("Archived", isOn: $showArchived)
                    .toggleStyle(.button)
                    .controlSize(.small)

                Spacer()

                // Selection controls
                if !selectedContacts.isEmpty {
                    Text("\(selectedContacts.count) selected")
                        .font(OrbitTypography.captionMedium)
                        .foregroundStyle(.secondary)

                    Button("Batch Action") {
                        showBatchAction = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Clear") {
                        selectedContacts.removeAll()
                    }
                    .controlSize(.small)
                }

                // Select all
                Button(selectedContacts.count == filteredAndSorted.count ? "Deselect All" : "Select All") {
                    if selectedContacts.count == filteredAndSorted.count {
                        selectedContacts.removeAll()
                    } else {
                        selectedContacts = Set(filteredAndSorted.map(\.id))
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, OrbitSpacing.md)
            .padding(.vertical, OrbitSpacing.sm)
        }
    }

    // MARK: - Table Content

    private var tableContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header row
                tableHeaderRow

                Divider()

                // Data rows
                ForEach(filteredAndSorted) { contact in
                    tableDataRow(contact: contact)
                    Divider()
                }
            }
        }
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            // Checkbox column
            Color.clear
                .frame(width: 32)

            columnHeader("Name", column: .name, minWidth: 140)
            columnHeader("Orbit", column: .orbit, minWidth: 100)
            columnHeader("Last Contact", column: .lastContact, minWidth: 100)
            columnHeader("Interactions", column: .interactions, minWidth: 80)
            columnHeader("Tags", column: .tags, minWidth: 120)
        }
        .padding(.horizontal, OrbitSpacing.sm)
        .padding(.vertical, OrbitSpacing.sm)
        .background(Color.secondary.opacity(0.05))
    }

    private func columnHeader(_ title: String, column: SortColumn, minWidth: CGFloat) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(.secondary)

                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: minWidth, alignment: .leading)
    }

    private func tableDataRow(contact: Contact) -> some View {
        let isSelected = selectedContacts.contains(contact.id)

        #if os(iOS)
        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            HStack {
                Button {
                    if isSelected { selectedContacts.remove(contact.id) }
                    else { selectedContacts.insert(contact.id) }
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                
                Text(contact.name).font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                Spacer()
                Text(contact.orbitZoneName).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            
            HStack {
                Text("Last: \(contact.lastContactDate?.relativeDescription ?? "Never")")
                    .font(OrbitTypography.caption)
                Spacer()
                Text("Logs: \(contact.interactions.filter { !$0.isDeleted }.count)")
                    .font(OrbitTypography.caption)
            }
            
            if !contact.tags.isEmpty {
                Text(contact.tags.map(\.name).joined(separator: ", "))
                    .font(OrbitTypography.footnote).foregroundStyle(.tertiary)
            }
        }
        .padding(OrbitSpacing.sm)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selectedContacts.remove(contact.id) }
            else { selectedContacts.insert(contact.id) }
        }
        #else
        // Keep the existing HStack implementation for macOS
        #endif
    }

    // MARK: - Batch Actions

    private func applyBatchAction(_ action: BatchAction) {
        let descriptor = FetchDescriptor<Contact>()
        guard let allFetched = try? modelContext.fetch(descriptor) else { return }

        let targets = allFetched.filter { selectedContacts.contains($0.id) }

        switch action {
        case .setOrbit(let orbit):
            for contact in targets {
                contact.targetOrbit = orbit
                contact.modifiedAt = Date()
            }

        case .addTag(let tagName):
            // Find or create the tag
            let searchName = tagName.lowercased()
            let tagPredicate = #Predicate<Tag> { $0.searchableName == searchName }
            var tagDescriptor = FetchDescriptor<Tag>(predicate: tagPredicate)
            tagDescriptor.fetchLimit = 1

            let tag: Tag
            if let existing = try? modelContext.fetch(tagDescriptor).first {
                tag = existing
            } else {
                tag = Tag(name: tagName)
                modelContext.insert(tag)
            }

            for contact in targets {
                if !contact.tags.contains(where: { $0.searchableName == searchName }) {
                    contact.tags.append(tag)
                }
            }

        case .archive:
            for contact in targets {
                contact.isArchived = true
                contact.modifiedAt = Date()
            }

        case .restore:
            for contact in targets {
                contact.isArchived = false
                contact.modifiedAt = Date()
            }
        }

        selectedContacts.removeAll()
    }
}

// MARK: - Batch Action Types

enum BatchAction {
    case setOrbit(Int)
    case addTag(String)
    case archive
    case restore
}

// MARK: - Batch Action Sheet

struct BatchActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedCount: Int
    let onApply: (BatchAction) -> Void

    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Change Orbit Zone") {
                    ForEach(OrbitZone.allZones, id: \.id) { zone in
                        Button {
                            onApply(.setOrbit(zone.id))
                            dismiss()
                        } label: {
                            Label(zone.name, systemImage: "circle.dotted")
                        }
                    }
                }

                Section("Add Tag") {
                    HStack {
                        TextField("Tag name", text: $newTagName)
                        Button("Apply") {
                            let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                onApply(.addTag(trimmed))
                                dismiss()
                            }
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Button("Archive Selected") {
                        onApply(.archive)
                        dismiss()
                    }

                    Button("Restore Selected") {
                        onApply(.restore)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Batch Action (\(selectedCount) selected)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
