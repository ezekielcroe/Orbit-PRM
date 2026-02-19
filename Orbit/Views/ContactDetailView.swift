import SwiftUI
import SwiftData

// MARK: - ContactDetailView (Phase 2)
// Updates from Phase 1:
// - Lazy-loaded interaction timeline (performance for contacts with many logs)
// - Spotlight re-indexing on interaction log
// - Inline artifact value editing on long-press (bypasses command palette)
// - Interaction grouping by month for easier scanning
// - Quick-action buttons for common operations
//
// FIX 4: Tabbed layout (Info / Timeline) prevents clutter at scale.
// - Artifacts grouped into semantic categories (Contact Info, Personal, Professional, Other)
// - Interactions have impulse-type filter chips and in-section search
// - Older month groups are collapsed by default

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Bindable var contact: Contact

    @State private var showEditForm = false
    @State private var showAddArtifact = false
    @State private var showAddInteraction = false
    @State private var editingArtifact: Artifact?
    @State private var interactionLimit = 20 // Lazy loading

    // FIX 4: Tab selection
    @State private var selectedTab: DetailTab = .info

    // FIX 4: Interaction filters
    @State private var impulseFilter: String?
    @State private var interactionSearch = ""
    @State private var expandedMonths: Set<String> = []

    enum DetailTab: String, CaseIterable {
        case info = "Info"
        case timeline = "Timeline"

        var icon: String {
            switch self {
            case .info: return "person.text.rectangle"
            case .timeline: return "clock"
            }
        }
    }

    // MARK: - Data

    private var activeInteractions: [Interaction] {
        contact.interactions
            .filter { !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }

    /// Filtered interactions based on impulse filter and search text
    private var filteredInteractions: [Interaction] {
        var result = activeInteractions

        if let filter = impulseFilter {
            result = result.filter { $0.impulse.lowercased() == filter.lowercased() }
        }

        if !interactionSearch.isEmpty {
            let query = interactionSearch.lowercased()
            result = result.filter {
                $0.impulse.lowercased().contains(query)
                || $0.content.lowercased().contains(query)
                || $0.tagNames.lowercased().contains(query)
            }
        }

        return result
    }

    /// Unique impulse types for filter chips
    private var uniqueImpulses: [String] {
        let impulses = activeInteractions.map(\.impulse)
        var seen = Set<String>()
        return impulses.filter { seen.insert($0.lowercased()).inserted }
            .sorted()
    }

    /// Group interactions by month for visual clarity
    private var groupedInteractions: [(key: String, interactions: [Interaction])] {
        let limited = Array(filteredInteractions.prefix(interactionLimit))

        let grouped = Dictionary(grouping: limited) { interaction in
            interaction.date.formatted(.dateTime.year().month(.wide))
        }

        return grouped
            .map { (key: $0.key, interactions: $0.value) }
            .sorted { a, b in
                let aDate = a.interactions.first?.date ?? .distantPast
                let bDate = b.interactions.first?.date ?? .distantPast
                return aDate > bDate
            }
    }

    // MARK: - Artifact Categories

    enum ArtifactCategory: String, CaseIterable {
        case contactInfo = "Contact Info"
        case personal = "Personal"
        case professional = "Professional"
        case other = "Other"

        var icon: String {
            switch self {
            case .contactInfo: return "phone.circle"
            case .personal: return "heart.circle"
            case .professional: return "briefcase"
            case .other: return "ellipsis.circle"
            }
        }

        static func category(for key: String) -> ArtifactCategory {
            let k = key.lowercased()
            let contactInfoKeys = ["email", "phone", "address", "city", "location",
                                   "website", "social", "instagram", "twitter",
                                   "linkedin", "github", "country"]
            let personalKeys = ["birthday", "anniversary", "born", "dob", "spouse",
                                "wife", "husband", "partner", "children", "kids",
                                "likes", "dislikes", "hobbies", "interests",
                                "allergies", "pronouns", "hometown", "zodiac",
                                "nickname", "pet", "pets", "favorite"]
            let professionalKeys = ["company", "role", "title", "job", "department",
                                    "team", "met_at", "school", "university",
                                    "org", "organization", "industry"]

            if contactInfoKeys.contains(where: { k.contains($0) }) { return .contactInfo }
            if personalKeys.contains(where: { k.contains($0) }) { return .personal }
            if professionalKeys.contains(where: { k.contains($0) }) { return .professional }
            return .other
        }
    }

    private var groupedArtifacts: [(category: ArtifactCategory, artifacts: [Artifact])] {
        let sorted = contact.artifacts.sorted { $0.key < $1.key }
        let grouped = Dictionary(grouping: sorted) { ArtifactCategory.category(for: $0.key) }

        // Return in category order, skipping empty groups
        return ArtifactCategory.allCases.compactMap { category in
            guard let arts = grouped[category], !arts.isEmpty else { return nil }
            return (category: category, artifacts: arts)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible header
            ScrollView {
                VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                    headerSection
                    quickActionsBar
                }
                .padding(.horizontal, OrbitSpacing.lg)
                .padding(.top, OrbitSpacing.lg)
            }
            .frame(maxHeight: 160)

            // Tab picker
            Picker("Section", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.vertical, OrbitSpacing.sm)

            Divider()

            // Tab content
            switch selectedTab {
            case .info:
                infoTabContent
            case .timeline:
                timelineTabContent
            }
        }
        .navigationTitle(contact.name)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showEditForm = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit Contact")

                Menu {
                    Button("Add Artifact", systemImage: "key") {
                        showAddArtifact = true
                    }
                    Button("Log Interaction", systemImage: "plus.bubble") {
                        showAddInteraction = true
                    }
                    Divider()
                    Button(contact.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                        contact.isArchived.toggle()
                        contact.modifiedAt = Date()

                        if contact.isArchived {
                            spotlightIndexer.deindex(contact: contact)
                        } else {
                            spotlightIndexer.index(contact: contact)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditForm) {
            ContactFormSheet(mode: .edit(contact))
        }
        .sheet(isPresented: $showAddArtifact) {
            ArtifactEditSheet(contact: contact, mode: .add)
        }
        .sheet(isPresented: $showAddInteraction) {
            QuickInteractionSheet(contact: contact)
        }
        .sheet(item: $editingArtifact) { artifact in
            ArtifactEditSheet(contact: contact, mode: .edit(artifact))
        }
        .onAppear {
            // Auto-expand the most recent 2 month groups
            let recentKeys = groupedInteractions.prefix(2).map(\.key)
            expandedMonths = Set(recentKeys)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text(contact.name)
                .font(OrbitTypography.contactNameLarge(orbit: contact.targetOrbit))
                .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

            HStack(spacing: OrbitSpacing.md) {
                Label(contact.orbitZoneName, systemImage: "circle.dotted")
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(.secondary)

                if let days = contact.daysSinceLastContact {
                    Label(
                        days == 0 ? "Today" : "\(days)d ago",
                        systemImage: "clock"
                    )
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
                }

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(activeInteractions.count) interaction\(activeInteractions.count == 1 ? "" : "s")")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            if !contact.tags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(contact.tags) { tag in
                        Text("#\(tag.name)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(OrbitColors.syntaxTag)
                    }
                }
            }

            if !contact.notes.isEmpty {
                Text(contact.notes)
                    .font(OrbitTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, OrbitSpacing.xs)
            }
        }
    }

    // MARK: - Quick Actions Bar

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OrbitSpacing.sm) {
                quickActionButton("Call", icon: "phone") {
                    quickLog(impulse: "Call")
                }
                quickActionButton("Text", icon: "message") {
                    quickLog(impulse: "Text")
                }
                quickActionButton("Coffee", icon: "cup.and.saucer") {
                    quickLog(impulse: "Coffee")
                }
                quickActionButton("Meeting", icon: "person.2") {
                    quickLog(impulse: "Meeting")
                }
                quickActionButton("Other…", icon: "plus.bubble") {
                    showAddInteraction = true
                }
            }
        }
    }

    private func quickActionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(OrbitTypography.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Instantly log a common interaction type
    private func quickLog(impulse: String) {
        let interaction = Interaction(impulse: impulse, date: Date())
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshLastContactDate()
        spotlightIndexer.index(contact: contact)
    }

    // MARK: - Info Tab

    private var infoTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                artifactSection
            }
            .padding(OrbitSpacing.lg)
        }
    }

    // MARK: - Artifacts (Grouped)

    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            HStack {
                Text("ARTIFACTS")
                    .font(OrbitTypography.captionMedium)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showAddArtifact = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if contact.artifacts.isEmpty {
                Text("No artifacts yet. Use > key: value to add context.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(groupedArtifacts, id: \.category) { group in
                    artifactCategorySection(group.category, artifacts: group.artifacts)
                }
            }
        }
    }

    private func artifactCategorySection(_ category: ArtifactCategory, artifacts: [Artifact]) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            // Category header
            HStack(spacing: OrbitSpacing.xs) {
                Image(systemName: category.icon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(category.rawValue.uppercased())
                    .font(OrbitTypography.footnote)
                    .tracking(1)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, OrbitSpacing.sm)

            ForEach(artifacts) { artifact in
                ArtifactRowView(artifact: artifact)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingArtifact = artifact
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            editingArtifact = artifact
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(artifact)
                            contact.modifiedAt = Date()
                            spotlightIndexer.index(contact: contact)
                        }
                    }
            }
        }
    }

    // MARK: - Timeline Tab

    private var timelineTabContent: some View {
        VStack(spacing: 0) {
            // Filter controls
            interactionFilterBar
            Divider()

            // Interaction list
            ScrollView {
                VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    interactionSection
                }
                .padding(OrbitSpacing.lg)
            }
        }
    }

    // MARK: - Interaction Filters

    private var interactionFilterBar: some View {
        VStack(spacing: OrbitSpacing.sm) {
            // Search
            HStack(spacing: OrbitSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search interactions…", text: $interactionSearch)
                    .font(OrbitTypography.caption)
                    .textFieldStyle(.plain)

                if !interactionSearch.isEmpty {
                    Button {
                        interactionSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OrbitSpacing.sm)
            .padding(.vertical, OrbitSpacing.xs)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            // Impulse filter chips
            if uniqueImpulses.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OrbitSpacing.xs) {
                        filterChip("All", isActive: impulseFilter == nil) {
                            impulseFilter = nil
                        }
                        ForEach(uniqueImpulses, id: \.self) { impulse in
                            filterChip(impulse, isActive: impulseFilter?.lowercased() == impulse.lowercased()) {
                                impulseFilter = (impulseFilter?.lowercased() == impulse.lowercased()) ? nil : impulse
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, OrbitSpacing.lg)
        .padding(.vertical, OrbitSpacing.sm)
    }

    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OrbitTypography.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isActive ? OrbitColors.syntaxImpulse.opacity(0.15) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? OrbitColors.syntaxImpulse : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Interactions (Grouped + Collapsible + Lazy)

    private var interactionSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            HStack {
                Text("INTERACTIONS")
                    .font(OrbitTypography.captionMedium)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                if filteredInteractions.count != activeInteractions.count {
                    Text("(\(filteredInteractions.count) of \(activeInteractions.count))")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    showAddInteraction = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if filteredInteractions.isEmpty {
                if activeInteractions.isEmpty {
                    Text("No interactions logged yet.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("No interactions match your filters.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                ForEach(Array(groupedInteractions.enumerated()), id: \.element.key) { index, group in
                    collapsibleMonthGroup(group, isRecentGroup: index < 2)
                }

                // Load more button for lazy loading
                if filteredInteractions.count > interactionLimit {
                    Button {
                        interactionLimit += 20
                    } label: {
                        Text("Show more (\(filteredInteractions.count - interactionLimit) remaining)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, OrbitSpacing.sm)
                }
            }
        }
    }

    private func collapsibleMonthGroup(
        _ group: (key: String, interactions: [Interaction]),
        isRecentGroup: Bool
    ) -> some View {
        let isExpanded = expandedMonths.contains(group.key)

        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            // Month header — tappable to collapse/expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedMonths.remove(group.key)
                    } else {
                        expandedMonths.insert(group.key)
                    }
                }
            } label: {
                HStack(spacing: OrbitSpacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Text(group.key)
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(1)

                    Text("(\(group.interactions.count))")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.quaternary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.top, OrbitSpacing.sm)

            if isExpanded {
                ForEach(group.interactions) { interaction in
                    InteractionRowView(interaction: interaction)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                interaction.isDeleted = true
                                contact.refreshLastContactDate()
                            }
                        }
                }
            }
        }
    }
}
