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

    @Query(sort: \Constellation.name)
    private var constellations: [Constellation]

    @State private var sortBy: SortOption = .name
    @State private var sortAscending = true
    @State private var selectedContacts: Set<UUID> = []
    @State private var showBatchAction = false
    @State private var filterOrbit: Int?
    @State private var showArchived = false
    @State private var searchText = ""
    @State private var groupBy: GroupOption = .none

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case orbit = "Orbit"
        case lastContact = "Last Contact"
        case interactions = "Interactions"
    }

    enum GroupOption: String, CaseIterable {
        case none = "None"
        case orbit = "Orbit Zone"
        case constellation = "Constellation"
    }

    // MARK: - Filtering & Sorting

    private var filteredAndSorted: [Contact] {
        var result = allContacts

        if !showArchived {
            result = result.filter { !$0.isArchived }
        }

        if let orbit = filterOrbit {
            result = result.filter { $0.targetOrbit == orbit }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.searchableName.contains(query)
                || $0.constellations.contains(where: { $0.searchableName.contains(query) })
                || $0.tagNames.contains(where: { $0.contains(query) })
            }
        }

        result.sort { a, b in
            let comparison: Bool
            switch sortBy {
            case .name:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .orbit:
                comparison = a.targetOrbit < b.targetOrbit
            case .lastContact:
                comparison = (a.lastContactDate ?? .distantPast) > (b.lastContactDate ?? .distantPast)
            case .interactions:
                comparison = a.interactions.filter({ !$0.isDeleted }).count > b.interactions.filter({ !$0.isDeleted }).count
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    // MARK: - Grouping

    private var groupedContacts: [(title: String, contacts: [Contact])] {
        let contacts = filteredAndSorted

        switch groupBy {
        case .none:
            return [(title: "", contacts: contacts)]

        case .orbit:
            let grouped = Dictionary(grouping: contacts) { $0.targetOrbit }
            return OrbitZone.allZones.compactMap { zone in
                guard let members = grouped[zone.id], !members.isEmpty else { return nil }
                return (title: zone.name, contacts: members)
            }

        case .constellation:
            // Group by constellation. Contacts can appear in multiple groups.
            // Also include an "Ungrouped" section for contacts with no constellation.
            var sections: [(title: String, contacts: [Contact])] = []

            for constellation in constellations {
                let members = contacts.filter { contact in
                    contact.constellations.contains(where: { $0.id == constellation.id })
                }
                if !members.isEmpty {
                    sections.append((title: constellation.name, contacts: members))
                }
            }

            let ungrouped = contacts.filter { $0.constellations.isEmpty }
            if !ungrouped.isEmpty {
                sections.append((title: "Ungrouped", contacts: ungrouped))
            }

            return sections
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()

            if filteredAndSorted.isEmpty {
                ContentUnavailableView(
                    "No Matching Contacts",
                    systemImage: "tablecells",
                    description: Text("Adjust your filters or add contacts.")
                )
            } else {
                contactList
            }
        }
        .navigationTitle("Table View")
        .searchable(text: $searchText, prompt: "Filter by name, tag, or constellation")
        .sheet(isPresented: $showBatchAction) {
            BatchActionSheet(
                selectedCount: selectedContacts.count,
                constellations: constellations,
                onApply: { action in
                    applyBatchAction(action)
                    showBatchAction = false
                }
            )
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: OrbitSpacing.sm) {
            // Top row: filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OrbitSpacing.sm) {
                    // Group by
                    Menu {
                        ForEach(GroupOption.allCases, id: \.self) { option in
                            Button {
                                groupBy = option
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if groupBy == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(
                            groupBy == .none ? "Group" : groupBy.rawValue,
                            systemImage: "rectangle.3.group"
                        )
                        .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Sort by
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                if sortBy == option {
                                    sortAscending.toggle()
                                } else {
                                    sortBy = option
                                    sortAscending = true
                                }
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if sortBy == option {
                                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Sort: \(sortBy.rawValue)", systemImage: "arrow.up.arrow.down")
                            .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Orbit filter
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
                }
                .padding(.horizontal, OrbitSpacing.md)
            }

            // Bottom row: selection controls
            if !selectedContacts.isEmpty || !filteredAndSorted.isEmpty {
                HStack(spacing: OrbitSpacing.sm) {
                    // Select all / deselect
                    Button(selectedContacts.count == filteredAndSorted.count ? "Deselect All" : "Select All") {
                        if selectedContacts.count == filteredAndSorted.count {
                            selectedContacts.removeAll()
                        } else {
                            selectedContacts = Set(filteredAndSorted.map(\.id))
                        }
                    }
                    .controlSize(.small)
                    .font(OrbitTypography.caption)

                    Spacer()

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

                    Text("\(filteredAndSorted.count) contact\(filteredAndSorted.count == 1 ? "" : "s")")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, OrbitSpacing.md)
            }
        }
        .padding(.vertical, OrbitSpacing.sm)
    }

    // MARK: - Contact List

    private var contactList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: groupBy != .none ? [.sectionHeaders] : []) {
                ForEach(groupedContacts, id: \.title) { group in
                    Section {
                        ForEach(group.contacts) { contact in
                            contactCard(contact)
                            Divider()
                                .padding(.leading, OrbitSpacing.xxl)
                        }
                    } header: {
                        if !group.title.isEmpty {
                            sectionHeader(group.title, count: group.contacts.count)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: OrbitSpacing.sm) {
            if groupBy == .constellation {
                Image(systemName: "star.circle.fill")
                    .font(.caption)
                    .foregroundStyle(title == "Ungrouped" ? .secondary : OrbitColors.syntaxConstellation)
            }

            Text(title.uppercased())
                .font(OrbitTypography.captionMedium)
                .tracking(1)
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Contact Card

    private func contactCard(_ contact: Contact) -> some View {
        let isSelected = selectedContacts.contains(contact.id)
        let activeCount = contact.interactions.filter { !$0.isDeleted }.count

        return HStack(alignment: .top, spacing: OrbitSpacing.md) {
            // Selection checkbox
            Button {
                if isSelected { selectedContacts.remove(contact.id) }
                else { selectedContacts.insert(contact.id) }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                // Name + orbit
                HStack(alignment: .firstTextBaseline) {
                    Text(contact.name)
                        .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                        .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                    Spacer()

                    Text(contact.orbitZoneName)
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }

                // Metadata row
                HStack(spacing: OrbitSpacing.md) {
                    Label(
                        contact.lastContactDate?.relativeDescription ?? "Never",
                        systemImage: "clock"
                    )
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text("\(activeCount) log\(activeCount == 1 ? "" : "s")")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                }

                // Tags (aggregated from interactions)
                if !contact.aggregatedTags.isEmpty {
                    Text(
                        contact.aggregatedTags.prefix(5).map { tag in
                            tag.count > 1 ? "#\(tag.name) ×\(tag.count)" : "#\(tag.name)"
                        }.joined(separator: "  ")
                    )
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(OrbitColors.syntaxTag.opacity(0.7))
                    .lineLimit(1)
                }

                // Constellations
                if !contact.constellations.isEmpty {
                    Text(
                        contact.constellations.map { "★ \($0.name)" }.joined(separator: "  ")
                    )
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(OrbitColors.syntaxConstellation.opacity(0.7))
                    .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm)
        .background(isSelected ? Color.blue.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selectedContacts.remove(contact.id) }
            else { selectedContacts.insert(contact.id) }
        }
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

        case .addToConstellation(let constellation):
            for contact in targets {
                if !contact.constellations.contains(where: { $0.id == constellation.id }) {
                    contact.constellations.append(constellation)
                }
            }

        case .removeFromConstellation(let constellation):
            for contact in targets {
                contact.constellations.removeAll { $0.id == constellation.id }
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
    case addToConstellation(Constellation)
    case removeFromConstellation(Constellation)
    case archive
    case restore
}

// MARK: - Batch Action Sheet

struct BatchActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedCount: Int
    let constellations: [Constellation]
    let onApply: (BatchAction) -> Void

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

                Section("Add to Constellation") {
                    if constellations.isEmpty {
                        Text("No constellations yet. Create one first.")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(constellations) { constellation in
                            Button {
                                onApply(.addToConstellation(constellation))
                                dismiss()
                            } label: {
                                Label {
                                    HStack {
                                        Text(constellation.name)
                                        Spacer()
                                        Text("\(constellation.contacts.count) members")
                                            .font(OrbitTypography.footnote)
                                            .foregroundStyle(.tertiary)
                                    }
                                } icon: {
                                    Image(systemName: "star.circle")
                                        .foregroundStyle(OrbitColors.syntaxConstellation)
                                }
                            }
                        }
                    }
                }

                if !constellations.isEmpty {
                    Section("Remove from Constellation") {
                        ForEach(constellations) { constellation in
                            Button {
                                onApply(.removeFromConstellation(constellation))
                                dismiss()
                            } label: {
                                Label {
                                    Text(constellation.name)
                                } icon: {
                                    Image(systemName: "star.slash")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
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
