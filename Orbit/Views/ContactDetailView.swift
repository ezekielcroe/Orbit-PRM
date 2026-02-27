import SwiftUI
import SwiftData

// MARK: - ContactDetailView
// Overhauled to use a "Facet" pattern (Profile vs. Activity) to prevent
// infinite scrolling on heavy contacts. Features a polished monogram header.

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Bindable var contact: Contact

    // Navigation / Facet State
    enum DetailTab { case profile, activity }
    @State private var selectedTab: DetailTab = .profile

    // Sheet State
    @State private var showEditForm = false
    @State private var showAddArtifact = false
    @State private var showAddInteraction = false
    @State private var editingArtifact: Artifact?
    @State private var editingInteraction: Interaction?

    // Profile State
    @State private var collapsedArtifactCategories: Set<String> = []

    // Activity State
    @State private var impulseFilter: String?
    @State private var interactionSearch = ""
    @State private var expandedMonths: Set<String> = []

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                
                // 1. The Sticky Hero Header
                contactHeroHeader
                    .padding(.bottom, OrbitSpacing.md)

                // 2. The Pinned Facet Toggle
                Section {
                    switch selectedTab {
                    case .profile:
                        profileFacet
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .activity:
                        activityFacet
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                } header: {
                    facetPicker
                }
            }
        }
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Sheets
        .sheet(isPresented: $showEditForm) { ContactFormSheet(mode: .edit(contact)) }
        .sheet(isPresented: $showAddArtifact) { ArtifactEditSheet(contact: contact, mode: .add) }
        .sheet(isPresented: $showAddInteraction) { QuickInteractionSheet(contact: contact) }
        .sheet(item: $editingArtifact) { artifact in ArtifactEditSheet(contact: contact, mode: .edit(artifact)) }
        .sheet(item: $editingInteraction) { interaction in InteractionEditSheet(interaction: interaction) }
        .onAppear {
            let recentKeys = groupedInteractions.prefix(2).map(\.key)
            expandedMonths = Set(recentKeys)
        }
    }

    // MARK: - Hero Header

    private var contactHeroHeader: some View {
        VStack(spacing: OrbitSpacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(contact.isDrifting ? contact.driftColor.opacity(0.2) : Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Text(initials(for: contact.name))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(contact.isDrifting ? contact.driftColor : Color.accentColor)
            }
            .padding(.top, OrbitSpacing.md)

            // Name & Orbit
            VStack(spacing: OrbitSpacing.xs) {
                Text(contact.name)
                    .font(OrbitTypography.contactNameLarge(orbit: contact.targetOrbit))
                    .multilineTextAlignment(.center)

                HStack(spacing: OrbitSpacing.sm) {
                    Label(contact.orbitZoneName, systemImage: "circle.dotted")
                    if contact.daysSinceLastContact != nil {
                        Text("·").foregroundStyle(.tertiary)
                        Label(contact.recencyDescription, systemImage: "clock")
                            .foregroundStyle(contact.isDrifting ? contact.driftColor : .secondary)
                    }
                }
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
            }

            // Quick Actions
            HStack(spacing: OrbitSpacing.md) {
                quickActionCircle("Call", icon: "phone.fill") { quickLog(impulse: "Call") }
                quickActionCircle("Message", icon: "message.fill") { quickLog(impulse: "Text") }
                quickActionCircle("Coffee", icon: "cup.and.saucer.fill") { quickLog(impulse: "Coffee") }
                quickActionCircle("Log", icon: "plus") { showAddInteraction = true }
            }
            .padding(.top, OrbitSpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickActionCircle(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .background(Color.secondary.opacity(0.1), in: Circle())
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "?" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return (String(parts[0].prefix(1)) + String(parts.last!.prefix(1))).uppercased()
    }

    // MARK: - Facet Picker (Sticky Header)

    private var facetPicker: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab.animation(.easeInOut(duration: 0.2))) {
                Text("Profile").tag(DetailTab.profile)
                Text("Activity").tag(DetailTab.activity)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.vertical, OrbitSpacing.sm)
            
            Divider()
        }
        // Use standard background to blur/block content when pinned to top
        .background(.regularMaterial)
    }

    // MARK: - Profile Facet

    private var profileFacet: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xl) {
            
            // Context Block (Notes, Tags, Constellations)
            VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                }

                if !contact.aggregatedTags.isEmpty || !contact.constellations.isEmpty {
                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(contact.aggregatedTags.prefix(8)) { tag in
                            Text("#\(tag.name)")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(OrbitColors.syntaxTag)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(OrbitColors.syntaxTag.opacity(0.1), in: Capsule())
                        }
                        ForEach(contact.constellations) { constellation in
                            Text("✦ \(constellation.name)")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.top, OrbitSpacing.md)

            // Artifacts
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

                if contact.artifacts.isEmpty {
                    Text("No artifacts saved yet.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(groupedArtifacts, id: \.category) { group in
                        artifactCategorySection(group.category, artifacts: group.artifacts)
                    }
                }
            }
            .padding(.horizontal, OrbitSpacing.lg)
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }

    // MARK: - Activity Facet

    private var activityFacet: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            
            // Search & Filter
            VStack(spacing: OrbitSpacing.sm) {
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
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

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
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.top, OrbitSpacing.md)

            // Timeline List
            if filteredInteractions.isEmpty {
                ContentUnavailableView("No Interactions", systemImage: "bubble.left.and.exclamationmark.bubble.right", description: Text("No logs match your filters."))
                    .padding(.top, OrbitSpacing.xl)
            } else {
                LazyVStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                    ForEach(Array(groupedInteractions.enumerated()), id: \.element.key) { index, group in
                        collapsibleMonthGroup(group)
                    }
                }
                .padding(.horizontal, OrbitSpacing.lg)
            }
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }

    // MARK: - Support Sub-Views (Unchanged Data Logic)

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

    private func collapsibleMonthGroup(_ group: (key: String, interactions: [Interaction])) -> some View {
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
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: OrbitSpacing.sm) {
                    ForEach(group.interactions) { interaction in
                        InteractionRowView(interaction: interaction)
                            .padding(OrbitSpacing.sm)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { editingInteraction = interaction }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingInteraction = interaction }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    interaction.isDeleted = true
                                    contact.refreshLastContactDate()
                                    try? modelContext.save()
                                }
                            }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func artifactCategorySection(_ category: ArtifactCategory, artifacts: [Artifact]) -> some View {
        let isCollapsed = collapsedArtifactCategories.contains(category.rawValue)

        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsedArtifactCategories.remove(category.rawValue) }
                    else { collapsedArtifactCategories.insert(category.rawValue) }
                }
            } label: {
                HStack(spacing: OrbitSpacing.xs) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary).frame(width: 12)
                    Image(systemName: category.icon).font(.caption2).foregroundStyle(.tertiary)
                    Text(category.rawValue.uppercased()).font(OrbitTypography.footnote).tracking(1).foregroundStyle(.tertiary)
                    Text("(\(artifacts.count))").font(OrbitTypography.footnote).foregroundStyle(.quaternary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.top, OrbitSpacing.sm)

            if !isCollapsed {
                ForEach(artifacts) { artifact in
                    ArtifactRowView(artifact: artifact)
                        .contentShape(Rectangle())
                        .onTapGesture { editingArtifact = artifact }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingArtifact = artifact }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(artifact)
                                contact.modifiedAt = Date()
                                try? modelContext.save()
                            }
                        }
                }
            }
        }
    }

    private func quickLog(impulse: String) {
        let interaction = Interaction(impulse: impulse, date: Date())
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshLastContactDate()
        spotlightIndexer.index(contact: contact)
        try? modelContext.save()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { showEditForm = true } label: { Image(systemName: "pencil") }
            
            Menu {
                Button("Add Artifact", systemImage: "key") { showAddArtifact = true }
                Button("Log Interaction", systemImage: "plus.bubble") { showAddInteraction = true }
                Divider()
                Button(contact.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                    contact.isArchived.toggle()
                    contact.modifiedAt = Date()
                    if contact.isArchived { spotlightIndexer.deindex(contact: contact) }
                    else { spotlightIndexer.index(contact: contact) }
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Artifact Categories & Filtering (Unchanged)
    
    enum ArtifactCategory: String, CaseIterable {
        case contactInfo = "Contact Info", personal = "Personal", professional = "Professional", other = "Other"
        var icon: String {
            switch self {
            case .contactInfo: return "phone.circle"
            case .personal: return "heart.circle"
            case .professional: return "briefcase"
            case .other: return "ellipsis.circle"
            }
        }
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

    private var groupedArtifacts: [(category: ArtifactCategory, artifacts: [Artifact])] {
        let sorted = contact.artifacts.sorted { $0.key < $1.key }
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
