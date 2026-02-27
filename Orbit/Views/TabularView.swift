import SwiftUI
import SwiftData

// MARK: - TabularView
// Spreadsheet-like view for auditing and batch operations on contacts.
// Now features a sleek floating action bar for batch selections and
// advanced constellation management.

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
    
    // Search text shared from PeopleView
    @Binding var searchText: String

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

        if !showArchived {
            result = result.filter { !$0.isArchived }
        }

        if let orbit = filterOrbit {
            result = result.filter { $0.targetOrbit == orbit }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.searchableName.contains(query) }
        }

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
                comparison = a.activeInteractions.count > b.activeInteractions.count
            case .artifacts:
                comparison = a.artifacts.count > b.artifacts.count
            case .tags:
                comparison = a.aggregatedTags.count > b.aggregatedTags.count
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

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
        // The new Floating Action Bar for batch selections
        .overlay(alignment: .bottom) {
            if !selectedContacts.isEmpty {
                floatingActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedContacts.isEmpty)
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
                    
                    // 1. ADD THIS: iOS-only Sort Menu
                    #if os(iOS)
                    Menu {
                        ForEach(SortColumn.allCases, id: \.self) { column in
                            Button {
                                if sortColumn == column {
                                    sortAscending.toggle()
                                } else {
                                    sortColumn = column
                                    sortAscending = true
                                }
                            } label: {
                                if sortColumn == column {
                                    Label(column.rawValue, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                                } else {
                                    Text(column.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label("Sort: \(sortColumn.rawValue)", systemImage: "arrow.up.arrow.down")
                            .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    #endif
                    
                    // Existing Orbit Filter
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

                    // Existing Archived Toggle
                    Toggle("Archived", isOn: $showArchived)
                        .toggleStyle(.button)
                        .controlSize(.small)
                }
                .padding(.horizontal, OrbitSpacing.md)
                .padding(.vertical, OrbitSpacing.sm)
            }
        }

    // MARK: - Floating Action Bar

    private var floatingActionBar: some View {
        HStack(spacing: OrbitSpacing.md) {
            Text("\(selectedContacts.count) selected")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(.primary)
            
            Divider()
                .frame(height: 16)
            
            Button("Select All") {
                selectedContacts = Set(filteredAndSorted.map(\.id))
            }
            .font(OrbitTypography.caption)
            .foregroundStyle(.blue)
            
            Spacer()
            
            Button {
                selectedContacts.removeAll()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Button {
                showBatchAction = true
            } label: {
                Label("Batch Actions", systemImage: "sparkles")
                    .font(OrbitTypography.captionMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
        }
        .padding(.horizontal, OrbitSpacing.lg)
        .padding(.vertical, OrbitSpacing.sm)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.bottom, OrbitSpacing.lg)
    }

    // MARK: - Table Content

        private var tableContent: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    
                    #if os(macOS)
                    tableHeaderRow
                    Divider()
                    #endif
                    
                    ForEach(filteredAndSorted) { contact in
                        tableDataRow(contact: contact)
                        Divider()
                    }
                }
                .padding(.bottom, selectedContacts.isEmpty ? 0 : 80)
            }
        }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 32)
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
        let tagDisplay = contact.aggregatedTags.prefix(3).map { "#\($0.name)" }.joined(separator: ", ")

        #if os(iOS)
        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            HStack {
                Button {
                    toggleSelection(for: contact.id)
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
                Text("Logs: \(contact.activeInteractions.count)")
                    .font(OrbitTypography.caption)
            }

            if !tagDisplay.isEmpty {
                Text(tagDisplay)
                    .font(OrbitTypography.footnote).foregroundStyle(.tertiary)
            }
        }
        .padding(OrbitSpacing.sm)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: contact.id)
        }
        #else
        return HStack(spacing: 0) {
            Button {
                toggleSelection(for: contact.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 32)

            Text(contact.name)
                .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                .frame(minWidth: 140, alignment: .leading)

            Text(contact.orbitZoneName)
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)

            Text(contact.lastContactDate?.relativeDescription ?? "Never")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)

            Text("\(contact.activeInteractions.count)")
                .font(OrbitTypography.caption)
                .frame(minWidth: 80, alignment: .leading)

            Text(tagDisplay)
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
        }
        .padding(.horizontal, OrbitSpacing.sm)
        .padding(.vertical, OrbitSpacing.xs)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: contact.id)
        }
        #endif
    }
    
    private func toggleSelection(for id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedContacts.contains(id) {
                selectedContacts.remove(id)
            } else {
                selectedContacts.insert(id)
            }
        }
    }

    // MARK: - Batch Actions Implementation

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
            
        case .addToConstellation(let constellation):
            for contact in targets {
                if !contact.constellations.contains(where: { $0.id == constellation.id }) {
                    contact.constellations.append(constellation)
                    contact.modifiedAt = Date()
                }
            }
            
        case .removeFromConstellation(let constellation):
            for contact in targets {
                contact.constellations.removeAll(where: { $0.id == constellation.id })
                contact.modifiedAt = Date()
            }
        }

        try? modelContext.save()
        withAnimation {
            selectedContacts.removeAll()
        }
    }
}

// MARK: - Batch Action Types
enum BatchAction {
    case setOrbit(Int)
    case archive
    case restore
    case addToConstellation(Constellation)
    case removeFromConstellation(Constellation)
}

// MARK: - Batch Action Sheet
struct BatchActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    // Query constellations to populate the new batch menus
    @Query(sort: \Constellation.name) private var constellations: [Constellation]

    let selectedCount: Int
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
                
                if !constellations.isEmpty {
                    Section("Constellations") {
                        Menu {
                            ForEach(constellations) { constellation in
                                Button(constellation.name) {
                                    onApply(.addToConstellation(constellation))
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Add to Constellation...", systemImage: "star.fill")
                        }
                        
                        Menu {
                            ForEach(constellations) { constellation in
                                Button(constellation.name) {
                                    onApply(.removeFromConstellation(constellation))
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Remove from Constellation...", systemImage: "star.slash")
                        }
                    }
                }

                Section("Archive") {
                    Button("Archive Selected") {
                        onApply(.archive)
                        dismiss()
                    }
                    .foregroundStyle(.orange)

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
