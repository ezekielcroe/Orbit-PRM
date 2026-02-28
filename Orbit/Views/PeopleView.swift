import SwiftUI
import SwiftData

// MARK: - Row Geometry Tracking for Drag-to-Select
struct RowFrameData: Equatable {
    let id: UUID
    let frame: CGRect
}

struct RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [RowFrameData] = []
    static func reduce(value: inout [RowFrameData], nextValue: () -> [RowFrameData]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - PeopleView

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Binding var selectedContact: Contact?
    @Binding var showCommandPalette: Bool
    @Binding var showSettings: Bool

    @Query(sort: [SortDescriptor(\Contact.name)])
    private var allContacts: [Contact]
    
    @Query(sort: \Constellation.name)
    private var allConstellations: [Constellation]
    
    @Query(sort: \Tag.name)
    private var allTags: [Tag]

    // Navigation and Sort State
    @State private var searchText = ""
    @State private var sortColumn: SortColumn = .name
    @State private var sortAscending = true
    @State private var selectedContacts: Set<UUID> = []
    @State private var showBatchAction = false
    @State private var showAddContact = false
    
    // Filter State
    @State private var filterOrbit: Int?
    @State private var filterConstellation: Constellation?
    @State private var filterTag: Tag?
    @State private var filterInteractions: ActivityFilter = .any
    @State private var filterArtifacts: ArtifactFilter = .any
    @State private var showArchived = false

    // Drag-to-select State
    @State private var rowFrames: [RowFrameData] = []
    @State private var dragSelectionState: Bool? = nil
    @State private var isScrubbing = false

    enum SortColumn: String, CaseIterable {
        case name = "Name"
        case orbit = "Orbit"
        case constellation = "Constellation"
        case lastContact = "Last Contact"
    }

    enum ActivityFilter: String, CaseIterable {
        case any = "Any Activity"
        case hasLogs = "Has Logs"
        case noLogs = "No Logs"
    }

    enum ArtifactFilter: String, CaseIterable {
        case any = "Any Artifacts"
        case hasArtifacts = "Has Artifacts"
        case noArtifacts = "No Artifacts"
    }

    // ┌─────────────────────────────────────────────────────────────┐
    // │ FIX P0-1.2: Filters now use cached fields                   │
    // │                                                              │
    // │ Changed lines marked with // FIX: was ...                   │
    // └─────────────────────────────────────────────────────────────┘
    private var filteredAndSorted: [Contact] {
        var result = allContacts

        if !showArchived {
            result = result.filter { !$0.isArchived }
        }

        if let orbit = filterOrbit {
            result = result.filter { $0.targetOrbit == orbit }
        }
        
        if let const = filterConstellation {
            result = result.filter { ($0.constellations ?? []).contains(where: { $0.id == const.id }) }
        }
        
        // FIX: was `$0.hasInteractionTag(tag.searchableName)` — traversed all interactions
        if let tag = filterTag {
            result = result.filter { $0.hasCachedTag(tag.searchableName) }
        }
        
        // FIX: was `!$0.activeInteractions.isEmpty` — filtered+sorted ALL interactions
        if filterInteractions == .hasLogs {
            result = result.filter { $0.cachedInteractionCount > 0 }
        } else if filterInteractions == .noLogs {
            result = result.filter { $0.cachedInteractionCount == 0 }
        }
        
        // FIX: was `!($0.artifacts ?? []).isEmpty` — faulted the relationship
        if filterArtifacts == .hasArtifacts {
            result = result.filter { $0.cachedHasArtifacts }
        } else if filterArtifacts == .noArtifacts {
            result = result.filter { !$0.cachedHasArtifacts }
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
            case .constellation:
                let aConst = a.constellations?.first?.name ?? "zzzz"
                let bConst = b.constellations?.first?.name ?? "zzzz"
                comparison = aConst.localizedCaseInsensitiveCompare(bConst) == .orderedAscending
            case .lastContact:
                comparison = (a.lastContactDate ?? .distantPast) > (b.lastContactDate ?? .distantPast)
            }
            return sortAscending ? comparison : !comparison
        }

        return result
    }

    var body: some View {
            ZStack(alignment: .bottom) {
                if filteredAndSorted.isEmpty {
                    ContentUnavailableView(
                        "No Matching Contacts",
                        systemImage: "tablecells",
                        description: Text("Adjust your filters or add contacts.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    tableContent
                }
            }
            .navigationTitle("People")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControls
            }
            .overlay(alignment: .bottomTrailing) {
                if selectedContacts.isEmpty {
                    floatingToolbarPill
                        .transition(.scale.combined(with: .opacity))
                        .padding(.trailing, OrbitSpacing.lg)
                        .padding(.bottom, 120)
                }
            }
            .overlay(alignment: .bottom) {
                if !selectedContacts.isEmpty {
                    floatingActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, OrbitSpacing.xl)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedContacts.isEmpty)
        .sheet(isPresented: $showBatchAction) {
            BatchActionSheet(
                selectedCount: selectedContacts.count,
                onApply: { edit in
                    applyBatchEdit(edit)
                    showBatchAction = false
                }
            )
        }
        .sheet(isPresented: $showAddContact) {
            ContactFormSheet(mode: .add) { newContact in
                selectedContact = newContact
            }
        }
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
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: RowFramePreferenceKey.self,
                                        value: [RowFrameData(id: contact.id, frame: geo.frame(in: .named("TableSpace")))]
                                    )
                                }
                            )
                        Divider()
                    }
                    Color.clear
                        .frame(height: 100)
                }
            }
            .scrollDisabled(isScrubbing)
            .coordinateSpace(name: "TableSpace")
            .onPreferenceChange(RowFramePreferenceKey.self) { frames in
                self.rowFrames = frames
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard value.startLocation.x < 50 else { return }

                        if !isScrubbing {
                            isScrubbing = true
                        }

                        if let row = rowFrames.first(where: { $0.frame.minY <= value.location.y && $0.frame.maxY >= value.location.y }) {
                            if dragSelectionState == nil {
                                dragSelectionState = !selectedContacts.contains(row.id)
                            }

                            if dragSelectionState == true {
                                selectedContacts.insert(row.id)
                            } else {
                                selectedContacts.remove(row.id)
                            }
                        }
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        dragSelectionState = nil
                    }
            )
        }

    #if os(macOS)
    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 32)
            columnHeader("Name", column: .name, minWidth: 140)
            columnHeader("Orbit", column: .orbit, minWidth: 100)
            columnHeader("Constellation", column: .constellation, minWidth: 120)
            columnHeader("Last Contact", column: .lastContact, minWidth: 100)
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
    #endif

    private func tableDataRow(contact: Contact) -> some View {
        let isSelected = selectedContacts.contains(contact.id)
        // FIX P0-1.1: Use cachedTagSummary instead of aggregatedTags.
        // Before: contact.aggregatedTags.prefix(3).map { "#\($0.name)" }.joined(separator: ", ")
        // That traversed all interactions → flatMapped tags → built dictionary → sorted → sliced.
        let tagDisplay = contact.cachedTagSummary.isEmpty ? "" :
            contact.cachedTagSummary.split(separator: ",").prefix(3).map { "#\($0)" }.joined(separator: ", ")

        #if os(iOS)
        return HStack(alignment: .top, spacing: OrbitSpacing.md) {
            // Checkbox Column
            Button {
                toggleSelection(for: contact.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .padding(.vertical, OrbitSpacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Contact Detail Column
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                HStack {
                    Text(contact.name).font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    Spacer()
                    Text(contact.orbitZoneName).font(OrbitTypography.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Text("Last: \(contact.lastContactDate?.relativeDescription ?? "Never")")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let const = contact.constellations?.first {
                        Text("✦ \(const.name)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.purple)
                    }
                }

                if !tagDisplay.isEmpty {
                    Text(tagDisplay)
                        .font(OrbitTypography.footnote).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, OrbitSpacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedContact = contact
            }
        }
        .padding(.horizontal, OrbitSpacing.sm)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        
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
                .contentShape(Rectangle())
                .onTapGesture { selectedContact = contact }

            Text(contact.orbitZoneName)
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { selectedContact = contact }
            
            Text(contact.constellations?.first?.name ?? "--")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { selectedContact = contact }

            Text(contact.lastContactDate?.relativeDescription ?? "Never")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { selectedContact = contact }
        }
        .padding(.horizontal, OrbitSpacing.sm)
        .padding(.vertical, OrbitSpacing.xs)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
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

    // MARK: - Breathable Bottom Controls
    
    private var bottomControls: some View {
            VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                // Search Bar Component
                HStack(spacing: OrbitSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search table...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(OrbitSpacing.sm)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            // Sort Section
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OrbitSpacing.sm) {
                    Text("SORT")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1)
                        .foregroundStyle(.tertiary)
                    
                    ForEach(SortColumn.allCases, id: \.self) { column in
                        Button {
                            if sortColumn == column {
                                sortAscending.toggle()
                            } else {
                                sortColumn = column
                                sortAscending = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(column.rawValue)
                                if sortColumn == column {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .font(OrbitTypography.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(sortColumn == column ? .blue : .secondary)
                        .controlSize(.small)
                    }
                }
            }

            // Filter Section
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OrbitSpacing.sm) {
                    Text("FILTER")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1)
                        .foregroundStyle(.tertiary)

                    // Orbit Menu
                    Menu {
                        Button("Any Orbit") { filterOrbit = nil }
                        Divider()
                        ForEach(OrbitZone.allZones, id: \.id) { zone in
                            Button(zone.name) { filterOrbit = zone.id }
                        }
                    } label: {
                        Label(filterOrbit != nil ? OrbitZone.name(for: filterOrbit!) : "Orbit", systemImage: "circle.dotted")
                            .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(filterOrbit != nil ? .blue : .secondary)
                    .controlSize(.small)

                    // Constellation Menu
                    if !allConstellations.isEmpty {
                        Menu {
                            Button("Any Constellation") { filterConstellation = nil }
                            Divider()
                            ForEach(allConstellations) { c in
                                Button("✦ \(c.name)") { filterConstellation = c }
                            }
                        } label: {
                            Label(filterConstellation?.name ?? "Constellation", systemImage: "star")
                                .font(OrbitTypography.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(filterConstellation != nil ? .blue : .secondary)
                        .controlSize(.small)
                    }

                    // Tags Menu
                    if !allTags.isEmpty {
                        Menu {
                            Button("Any Tag") { filterTag = nil }
                            Divider()
                            ForEach(allTags) { t in
                                Button("#\(t.name)") { filterTag = t }
                            }
                        } label: {
                            Label(filterTag != nil ? "#\(filterTag!.name)" : "Tags", systemImage: "tag")
                                .font(OrbitTypography.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(filterTag != nil ? .blue : .secondary)
                        .controlSize(.small)
                    }

                    // Interactions Menu
                    Menu {
                        ForEach(ActivityFilter.allCases, id: \.self) { f in
                            Button(f.rawValue) { filterInteractions = f }
                        }
                    } label: {
                        Label(filterInteractions.rawValue, systemImage: "bubble.left.and.exclamationmark.bubble.right")
                            .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(filterInteractions != .any ? .blue : .secondary)
                    .controlSize(.small)

                    // Artifacts Menu
                    Menu {
                        ForEach(ArtifactFilter.allCases, id: \.self) { f in
                            Button(f.rawValue) { filterArtifacts = f }
                        }
                    } label: {
                        Label(filterArtifacts.rawValue, systemImage: "tray")
                            .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(filterArtifacts != .any ? .blue : .secondary)
                    .controlSize(.small)

                    // Archived Toggle
                    Toggle("Archived", isOn: $showArchived)
                        .toggleStyle(.button)
                        .tint(showArchived ? .blue : .secondary)
                        .controlSize(.small)
                }
            }
        }
        .padding(OrbitSpacing.md)
        .background(.regularMaterial)
    }

    // MARK: - Floating Toolbars
    
    private var floatingToolbarPill: some View {
        HStack(spacing: 0) {
            Button {
                showAddContact = true
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.title3.weight(.medium))
                    .frame(width: 56, height: 56)
            }
            .help("Add Contact")
            
            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.4))
            
            Button {
                showCommandPalette = true
            } label: {
                Image(systemName: "command")
                    .font(.title3.weight(.medium))
                    .frame(width: 56, height: 56)
            }
            .help("Quick Log (⌘K)")
        }
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

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
                Label("Edit", systemImage: "sparkles")
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
    }

    // MARK: - Batch Edit Implementation

    private func applyBatchEdit(_ edit: BatchEdit) {
        let descriptor = FetchDescriptor<Contact>()
        guard let allFetched = try? modelContext.fetch(descriptor) else { return }

        let targets = allFetched.filter { selectedContacts.contains($0.id) }

        // Handle delete (overrides everything else)
        if edit.deleteAll {
            for contact in targets {
                spotlightIndexer.deindex(contact: contact)
                modelContext.delete(contact)
            }
            PersistenceHelper.saveWithLogging(modelContext, operation: "batch delete contacts")
            withAnimation { selectedContacts.removeAll() }
            return
        }

        // Apply orbit change
        if let orbit = edit.orbitZone {
            for contact in targets {
                contact.targetOrbit = orbit
                contact.modifiedAt = Date()
            }
        }

        // Apply archive status
        switch edit.archiveStatus {
        case .archive:
            for contact in targets {
                contact.isArchived = true
                contact.modifiedAt = Date()
                spotlightIndexer.deindex(contact: contact)
            }
        case .unarchive:
            for contact in targets {
                contact.isArchived = false
                contact.modifiedAt = Date()
                spotlightIndexer.index(contact: contact)
            }
        case .noChange:
            break
        }

        // Apply constellation additions
        if !edit.constellationsToAdd.isEmpty {
            let constellationDescriptor = FetchDescriptor<Constellation>()
            if let allConstellations = try? modelContext.fetch(constellationDescriptor) {
                let toAdd = allConstellations.filter { edit.constellationsToAdd.contains($0.id) }
                for contact in targets {
                    for constellation in toAdd {
                        if !(contact.constellations?.contains(where: { $0.id == constellation.id }) ?? false) {
                            if contact.constellations == nil { contact.constellations = [] }
                            contact.constellations?.append(constellation)
                            contact.modifiedAt = Date()
                        }
                    }
                }
            }
        }

        // Apply constellation removals
        if !edit.constellationsToRemove.isEmpty {
            for contact in targets {
                contact.constellations?.removeAll { edit.constellationsToRemove.contains($0.id) }
                contact.modifiedAt = Date()
            }
        }

        PersistenceHelper.saveWithLogging(modelContext, operation: "batch edit contacts")
        withAnimation {
            selectedContacts.removeAll()
        }
    }
}
