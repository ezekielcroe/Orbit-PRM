import SwiftUI
import SwiftData

// MARK: - ContactDetailView
// One page per person: name → plain-language status → visible actions →
// notes → facts → timeline. The actions people use most (log, add a fact,
// change closeness) are real buttons, not hidden in a long-press. Rows are
// tappable to edit and swipeable to delete, and every change can be undone.

struct ContactDetailView: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Bindable var contact: Contact

    @State private var showEditForm = false
    @State private var showAddFact = false
    @State private var editingFact: Artifact?
    @State private var showSearch = false
    @State private var search = ""
    @State private var actionFilter: String?
    @State private var showDeleteConfirm = false

    private let keyColumnWidth: CGFloat = 96
    private let dateGutterWidth: CGFloat = 52

    var body: some View {
        List {
            Section {
                header
                actionRow
                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(OrbitTypography.headline.weight(.regular))
                        .lineSpacing(4)
                        .padding(.vertical, OrbitSpacing.xs)
                        .textSelection(.enabled)
                }
            }
            .listRowSeparator(.hidden)

            factsSection
            timelineSection
        }
        .listStyle(.plain)
        .navigationTitle(contact.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $showEditForm) { ContactFormSheet(mode: .edit(contact)) }
        .sheet(isPresented: $showAddFact) { ArtifactEditSheet(contact: contact, mode: .add) }
        .sheet(item: $editingFact) { fact in ArtifactEditSheet(contact: contact, mode: .edit(fact)) }
        .confirmationDialog("Delete \(contact.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                let target = contact
                router.forget(target)
                store.deleteContacts([target])
            }
        } message: {
            Text("This removes \(contact.name), their facts and their whole history, and can't be undone. Archiving hides them instead and can be reversed.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text(contact.name)
                .font(OrbitTypography.contactNameLarge(orbit: contact.targetOrbit))
                .textSelection(.enabled)

            Text(statusLine)
                .font(OrbitTypography.body)
                .foregroundStyle(contact.isDrifting ? AnyShapeStyle(contact.driftColor) : AnyShapeStyle(.secondary))

            HStack(spacing: OrbitSpacing.sm) {
                closenessMenu
                if contact.isSnoozed, let until = contact.snoozedUntil {
                    Button {
                        store.snooze([contact], until: nil)
                    } label: {
                        Label("Snoozed until \(until.formatted(.dateTime.day().month(.abbreviated)))", systemImage: "moon.zzz")
                            .font(OrbitTypography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Tap to unsnooze")
                }
                if contact.isArchived {
                    Text("Archived").font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }

            if !contextLine.isEmpty {
                Text(contextLine)
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, OrbitSpacing.md)
    }

    private var statusLine: String {
        if let reason = contact.attentionReason { return reason }
        guard let last = contact.lastContactDate else {
            return contact.targetOrbit == 4 ? "No reminders for \(firstName)." : "Nothing logged yet."
        }
        return "Last in touch \(last.relativeDescription.lowercased()) — on track."
    }

    private var firstName: String {
        contact.name.split(separator: " ").first.map(String.init) ?? contact.name
    }

    private var contextLine: String {
        var parts: [String] = []
        let groups = (contact.constellations ?? []).map { "✦ \($0.name)" }
        if !groups.isEmpty { parts.append(groups.joined(separator: "  ")) }
        let tags = contact.aggregatedTags.prefix(8).map { "#\($0.name)" }
        if !tags.isEmpty { parts.append(tags.joined(separator: " ")) }
        return parts.joined(separator: "   ")
    }

    private var closenessMenu: some View {
        Menu {
            ForEach(OrbitZone.allZones, id: \.id) { zone in
                Button {
                    store.setCloseness(zone.id, for: [contact])
                } label: {
                    if zone.id == contact.targetOrbit && contact.closenessConfirmed {
                        Label("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))", systemImage: "checkmark")
                    } else {
                        Text("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))")
                    }
                }
            }
        } label: {
            Label(closenessLabel, systemImage: "circle.dotted")
                .font(OrbitTypography.caption)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    private var closenessLabel: String {
        if !contact.closenessConfirmed && contact.cachedInteractionCount == 0 { return "Set closeness" }
        return "\(contact.orbitZoneName) · \(AttentionEngine.cadenceWord(forOrbit: contact.targetOrbit))"
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: OrbitSpacing.sm) {
            Button { router.log([contact]) } label: {
                Label("Log", systemImage: "plus.bubble")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                ForEach(store.actionSuggestions(limit: 4), id: \.self) { action in
                    Button(action) { store.log(contacts: [contact], action: action) }
                }
            } label: {
                Label("Quick log", systemImage: "bolt")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()

            Button { showAddFact = true } label: {
                Label("Add fact", systemImage: "text.badge.plus")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .padding(.vertical, OrbitSpacing.xs)
    }

    // MARK: - Facts

    @ViewBuilder
    private var factsSection: some View {
        Section {
            if (contact.artifacts ?? []).isEmpty {
                Button { showAddFact = true } label: {
                    Text("Add something worth remembering — a birthday, kids' names, their favourite coffee.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(groupedFacts, id: \.category) { group in
                    if groupedFacts.count > 1 {
                        Text(group.category.rawValue.uppercased())
                            .font(OrbitTypography.footnote)
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(group.artifacts) { fact in
                        factRow(fact, demoted: group.category == .contactInfo)
                    }
                }
            }
        } header: {
            sectionHeader("FACTS") {
                Button("Add") { showAddFact = true }
                    .font(OrbitTypography.caption)
            }
        }
    }

    private func factRow(_ fact: Artifact, demoted: Bool) -> some View {
        Button { editingFact = fact } label: {
            HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
                Text(fact.key.lowercased())
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: keyColumnWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(fact.listValues, id: \.self) { item in
                        Text(item)
                            .font(demoted ? OrbitTypography.caption : OrbitTypography.body)
                            .foregroundStyle(demoted ? .secondary : .primary)
                    }
                    if let date = fact.dateValue, let days = Birthdays.daysUntil(date, from: Date()), days <= 30 {
                        Text(days == 0 ? "Today" : "In \(days) day\(days == 1 ? "" : "s")")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.deleteFacts([fact]) } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingFact = fact }
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteFacts([fact]) }
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
        Section {
            if showSearch { timelineFilters }
            if filteredInteractions.isEmpty {
                Text(contact.cachedInteractionCount == 0 ? "Nothing logged yet." : "No logs match.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedInteractions, id: \.key) { month in
                    Text(month.key.uppercased())
                        .font(OrbitTypography.footnote)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .padding(.top, OrbitSpacing.sm)
                    ForEach(month.interactions) { interaction in
                        timelineRow(interaction)
                    }
                }
            }
        } header: {
            sectionHeader("ACTIVITY") {
                HStack(spacing: OrbitSpacing.md) {
                    Text("\(contact.cachedInteractionCount)")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.secondary)
                    Button("Log") { router.log([contact]) }
                        .font(OrbitTypography.caption)
                }
            }
        }
    }

    private var timelineFilters: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            TextField("Search this timeline", text: $search)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if uniqueActions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OrbitSpacing.sm) {
                        filterChip("All", active: actionFilter == nil) { actionFilter = nil }
                        ForEach(uniqueActions, id: \.self) { action in
                            filterChip(action, active: actionFilter?.lowercased() == action.lowercased()) {
                                actionFilter = actionFilter?.lowercased() == action.lowercased() ? nil : action
                            }
                        }
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    private func filterChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(active ? .accentColor : .secondary)
    }

    private func timelineRow(_ interaction: Interaction) -> some View {
        Button { router.edit(interaction) } label: {
            HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
                Text(interaction.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(OrbitTypography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: dateGutterWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                    HStack(spacing: OrbitSpacing.xs) {
                        Text(interaction.impulse).font(OrbitTypography.bodyMedium)
                        if interaction.batchID != nil {
                            Image(systemName: "person.2").font(.caption2).foregroundStyle(.secondary)
                                .accessibilityLabel("Logged with others")
                        }
                    }
                    if !interaction.content.isEmpty {
                        Text(interaction.content)
                            .font(OrbitTypography.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    if !interaction.tagList.isEmpty {
                        Text(interaction.tagList.map { "#\($0)" }.joined(separator: " "))
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.delete(interaction, includeBatch: false) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { router.edit(interaction) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(interaction, includeBatch: false) }
        }
    }

    private func sectionHeader<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(OrbitTypography.captionMedium)
                .tracking(2)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation {
                    showSearch.toggle()
                    if !showSearch { search = ""; actionFilter = nil }
                }
            } label: {
                Label("Search timeline", systemImage: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }

            Button { showEditForm = true } label: { Label("Edit", systemImage: "pencil") }

            Menu {
                Section("Snooze") {
                    Button("For a week") { snooze(days: 7) }
                    Button("For a month") { snooze(days: 30) }
                    if contact.isSnoozed { Button("Unsnooze") { store.snooze([contact], until: nil) } }
                }
                Section {
                    Button(contact.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                        store.setArchived(!contact.isArchived, for: [contact])
                    }
                    Button("Delete…", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func snooze(days: Int) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))
        store.snooze([contact], until: until)
    }

    // MARK: - Fact categories

    enum ArtifactCategory: String, CaseIterable {
        case personal = "Personal", professional = "Professional", other = "Other", contactInfo = "Contact Info"

        static func category(for artifact: Artifact) -> ArtifactCategory {
            if let explicit = artifact.category, !explicit.isEmpty {
                switch explicit {
                case "Contact Info": return .contactInfo
                case "Personal": return .personal
                case "Professional": return .professional
                default: return .other
                }
            }
            let k = artifact.key.lowercased()
            if ["email", "phone", "address", "city", "location", "website", "social", "instagram", "twitter", "linkedin", "github", "country"].contains(where: { k.contains($0) }) { return .contactInfo }
            if ["birthday", "anniversary", "born", "dob", "spouse", "wife", "husband", "partner", "children", "kids", "likes", "dislikes", "hobbies", "interests", "allergies", "pronouns", "hometown", "zodiac", "nickname", "pet", "pets", "favorite", "favourite"].contains(where: { k.contains($0) }) { return .personal }
            if ["company", "role", "title", "job", "department", "team", "met_at", "school", "university", "org", "organization", "industry"].contains(where: { k.contains($0) }) { return .professional }
            return .other
        }
    }

    private var groupedFacts: [(category: ArtifactCategory, artifacts: [Artifact])] {
        let sorted = (contact.artifacts ?? []).sorted { $0.key < $1.key }
        let grouped = Dictionary(grouping: sorted) { ArtifactCategory.category(for: $0) }
        return ArtifactCategory.allCases.compactMap { category in
            guard let arts = grouped[category], !arts.isEmpty else { return nil }
            return (category: category, artifacts: arts)
        }
    }

    private var filteredInteractions: [Interaction] {
        var result = contact.activeInteractions
        if let filter = actionFilter { result = result.filter { $0.impulse.lowercased() == filter.lowercased() } }
        if !search.isEmpty {
            let q = search.lowercased()
            result = result.filter {
                $0.impulse.lowercased().contains(q) || $0.content.lowercased().contains(q) || $0.tagNames.lowercased().contains(q)
            }
        }
        return result
    }

    private var uniqueActions: [String] {
        var seen = Set<String>()
        return contact.activeInteractions.map(\.impulse).filter { seen.insert($0.lowercased()).inserted }.sorted()
    }

    private var groupedInteractions: [(key: String, interactions: [Interaction])] {
        let grouped = Dictionary(grouping: filteredInteractions) { $0.date.formatted(.dateTime.year().month(.wide)) }
        return grouped.map { (key: $0.key, interactions: $0.value) }
            .sorted { ($0.interactions.first?.date ?? .distantPast) > ($1.interactions.first?.date ?? .distantPast) }
    }
}
