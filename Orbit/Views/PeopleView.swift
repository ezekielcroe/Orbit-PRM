import SwiftUI
import SwiftData

// MARK: - PeopleView
// The single primary view for browsing, searching, and monitoring contacts.
// Merges the previous Dashboard, ContactListView, and ReviewDashboardView into
// one unified surface. Contacts are grouped by orbit zone by default, with
// inline attention signals (drifting contacts, upcoming dates) surfaced at
// the top when relevant.
//
// Tags shown here are aggregated from interactions — they reflect what you
// DO with someone, not a label you assigned. Constellations handle grouping.

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Binding var selectedContact: Contact?
    @Binding var showCommandPalette: Bool
    @Binding var showSettings: Bool

    @Query(sort: [SortDescriptor(\Contact.name)])
    private var allContacts: [Contact]

    // Tag registry — for filter chip display (tag names that exist)
    @Query(sort: [SortDescriptor(\Tag.name)])
    private var allTags: [Tag]

    @Query(sort: [SortDescriptor(\Constellation.name)])
    private var allConstellations: [Constellation]

    // MARK: - State

    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var groupMode: GroupMode = .orbit
    @State private var showArchived = false
    @State private var showTableView = false

    // Filters
    @State private var filterTagName: String?      // filters by interaction tag
    @State private var filterConstellation: Constellation?
    @State private var filterStatus: StatusFilter = .all

    // Attention banner
    @State private var attentionExpanded = false

    enum GroupMode: String, CaseIterable {
        case orbit = "Orbit"
        case alphabetical = "A–Z"
        case recent = "Recent"
    }

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case drifting = "Drifting"
        case neglected = "New"
    }

    // MARK: - Computed Data

    private var activeContacts: [Contact] {
        showArchived ? allContacts : allContacts.filter { !$0.isArchived }
    }

    private var filteredContacts: [Contact] {
        var result = activeContacts

        // Search
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

        // Tag filter (checks interaction tags)
        if let tagName = filterTagName {
            result = result.filter { $0.hasInteractionTag(tagName) }
        }

        // Constellation filter
        if let constellation = filterConstellation {
            result = result.filter { $0.constellations.contains(where: { $0.id == constellation.id }) }
        }

        // Status filter
        switch filterStatus {
        case .all: break
        case .active:
            result = result.filter { ($0.daysSinceLastContact ?? 999) <= 14 }
        case .drifting:
            result = result.filter { $0.isDrifting }
        case .neglected:
            result = result.filter { $0.lastContactDate == nil && $0.targetOrbit < 4 }
        }

        return result
    }

    /// Contacts grouped and sorted according to the current group mode
    private var groupedContacts: [(key: String, contacts: [Contact])] {
        switch groupMode {
        case .orbit:
            let grouped = Dictionary(grouping: filteredContacts) { $0.targetOrbit }
            return OrbitZone.allZones.compactMap { zone in
                guard let contacts = grouped[zone.id], !contacts.isEmpty else { return nil }
                return (key: zone.name, contacts: contacts.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                })
            }

        case .alphabetical:
            let sorted = filteredContacts.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let grouped = Dictionary(grouping: sorted) { contact in
                String(contact.name.prefix(1)).uppercased()
            }
            return grouped
                .sorted { $0.key < $1.key }
                .map { (key: $0.key, contacts: $0.value) }

        case .recent:
            let sorted = filteredContacts.sorted {
                ($0.lastContactDate ?? .distantPast) > ($1.lastContactDate ?? .distantPast)
            }
            let grouped = Dictionary(grouping: sorted) { contact -> String in
                guard let days = contact.daysSinceLastContact else { return "Never Contacted" }
                switch days {
                case 0...7: return "This Week"
                case 8...30: return "This Month"
                case 31...90: return "This Quarter"
                case 91...365: return "This Year"
                default: return "Over a Year"
                }
            }
            let order = ["This Week", "This Month", "This Quarter", "This Year", "Over a Year", "Never Contacted"]
            return order.compactMap { key in
                guard let contacts = grouped[key], !contacts.isEmpty else { return nil }
                return (key: key, contacts: contacts)
            }
        }
    }

    // MARK: - Attention Data

    private var driftingContacts: [Contact] {
        activeContacts
            .filter { $0.isDrifting }
            .sorted { $0.driftPriority > $1.driftPriority }
    }

    private var upcomingDates: [UpcomingDateItem] {
        findUpcomingDates(from: activeContacts)
    }

    private var activeIn7Days: Int {
        activeContacts.filter { ($0.daysSinceLastContact ?? 999) <= 7 }.count
    }

    // MARK: - Body

    var body: some View {
        Group {
            if allContacts.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    summaryBar
                    filterBar
                    Divider()
                    contactList
                }
            }
        }
        .navigationTitle("People")
        .searchable(text: $searchText, prompt: "Search contacts, tags, or artifacts")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Picker("Group by", selection: $groupMode) {
                        ForEach(GroupMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Divider()
                    Toggle("Show Archived", isOn: $showArchived)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }

                Button {
                    showTableView = true
                } label: {
                    Image(systemName: "tablecells")
                }
                .help("Table View")

                Button {
                    showAddContact = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .help("Add Contact")

                Button {
                    showCommandPalette = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("Quick Log (⌘K)")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactFormSheet(mode: .add) { newContact in
                selectedContact = newContact
            }
        }
        .sheet(isPresented: $showTableView) {
            NavigationStack {
                TabularView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showTableView = false }
                        }
                    }
            }
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: OrbitSpacing.lg) {
            summaryItem(count: activeContacts.count, label: "Contacts", icon: "person.2")
            summaryItem(count: activeIn7Days, label: "Active (7d)", icon: "checkmark.circle")

            if !driftingContacts.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        attentionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: OrbitSpacing.xs) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("\(driftingContacts.count)")
                            .font(OrbitTypography.captionMedium)
                            .foregroundStyle(.orange)
                        Text("Need attention")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.orange.opacity(0.7))
                        Image(systemName: attentionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
            }

            if !upcomingDates.isEmpty {
                let soonCount = upcomingDates.filter { $0.daysUntil <= 7 }.count
                if soonCount > 0 {
                    HStack(spacing: OrbitSpacing.xs) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                        Text("\(soonCount) upcoming")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.cyan)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm)
    }

    private func summaryItem(count: Int, label: String, icon: String) -> some View {
        HStack(spacing: OrbitSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(.secondary)
            Text(label)
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Filter Bar (Status, Tags, Constellations)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OrbitSpacing.xs) {
                // Status filters
                ForEach(StatusFilter.allCases, id: \.self) { status in
                    filterChip(
                        status.rawValue,
                        isActive: filterStatus == status,
                        color: status == .drifting ? .orange : nil
                    ) {
                        filterStatus = (filterStatus == status && status != .all) ? .all : status
                    }
                }

                if !allTags.isEmpty || !allConstellations.isEmpty {
                    dividerPill
                }

                // Interaction tag filters (from tag registry)
                ForEach(allTags) { tag in
                    filterChip(
                        "#\(tag.name)",
                        isActive: filterTagName == tag.searchableName,
                        color: OrbitColors.syntaxTag
                    ) {
                        filterTagName = (filterTagName == tag.searchableName) ? nil : tag.searchableName
                    }
                }

                // Constellation filters
                ForEach(allConstellations) { constellation in
                    filterChip(
                        "✦ \(constellation.name)",
                        isActive: filterConstellation?.id == constellation.id,
                        color: .purple
                    ) {
                        filterConstellation = (filterConstellation?.id == constellation.id) ? nil : constellation
                    }
                }
            }
            .padding(.horizontal, OrbitSpacing.md)
            .padding(.vertical, OrbitSpacing.sm)
        }
    }

    private var dividerPill: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 16)
            .padding(.horizontal, OrbitSpacing.xs)
    }

    private func filterChip(_ label: String, isActive: Bool, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OrbitTypography.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isActive
                        ? (color ?? Color.primary).opacity(0.12)
                        : Color.secondary.opacity(0.06),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? (color ?? .primary) : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contact List

    private var contactList: some View {
        List(selection: $selectedContact) {
            if attentionExpanded && !driftingContacts.isEmpty {
                attentionSection
            }

            if upcomingDates.contains(where: { $0.daysUntil <= 7 }) {
                upcomingSection
            }

            ForEach(groupedContacts, id: \.key) { group in
                Section {
                    ForEach(group.contacts) { contact in
                        PeopleContactRow(contact: contact)
                            .tag(contact)
                            .swipeActions(edge: .leading) {
                                Button {
                                    selectedContact = contact
                                    showCommandPalette = true
                                } label: {
                                    Label("Log", systemImage: "plus.bubble")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(contact.isArchived ? "Restore" : "Archive") {
                                    contact.isArchived.toggle()
                                    contact.modifiedAt = Date()
                                    if contact.isArchived {
                                        spotlightIndexer.deindex(contact: contact)
                                    } else {
                                        spotlightIndexer.index(contact: contact)
                                    }
                                }
                                .tint(contact.isArchived ? .blue : .orange)
                            }
                    }
                } header: {
                    HStack(spacing: OrbitSpacing.sm) {
                        Text(group.key)
                            .font(OrbitTypography.captionMedium)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Spacer()
                        Text("\(group.contacts.count)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if groupedContacts.isEmpty && !allContacts.isEmpty {
                Section {
                    Text("No contacts match your current filters.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Attention Section

    private var attentionSection: some View {
        Section {
            ForEach(driftingContacts.prefix(5)) { contact in
                HStack(spacing: OrbitSpacing.md) {
                    Circle()
                        .fill(contact.driftColor)
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                            .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                        HStack(spacing: OrbitSpacing.sm) {
                            Text(contact.orbitZoneName)
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(contact.recencyDescription)
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(contact.driftColor)
                        }
                    }

                    Spacer()

                    Button {
                        quickLog(contact: contact, impulse: "Check-in")
                    } label: {
                        Image(systemName: "plus.bubble")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .tag(contact)
            }

            if driftingContacts.count > 5 {
                Text("\(driftingContacts.count - 5) more need attention")
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            HStack {
                Label("Needs Attention", systemImage: "exclamationmark.circle")
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
            }
        }
    }

    // MARK: - Upcoming Dates Section

    private var upcomingSection: some View {
        Section {
            ForEach(upcomingDates.filter({ $0.daysUntil <= 7 })) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.contact.name)
                            .font(OrbitTypography.bodyMedium)
                        Text(item.key.capitalized)
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.daysUntilText)
                        .font(OrbitTypography.captionMedium)
                        .foregroundStyle(item.urgencyColor)
                }
            }
        } header: {
            Label("Coming Up", systemImage: "calendar")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(.cyan)
                .textCase(.uppercase)
                .tracking(1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Contacts Yet", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Add your first contact to begin mapping your universe.")
        } actions: {
            Button("Open Command Palette") {
                showCommandPalette = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func quickLog(contact: Contact, impulse: String) {
        let interaction = Interaction(impulse: impulse, date: Date())
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshLastContactDate()
        spotlightIndexer.index(contact: contact)
    }

    // MARK: - Date Parsing (migrated from ReviewDashboardView)

    private func findUpcomingDates(from contacts: [Contact]) -> [UpcomingDateItem] {
        var items: [UpcomingDateItem] = []
        let calendar = Calendar.current
        let today = Date()

        for contact in contacts {
            for artifact in contact.artifacts where artifact.isDateType {
                if let nextDate = parseAndProjectDate(artifact.value, from: today) {
                    let daysUntil = calendar.dateComponents([.day], from: today, to: nextDate).day ?? 999
                    if daysUntil >= 0 && daysUntil <= 60 {
                        items.append(UpcomingDateItem(
                            contact: contact, key: artifact.key,
                            date: nextDate, daysUntil: daysUntil
                        ))
                    }
                }
            }
        }
        return items.sorted { $0.daysUntil < $1.daysUntil }
    }

    private func parseAndProjectDate(_ value: String, from reference: Date) -> Date? {
        let slashParts = value.split(separator: "/")
        if slashParts.count >= 2,
           let month = Int(slashParts[0]), let day = Int(slashParts[1]),
           (1...12).contains(month), (1...31).contains(day) {
            return nextOccurrence(month: month, day: day, from: reference)
        }
        let dashParts = value.split(separator: "-")
        if dashParts.count == 3, let month = Int(dashParts[1]), let day = Int(dashParts[2]) {
            return nextOccurrence(month: month, day: day, from: reference)
        }
        let dateFormatter = DateFormatter()
        for format in ["MMMM d", "MMM d", "MMMM dd", "MMM dd", "d MMMM", "d MMM"] {
            dateFormatter.dateFormat = format
            if let parsed = dateFormatter.date(from: value) {
                let components = Calendar.current.dateComponents([.month, .day], from: parsed)
                if let month = components.month, let day = components.day {
                    return nextOccurrence(month: month, day: day, from: reference)
                }
            }
        }
        return nil
    }

    private func nextOccurrence(month: Int, day: Int, from reference: Date) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: reference)
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year
        if let thisYear = calendar.date(from: components), thisYear >= reference {
            return thisYear
        }
        components.year = year + 1
        return calendar.date(from: components)
    }
}

// MARK: - People Contact Row

struct PeopleContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: OrbitSpacing.md) {
            if contact.isDrifting {
                Circle()
                    .fill(contact.driftColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                Text(contact.recencyDescription)
                    .font(OrbitTypography.caption)
                    .foregroundStyle(contact.isDrifting ? contact.driftColor : .secondary)
            }

            Spacer()

            // Show top aggregated interaction tags (what you do together)
            if !contact.aggregatedTags.isEmpty {
                Text(contact.aggregatedTags.prefix(2).map { "#\($0.name)" }.joined(separator: " "))
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
    }
}

// MARK: - Supporting Types

struct UpcomingDateItem: Identifiable {
    let id = UUID()
    let contact: Contact
    let key: String
    let date: Date
    let daysUntil: Int

    var daysUntilText: String {
        switch daysUntil {
        case 0: return "Today!"
        case 1: return "Tomorrow"
        case 2...7: return "In \(daysUntil) days"
        default: return "In \(daysUntil / 7) weeks"
        }
    }

    var urgencyColor: Color {
        switch daysUntil {
        case 0: return .red
        case 1...3: return .orange
        case 4...7: return .yellow
        default: return .secondary
        }
    }
}
