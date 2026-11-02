import SwiftUI
import SwiftData

// MARK: - PeopleView
// Finding people, not administering a table. Search covers names, notes,
// facts, tags and groups ("google", "jazz", "book club"). Filters live in a
// sheet instead of a permanent wall of menus. On iPhone the list is a native
// List: swipe to log or archive, Edit to multi-select. On Mac it stays a
// sortable Table with context menus.

struct PeopleFilter: Equatable {
    enum Activity: String, CaseIterable { case any = "Any", hasLogs = "Has logs", noLogs = "No logs" }
    enum Facts: String, CaseIterable { case any = "Any", has = "Has facts", none = "No facts" }

    var orbit: Int?
    var groupID: UUID?
    var tag: String?
    var activity: Activity = .any
    var facts: Facts = .any
    var dueOnly = false
    var showArchived = false

    var activeCount: Int {
        [orbit != nil, groupID != nil, tag != nil, activity != .any, facts != .any, dueOnly, showArchived]
            .filter { $0 }.count
    }
}

struct PeopleView: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Binding var selectedContact: Contact?

    @Query(sort: [SortDescriptor(\Contact.name)]) private var allContacts: [Contact]
    @Query(sort: \Constellation.name) private var allGroups: [Constellation]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var searchText = ""
    @State private var filter = PeopleFilter()
    @State private var showFilters = false
    @State private var sort: SortColumn = .name
    @State private var selection: Set<UUID> = []
    @State private var showBatchEdit = false

    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #else
    @State private var sortOrder = [KeyPathComparator(\Contact.name)]
    #endif

    enum SortColumn: String, CaseIterable {
        case name = "Name"
        case lastContact = "Last contact"
        case closeness = "Closeness"
        case due = "Most overdue"
    }

    // MARK: - Data

    private var filtered: [Contact] {
        var result = allContacts.filter { filter.showArchived || !$0.isArchived }
        if let orbit = filter.orbit { result = result.filter { $0.targetOrbit == orbit } }
        if let groupID = filter.groupID {
            result = result.filter { ($0.constellations ?? []).contains(where: { $0.id == groupID }) }
        }
        if let tag = filter.tag { result = result.filter { $0.hasCachedTag(tag) } }
        switch filter.activity {
        case .any: break
        case .hasLogs: result = result.filter { $0.cachedInteractionCount > 0 }
        case .noLogs: result = result.filter { $0.cachedInteractionCount == 0 }
        }
        switch filter.facts {
        case .any: break
        case .has: result = result.filter(\.cachedHasArtifacts)
        case .none: result = result.filter { !$0.cachedHasArtifacts }
        }
        if filter.dueOnly { result = result.filter(\.isDrifting) }
        if !searchText.isEmpty { result = result.filter { $0.matchesSearch(searchText) } }

        #if os(macOS)
        result.sort(using: sortOrder)
        #else
        switch sort {
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastContact: result.sort { ($0.lastContactDate ?? .distantPast) > ($1.lastContactDate ?? .distantPast) }
        case .closeness: result.sort { ($0.targetOrbit, $0.name) < ($1.targetOrbit, $1.name) }
        case .due: result.sort { $0.driftPriority > $1.driftPriority }
        }
        #endif
        return result
    }

    private var selectedContacts: [Contact] {
        allContacts.filter { selection.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle("People")
            .searchable(text: $searchText, prompt: "Search names, notes, facts, tags")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showFilters) {
                PeopleFilterSheet(filter: $filter, groups: allGroups, tags: allTags.map(\.name))
            }
            .sheet(isPresented: $showBatchEdit) {
                BatchActionSheet(selectedCount: selection.count) { edit in
                    apply(edit)
                    showBatchEdit = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState
        } else {
            #if os(macOS)
            macTable
            #else
            phoneList
            #endif
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if allContacts.isEmpty {
            ContentUnavailableView {
                Label("No one here yet", systemImage: "person.2")
            } description: {
                Text("Add someone, import from Contacts in Settings, or just log a catch-up and Orbit will add them.")
            } actions: {
                Button("Add someone") { router.showNewContact = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("No matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No one matches these filters.")
            } actions: {
                Button("Clear filters") { filter = PeopleFilter() }
            }
        }
    }

    // MARK: - iPhone / iPad list

    #if os(iOS)
    private var phoneList: some View {
        List(selection: $selection) {
            ForEach(filtered) { contact in
                Group {
                    if editMode.isEditing {
                        row(contact)
                    } else {
                        Button { selectedContact = contact } label: { row(contact) }
                            .buttonStyle(.plain)
                    }
                }
                .tag(contact.id)
                .swipeActions(edge: .leading) {
                    Button { router.log([contact]) } label: { Label("Log", systemImage: "plus.bubble") }
                        .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button { store.setArchived(!contact.isArchived, for: [contact]) } label: {
                        Label(contact.isArchived ? "Restore" : "Archive", systemImage: "archivebox")
                    }
                    .tint(.gray)
                }
                .contextMenu { contextActions(for: [contact]) }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .onChange(of: editMode) { _, mode in
            if !mode.isEditing { selection.removeAll() }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                HStack {
                    Button(selection.count == filtered.count ? "Select none" : "Select all") {
                        selection = selection.count == filtered.count ? [] : Set(filtered.map(\.id))
                    }
                    Spacer()
                    Text("\(selection.count) selected").font(OrbitTypography.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit…") { showBatchEdit = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(selection.isEmpty)
                }
                .padding(OrbitSpacing.md)
                .background(.regularMaterial)
            }
        }
    }
    #endif

    private func row(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .foregroundStyle(contact.isArchived ? .secondary : .primary)
                Spacer()
                Text(contact.lastContactDate?.relativeDescription ?? "Never")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(contact.isDrifting ? AnyShapeStyle(contact.driftColor) : AnyShapeStyle(.secondary))
            }
            Text(subtitle(for: contact))
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func subtitle(for contact: Contact) -> String {
        var parts = [contact.closenessConfirmed || contact.cachedInteractionCount > 0 ? contact.orbitZoneName : "Closeness not set"]
        if let group = contact.constellations?.first { parts.append("✦ \(group.name)") }
        let tags = contact.cachedTagSummary.split(separator: ",").prefix(2).map { "#\($0)" }
        if !tags.isEmpty { parts.append(tags.joined(separator: " ")) }
        if contact.isArchived { parts.append("Archived") }
        if contact.isSnoozed { parts.append("Snoozed") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Mac table

    #if os(macOS)
    private var macTable: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { contact in
                Text(contact.name).font(OrbitTypography.contactName(orbit: contact.targetOrbit))
            }
            .width(min: 140, ideal: 200)

            TableColumn("Closeness", value: \.targetOrbit) { contact in
                Text(contact.orbitZoneName).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            .width(ideal: 110)

            TableColumn("Group", value: \.sortableConstellationName) { contact in
                Text(contact.constellations?.first?.name ?? "—").font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            .width(ideal: 120)

            TableColumn("Tags", value: \.sortableTags) { contact in
                let tags = contact.cachedTagSummary.split(separator: ",").prefix(3).map { "#\($0)" }.joined(separator: " ")
                Text(tags.isEmpty ? "—" : tags).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            .width(ideal: 150)

            TableColumn("Last contact", value: \.sortableLastContactDate) { contact in
                Text(contact.lastContactDate?.relativeDescription ?? "Never")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(contact.isDrifting ? AnyShapeStyle(contact.driftColor) : AnyShapeStyle(.secondary))
            }
            .width(ideal: 110)
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection.count == 1, let id = newSelection.first {
                selectedContact = allContacts.first(where: { $0.id == id })
            }
        }
        .contextMenu(forSelectionType: Contact.ID.self) { ids in
            let targets = allContacts.filter { ids.contains($0.id) }
            if !targets.isEmpty { contextActions(for: targets) }
        } primaryAction: { ids in
            if let id = ids.first, let contact = allContacts.first(where: { $0.id == id }) {
                selectedContact = contact
            }
        }
    }
    #endif

    // MARK: - Shared actions

    @ViewBuilder
    private func contextActions(for targets: [Contact]) -> some View {
        Button("Log…", systemImage: "plus.bubble") { router.log(targets) }
        Menu("Closeness") {
            ForEach(OrbitZone.allZones, id: \.id) { zone in
                Button("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))") {
                    store.setCloseness(zone.id, for: targets)
                }
            }
        }
        if targets.count == 1, let only = targets.first {
            Button("Open", systemImage: "arrow.right") { selectedContact = only }
        } else {
            Button("Edit \(targets.count) people…", systemImage: "slider.horizontal.3") {
                selection = Set(targets.map(\.id))
                showBatchEdit = true
            }
        }
        Divider()
        let allArchived = targets.allSatisfy(\.isArchived)
        Button(allArchived ? "Restore" : "Archive", systemImage: "archivebox") {
            store.setArchived(!allArchived, for: targets)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showFilters = true } label: {
                Label(filter.activeCount > 0 ? "Filters (\(filter.activeCount))" : "Filters",
                      systemImage: filter.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            #if os(iOS)
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(SortColumn.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            #endif
            Button { router.showNewContact = true } label: {
                Label("Add person", systemImage: "person.badge.plus")
            }
        }
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        #else
        ToolbarItem {
            Button("Edit \(selection.count)…") { showBatchEdit = true }
                .disabled(selection.count < 2)
        }
        #endif
    }

    // MARK: - Batch edit

    private func apply(_ edit: BatchEdit) {
        let targets = selectedContacts
        guard !targets.isEmpty else { return }

        if edit.deleteAll {
            if targets.contains(where: { $0.id == selectedContact?.id }) { selectedContact = nil }
            store.deleteContacts(targets)
            selection.removeAll()
            return
        }

        store.grouped("Edit \(targets.count) people", message: "Updated \(store.names(targets))") {
            if let orbit = edit.orbitZone { store.setCloseness(orbit, for: targets) }
            switch edit.archiveStatus {
            case .archive: store.setArchived(true, for: targets)
            case .unarchive: store.setArchived(false, for: targets)
            case .noChange: break
            }
            for group in allGroups where edit.constellationsToAdd.contains(group.id) {
                store.addToGroup(targets, group: group)
            }
            for group in allGroups where edit.constellationsToRemove.contains(group.id) {
                store.removeFromGroup(targets, group: group)
            }
        }
        selection.removeAll()
        #if os(iOS)
        editMode = .inactive
        #endif
    }
}

// MARK: - PeopleFilterSheet

struct PeopleFilterSheet: View {
    @Binding var filter: PeopleFilter
    let groups: [Constellation]
    let tags: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Due for a catch-up", isOn: $filter.dueOnly)
                    Picker("Closeness", selection: $filter.orbit) {
                        Text("Any").tag(Int?.none)
                        ForEach(OrbitZone.allZones, id: \.id) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                    if !groups.isEmpty {
                        Picker("Group", selection: $filter.groupID) {
                            Text("Any").tag(UUID?.none)
                            ForEach(groups) { Text("✦ \($0.name)").tag(UUID?.some($0.id)) }
                        }
                    }
                    if !tags.isEmpty {
                        Picker("Tag", selection: $filter.tag) {
                            Text("Any").tag(String?.none)
                            ForEach(tags, id: \.self) { Text("#\($0)").tag(String?.some($0)) }
                        }
                    }
                }
                Section("Housekeeping") {
                    Picker("Logs", selection: $filter.activity) {
                        ForEach(PeopleFilter.Activity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Facts", selection: $filter.facts) {
                        ForEach(PeopleFilter.Facts.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Include archived", isOn: $filter.showArchived)
                }
                if filter.activeCount > 0 {
                    Section {
                        Button("Clear all filters", role: .destructive) { filter = PeopleFilter() }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }
}
