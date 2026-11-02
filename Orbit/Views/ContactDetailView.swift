import SwiftUI
import SwiftData

// MARK: - ContactDetailView
// Editorial one-pager. Single scroll: name → drift sentence → notes lede →
// curated fact grid → flush timeline. Typography carries all hierarchy;
// color appears in exactly one place (the drift sentence). Quick actions
// live in the toolbar. Search is behind a toolbar toggle.

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Bindable var contact: Contact

    // Sheet State
    @State private var showEditForm = false
    @State private var showAddArtifact = false
    @State private var showAddInteraction = false
    @State private var editingArtifact: Artifact?
    @State private var editingInteraction: Interaction?

    // Timeline State
    @State private var showSearch = false
    @State private var interactionSearch = ""
    @State private var impulseFilter: String?
    @State private var collapsedMonths: Set<String> = []   // empty = everything visible

    // Key-column width for the fact grid and the timeline date gutter.
    private let keyColumnWidth: CGFloat = 96
    private let dateGutterWidth: CGFloat = 52

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.top, OrbitSpacing.lg)
                    .padding(.bottom, OrbitSpacing.xl)

                if !contact.notes.isEmpty {
                    lede
                        .padding(.bottom, OrbitSpacing.xl)
                }

                factSections
                timelineSection
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.bottom, OrbitSpacing.xxxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle(contact.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        // Sheets
        .sheet(isPresented: $showEditForm) { ContactFormSheet(mode: .edit(contact)) }
        .sheet(isPresented: $showAddArtifact) { ArtifactEditSheet(contact: contact, mode: .add) }
        .sheet(isPresented: $showAddInteraction) { QuickInteractionSheet(contact: contact) }
        .sheet(item: $editingArtifact) { artifact in ArtifactEditSheet(contact: contact, mode: .edit(artifact)) }
        .sheet(item: $editingInteraction) { interaction in InteractionEditSheet(interaction: interaction) }
    }

    // MARK: - Masthead
    // Name in orbit weight, one status sentence, one context line.
    // The drift sentence is the only colored element on the page.

    private var masthead: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text(contact.name)
                .font(OrbitTypography.contactNameLarge(orbit: contact.targetOrbit))
                .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

            Text(driftSentence)
                .font(OrbitTypography.body)
                .foregroundStyle(contact.isDrifting ? AnyShapeStyle(contact.driftColor) : AnyShapeStyle(.secondary))

            if !contextLine.isEmpty {
                Text(contextLine)
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var driftSentence: String {
        let zone = contact.orbitZoneName
        guard contact.targetOrbit < 4 else {
            return "\(zone) — no cadence expected."
        }
        guard let days = contact.daysSinceLastContact else {
            return "\(zone) — no interactions logged yet."
        }
        let threshold = contact.cadenceThreshold
        if days > threshold {
            let over = days - threshold
            return "\(zone) — last contact \(contact.recencyDescription.lowercased()), \(over) day\(over == 1 ? "" : "s") past cadence."
        }
        return "\(zone) — last contact \(contact.recencyDescription.lowercased()), on cadence."
    }

    private var contextLine: String {
        var parts: [String] = []
        let constellationNames = (contact.constellations ?? []).map { "✦ \($0.name)" }
        if !constellationNames.isEmpty {
            parts.append(constellationNames.joined(separator: "  "))
        }
        let tags = contact.aggregatedTags.prefix(8).map { "#\($0.name)" }
        if !tags.isEmpty {
            parts.append(tags.joined(separator: " "))
        }
        return parts.joined(separator: "   ")
    }

    // MARK: - Lede
    // Notes as the opening paragraph, set in primary — this is the
    // most human material on the page and reads first.

    private var lede: some View {
        Text(contact.notes)
            .font(OrbitTypography.headline.weight(.regular))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Fact Sections
    // Curated order: Personal, Professional, Other, then Contact Info
    // demoted to a quieter block. No icons, no chevrons, no collapse —
    // curation replaces disclosure.

    private var factSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "FACTS") {
                Button { showAddArtifact = true } label: {
                    Text("Add")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if (contact.artifacts ?? []).isEmpty {
                Text("No facts saved yet.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, OrbitSpacing.md)
                    .padding(.bottom, OrbitSpacing.xl)
            } else {
                VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                    ForEach(groupedArtifacts, id: \.category) { group in
                        factGroup(group.category, artifacts: group.artifacts)
                    }
                }
                .padding(.top, OrbitSpacing.md)
                .padding(.bottom, OrbitSpacing.xl)
            }
        }
    }

    private func factGroup(_ category: ArtifactCategory, artifacts: [Artifact]) -> some View {
        // Contact Info is plumbing: demoted to caption-size values.
        let demoted = (category == .contactInfo)

        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            if groupedArtifacts.count > 1 {
                Text(category.rawValue.uppercased())
                    .font(OrbitTypography.footnote)
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)
            }

            ForEach(artifacts) { artifact in
                factRow(artifact, demoted: demoted)
            }
        }
    }

    private func factRow(_ artifact: Artifact, demoted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Text(artifact.key.lowercased())
                .font(OrbitTypography.footnote)
                .foregroundStyle(.secondary)
                .frame(width: keyColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(artifact.listValues, id: \.self) { item in
                    Text(item)
                        .font(demoted ? OrbitTypography.caption : OrbitTypography.body)
                        .foregroundStyle(demoted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingArtifact = artifact }
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(artifact)
                contact.refreshArtifactCache()
                try? modelContext.save()
            }
        }
    }

    // MARK: - Timeline
    // Flush-left rows with a thin date gutter. No cards, no fills.
    // Long-press for edit/delete; browsing never opens a sheet.

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "ACTIVITY") {
                HStack(spacing: OrbitSpacing.md) {
                    Text("\(contact.cachedInteractionCount)")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.quaternary)
                    Button { showAddInteraction = true } label: {
                        Text("Log")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showSearch {
                timelineFilters
                    .padding(.top, OrbitSpacing.md)
            }

            if filteredInteractions.isEmpty {
                Text(contact.cachedInteractionCount == 0
                     ? "No interactions logged."
                     : "No logs match your filters.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, OrbitSpacing.md)
            } else {
                VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                    ForEach(groupedInteractions, id: \.key) { group in
                        monthGroup(group)
                    }
                }
                .padding(.top, OrbitSpacing.md)
            }
        }
    }

    private var timelineFilters: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            HStack(spacing: OrbitSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Search interactions…", text: $interactionSearch)
                    .font(OrbitTypography.caption)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !interactionSearch.isEmpty {
                    Button { interactionSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if uniqueImpulses.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OrbitSpacing.md) {
                        impulseToggle("All", isActive: impulseFilter == nil) { impulseFilter = nil }
                        ForEach(uniqueImpulses, id: \.self) { impulse in
                            impulseToggle(impulse, isActive: impulseFilter?.lowercased() == impulse.lowercased()) {
                                impulseFilter = (impulseFilter?.lowercased() == impulse.lowercased()) ? nil : impulse
                            }
                        }
                    }
                }
            }
        }
    }

    private func impulseToggle(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(isActive ? OrbitTypography.captionMedium : OrbitTypography.caption)
                .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .underline(isActive)
        }
        .buttonStyle(.plain)
    }

    private func monthGroup(_ group: (key: String, interactions: [Interaction])) -> some View {
        let isCollapsed = collapsedMonths.contains(group.key)

        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsedMonths.remove(group.key) }
                    else { collapsedMonths.insert(group.key) }
                }
            } label: {
                HStack(spacing: OrbitSpacing.sm) {
                    Text(group.key)
                        .font(OrbitTypography.footnote)
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(.tertiary)
                    if isCollapsed {
                        Text("(\(group.interactions.count))")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    ForEach(group.interactions) { interaction in
                        timelineRow(interaction)
                    }
                }
            }
        }
    }

    private func timelineRow(_ interaction: Interaction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Text(interaction.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(OrbitTypography.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: dateGutterWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                Text(interaction.impulse)
                    .font(OrbitTypography.bodyMedium)

                if !interaction.content.isEmpty {
                    Text(interaction.content)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                if !interaction.tagNames.isEmpty {
                    Text(interaction.tagList.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingInteraction = interaction }
            Button("Delete", systemImage: "trash", role: .destructive) {
                interaction.isDeleted = true
                contact.refreshCachedFields()
                try? modelContext.save()
            }
        }
    }

    // MARK: - Section Rule
    // Hairline + uppercase label. The only structural device on the page.

    private func sectionRule<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Divider()
            HStack {
                Text(label)
                    .font(OrbitTypography.captionMedium)
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
        }
    }

    // MARK: - Quick Log

    private func quickLog(impulse: String) {
        let interaction = Interaction(impulse: impulse, date: Date())
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshCachedFields()
        spotlightIndexer.index(contact: contact)
        try? modelContext.save()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSearch.toggle()
                    if !showSearch {
                        interactionSearch = ""
                        impulseFilter = nil
                    }
                }
            } label: {
                Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }

            Button { showEditForm = true } label: { Image(systemName: "pencil") }

            Menu {
                Section("Quick Log") {
                    Button("Call", systemImage: "phone") { quickLog(impulse: "Call") }
                    Button("Text", systemImage: "message") { quickLog(impulse: "Text") }
                    Button("Coffee", systemImage: "cup.and.saucer") { quickLog(impulse: "Coffee") }
                    Button("Log Interaction…", systemImage: "plus.bubble") { showAddInteraction = true }
                }
                Section {
                    Button("Add Fact", systemImage: "key") { showAddArtifact = true }
                    Button(contact.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                        contact.isArchived.toggle()
                        contact.modifiedAt = Date()
                        if contact.isArchived { spotlightIndexer.deindex(contact: contact) }
                        else { spotlightIndexer.index(contact: contact) }
                        try? modelContext.save()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Artifact Categories & Filtering

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
            if ["birthday", "anniversary", "born", "dob", "spouse", "wife", "husband", "partner", "children", "kids", "likes", "dislikes", "hobbies", "interests", "allergies", "pronouns", "hometown", "zodiac", "nickname", "pet", "pets", "favorite"].contains(where: { k.contains($0) }) { return .personal }
            if ["company", "role", "title", "job", "department", "team", "met_at", "school", "university", "org", "organization", "industry"].contains(where: { k.contains($0) }) { return .professional }
            return .other
        }
    }

    /// Curated order — allCases order puts Personal first and Contact Info last.
    private var groupedArtifacts: [(category: ArtifactCategory, artifacts: [Artifact])] {
        let sorted = (contact.artifacts ?? []).sorted { $0.key < $1.key }
        let grouped = Dictionary(grouping: sorted) { ArtifactCategory.category(for: $0) }
        return ArtifactCategory.allCases.compactMap { category in
            guard let arts = grouped[category], !arts.isEmpty else { return nil }
            return (category: category, artifacts: arts)
        }
    }

    private var filteredInteractions: [Interaction] {
        var result = contact.activeInteractions
        if let filter = impulseFilter { result = result.filter { $0.impulse.lowercased() == filter.lowercased() } }
        if !interactionSearch.isEmpty {
            let query = interactionSearch.lowercased()
            result = result.filter { $0.impulse.lowercased().contains(query) || $0.content.lowercased().contains(query) || $0.tagNames.lowercased().contains(query) }
        }
        return result
    }

    private var uniqueImpulses: [String] {
        let impulses = contact.activeInteractions.map(\.impulse)
        var seen = Set<String>()
        return impulses.filter { seen.insert($0.lowercased()).inserted }.sorted()
    }

    private var groupedInteractions: [(key: String, interactions: [Interaction])] {
        let grouped = Dictionary(grouping: filteredInteractions) { $0.date.formatted(.dateTime.year().month(.wide)) }
        return grouped.map { (key: $0.key, interactions: $0.value) }
            .sorted { ($0.interactions.first?.date ?? .distantPast) > ($1.interactions.first?.date ?? .distantPast) }
    }
}
