import SwiftUI
import SwiftData

// MARK: - ContactDetailView (Refactored)
// Single continuous scroll replaces the previous Info/Timeline tab picker.
// The full picture of a contact is visible in one flow:
//   1. Header (name, orbit, tags, last contact)
//   2. Quick action buttons
//   3. Artifacts grouped by category
//   4. Recent interactions (last 5 inline)
//   5. "Show all" expands full timeline with search/filter
//

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Bindable var contact: Contact

    @State private var showEditForm = false
    @State private var showAddArtifact = false
    @State private var showAddInteraction = false
    @State private var editingArtifact: Artifact?
    @State private var showFullTimeline = false

    // Timeline filter state
    @State private var impulseFilter: String?
    @State private var interactionSearch = ""
    @State private var expandedMonths: Set<String> = []
    @State private var interactionLimit = 20

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
        return ArtifactCategory.allCases.compactMap { category in
            guard let arts = grouped[category], !arts.isEmpty else { return nil }
            return (category: category, artifacts: arts)
        }
    }

    // MARK: - Interaction Data

    private var filteredInteractions: [Interaction] {
        var result = contact.activeInteractions
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

    private var uniqueImpulses: [String] {
        let impulses = contact.activeInteractions.map(\.impulse)
        var seen = Set<String>()
        return impulses.filter { seen.insert($0.lowercased()).inserted }.sorted()
    }

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

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                headerSection
                quickActionsBar

                if !contact.artifacts.isEmpty {
                    artifactSection
                }

                interactionSection
            }
            .padding(OrbitSpacing.lg)
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

                if contact.daysSinceLastContact != nil {
                    Label(contact.recencyDescription, systemImage: "clock")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(contact.isDrifting ? contact.driftColor : .secondary)
                }

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(contact.activeInteractions.count) interaction\(contact.activeInteractions.count == 1 ? "" : "s")")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            // Aggregated interaction tags — what you do with this person
            if !contact.aggregatedTags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(contact.aggregatedTags.prefix(8)) { tag in
                        HStack(spacing: 2) {
                            Text("#\(tag.name)")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(OrbitColors.syntaxTag)
                            if tag.count > 1 {
                                Text("×\(tag.count)")
                                    .font(OrbitTypography.footnote)
                                    .foregroundStyle(OrbitColors.syntaxTag.opacity(0.6))
                            }
                        }
                    }
                }
            }

            // Constellations
            if !contact.constellations.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(contact.constellations) { constellation in
                        Text("✦ \(constellation.name)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.purple)
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

    // MARK: - Quick Actions

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OrbitSpacing.sm) {
                quickActionButton("Call", icon: "phone") { quickLog(impulse: "Call") }
                quickActionButton("Text", icon: "message") { quickLog(impulse: "Text") }
                quickActionButton("Coffee", icon: "cup.and.saucer") { quickLog(impulse: "Coffee") }
                quickActionButton("Meeting", icon: "person.2") { quickLog(impulse: "Meeting") }
                quickActionButton("Other…", icon: "plus.bubble") { showAddInteraction = true }
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

    private func quickLog(impulse: String) {
        let interaction = Interaction(impulse: impulse, date: Date())
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshLastContactDate()
        spotlightIndexer.index(contact: contact)
    }

    // MARK: - Artifacts

    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            HStack {
                Text("ARTIFACTS")
                    .font(OrbitTypography.captionMedium)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showAddArtifact = true } label: {
                    Image(systemName: "plus").font(.caption)
                }
                .buttonStyle(.plain)
            }

            ForEach(groupedArtifacts, id: \.category) { group in
                artifactCategorySection(group.category, artifacts: group.artifacts)
            }
        }
    }

    private func artifactCategorySection(_ category: ArtifactCategory, artifacts: [Artifact]) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
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
                    .onTapGesture { editingArtifact = artifact }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingArtifact = artifact }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(artifact)
                            contact.modifiedAt = Date()
                            spotlightIndexer.index(contact: contact)
                        }
                    }
            }
        }
    }

    // MARK: - Interactions

    private var interactionSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            HStack {
                Text("INTERACTIONS")
                    .font(OrbitTypography.captionMedium)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                if !contact.activeInteractions.isEmpty {
                    Text("(\(contact.activeInteractions.count))")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button { showAddInteraction = true } label: {
                    Image(systemName: "plus").font(.caption)
                }
                .buttonStyle(.plain)
            }

            if contact.activeInteractions.isEmpty {
                Text("No interactions logged yet.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            } else if !showFullTimeline {
                recentInteractionsPreview
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showFullTimeline = true }
                } label: {
                    Text("Show all \(contact.activeInteractions.count) interactions →")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, OrbitSpacing.xs)
            } else {
                fullTimeline
            }
        }
    }

    private var recentInteractionsPreview: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            ForEach(contact.activeInteractions.prefix(5)) { interaction in
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

    private var fullTimeline: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFullTimeline = false
                    impulseFilter = nil
                    interactionSearch = ""
                }
            } label: {
                Text("← Show recent only")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            // Search
            HStack(spacing: OrbitSpacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search interactions…", text: $interactionSearch)
                    .font(OrbitTypography.caption).textFieldStyle(.plain)
                if !interactionSearch.isEmpty {
                    Button { interactionSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OrbitSpacing.sm)
            .padding(.vertical, OrbitSpacing.xs)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if uniqueImpulses.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OrbitSpacing.xs) {
                        impulseChip("All", isActive: impulseFilter == nil) { impulseFilter = nil }
                        ForEach(uniqueImpulses, id: \.self) { impulse in
                            impulseChip(impulse, isActive: impulseFilter?.lowercased() == impulse.lowercased()) {
                                impulseFilter = (impulseFilter?.lowercased() == impulse.lowercased()) ? nil : impulse
                            }
                        }
                    }
                }
            }

            if filteredInteractions.count != contact.activeInteractions.count {
                Text("\(filteredInteractions.count) of \(contact.activeInteractions.count) interactions")
                    .font(OrbitTypography.footnote).foregroundStyle(.tertiary)
            }

            if filteredInteractions.isEmpty {
                Text("No interactions match your filters.")
                    .font(OrbitTypography.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(groupedInteractions.enumerated()), id: \.element.key) { index, group in
                    collapsibleMonthGroup(group, isRecentGroup: index < 2)
                }
                if filteredInteractions.count > interactionLimit {
                    Button { interactionLimit += 20 } label: {
                        Text("Show more (\(filteredInteractions.count - interactionLimit) remaining)")
                            .font(OrbitTypography.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).padding(.top, OrbitSpacing.sm)
                }
            }
        }
    }

    private func impulseChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OrbitTypography.footnote)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(
                    isActive ? OrbitColors.syntaxImpulse.opacity(0.15) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? OrbitColors.syntaxImpulse : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func collapsibleMonthGroup(
        _ group: (key: String, interactions: [Interaction]),
        isRecentGroup: Bool
    ) -> some View {
        let isExpanded = expandedMonths.contains(group.key)
        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedMonths.remove(group.key) }
                    else { expandedMonths.insert(group.key) }
                }
            } label: {
                HStack(spacing: OrbitSpacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary).frame(width: 12)
                    Text(group.key).font(OrbitTypography.footnote).foregroundStyle(.tertiary)
                        .textCase(.uppercase).tracking(1)
                    Text("(\(group.interactions.count))").font(OrbitTypography.footnote).foregroundStyle(.quaternary)
                    Spacer()
                }
            }
            .buttonStyle(.plain).padding(.top, OrbitSpacing.sm)

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
