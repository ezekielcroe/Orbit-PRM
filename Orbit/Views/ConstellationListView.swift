import SwiftUI
import SwiftData

// MARK: - ConstellationListView (Fix 4)
// Enhanced from a settings sub-view to a first-class navigation destination.
// Now shows aggregate stats: member count, drift count, shared tags, last activity.

struct ConstellationListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Constellation.name)
    private var constellations: [Constellation]

    @State private var showAddSheet = false
    @State private var constellationToEdit: Constellation?
    
    @Binding var selectedConstellation: Constellation?

    var body: some View {
        Group {
            if constellations.isEmpty {
                ContentUnavailableView(
                    "No Constellations",
                    systemImage: "star.circle",
                    description: Text("Group related contacts into constellations.\nUse *GroupName in the command palette to create one.")
                )
            } else {
                List(selection: $selectedConstellation) {
                    ForEach(constellations) { constellation in
                        ConstellationRowView(constellation: constellation)
                            .tag(constellation)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(constellation)
                                    try? modelContext.save()
                                }
                                
                                Button("Edit") {
                                    constellationToEdit = constellation
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
        .navigationTitle("Constellations")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .background {
            Color.clear
                .sheet(isPresented: $showAddSheet) {
                    ConstellationFormSheet()
                }
        }
        .background {
            Color.clear
                .sheet(item: $constellationToEdit) { constellation in
                    ConstellationFormSheet(editingConstellation: constellation)
                }
        }
    }
}

// MARK: - Constellation Row (Fix 4: Shows aggregate stats)

struct ConstellationRowView: View {
    let constellation: Constellation

    private var activeMembers: [Contact] {
        constellation.contacts.filter { !$0.isArchived }
    }

    private var driftingCount: Int {
        activeMembers.filter { $0.isDrifting }.count
    }

    private var lastGroupActivity: Date? {
        activeMembers
            .compactMap { $0.lastContactDate }
            .max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            HStack {
                Text("✦ \(constellation.name)")
                    .font(OrbitTypography.bodyMedium)

                Spacer()

                Text("\(activeMembers.count)")
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(.secondary)
                Image(systemName: "person.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: OrbitSpacing.md) {
                if driftingCount > 0 {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                        Text("\(driftingCount) drifting")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let lastDate = lastGroupActivity {
                    Text("Last: \(lastDate.relativeDescription)")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }

                if !constellation.notes.isEmpty {
                    Text(constellation.notes)
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // FIX 4: Show shared interaction tags across the group
            let sharedTags = topSharedTags(limit: 3)
            if !sharedTags.isEmpty {
                Text(sharedTags.map { "#\($0)" }.joined(separator: " "))
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(OrbitColors.syntaxTag.opacity(0.7))
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
    }

    /// Find the most common tags across all members' interactions
    private func topSharedTags(limit: Int) -> [String] {
        var tagCounts: [String: Int] = [:]
        for contact in activeMembers {
            for tag in contact.aggregatedTags {
                tagCounts[tag.name, default: 0] += tag.count
            }
        }
        return tagCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}

// MARK: - Constellation Form Sheet

struct ConstellationFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    
    var editingConstellation: Constellation?

    init(editingConstellation: Constellation? = nil) {
        self.editingConstellation = editingConstellation
        if let constellation = editingConstellation {
            _name = State(initialValue: constellation.name)
            _notes = State(initialValue: constellation.notes)
        } else {
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g., College Friends)", text: $name)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .navigationTitle(editingConstellation == nil ? "New Constellation" : "Edit Constellation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingConstellation == nil ? "Create" : "Save") {
                        if let constellation = editingConstellation {
                            constellation.name = name
                            constellation.notes = notes
                        } else {
                            let constellation = Constellation(name: name, notes: notes)
                            modelContext.insert(constellation)
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Constellation Detail View

struct ConstellationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var constellation: Constellation

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var allContacts: [Contact]
    
    // Facet State
        enum DetailTab { case members, activity }
        @State private var selectedTab: DetailTab = .members
        
        // Add this new state:
        @State private var showAddInteraction = false

    // MARK: - Computed Data
    
    private var activeMembers: [Contact] {
        constellation.contacts
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var driftingMembers: [Contact] {
        activeMembers.filter { $0.isDrifting }
    }

    private var avgDaysSinceContact: Int? {
        let days = activeMembers.compactMap { $0.daysSinceLastContact }
        guard !days.isEmpty else { return nil }
        return days.reduce(0, +) / days.count
    }

    private var groupInteractions: [Interaction] {
        activeMembers
            .flatMap { $0.activeInteractions }
            .sorted { $0.date > $1.date }
    }

    private var sharedTagStats: [(name: String, count: Int)] {
        var tagCounts: [String: Int] = [:]
        for contact in activeMembers {
            for tag in contact.aggregatedTags {
                tagCounts[tag.name, default: 0] += tag.count
            }
        }
        return tagCounts
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                
                // 1. The Sticky Hero Header
                constellationHeader
                    .padding(.bottom, OrbitSpacing.md)

                // 2. The Pinned Facet Toggle
                Section {
                    switch selectedTab {
                    case .members:
                        membersFacet
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .activity:
                        activityFacet
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                } header: {
                    facetPicker
                }
            }
            
            .background(OrbitColors.commandBackground.ignoresSafeArea())
                    .navigationTitle(constellation.name)
                    .navigationBarTitleDisplayMode(.inline)
                    // 1. ADD TOOLBAR
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Log Activity", systemImage: "plus.bubble") {
                                showAddInteraction = true
                            }
                        }
                    }
                    // 2. ADD SHEET
                    .sheet(isPresented: $showAddInteraction) {
                        ConstellationInteractionSheet(constellation: constellation)
                    }
        }
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle(constellation.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero Header

    private var constellationHeader: some View {
        VStack(spacing: OrbitSpacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "star.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)
            }
            .padding(.top, OrbitSpacing.md)

            // Title & Notes
            VStack(spacing: OrbitSpacing.xs) {
                Text(constellation.name)
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .multilineTextAlignment(.center)

                if !constellation.notes.isEmpty {
                    Text(constellation.notes)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OrbitSpacing.lg)
                }
            }

            // Group Stats
            HStack(spacing: OrbitSpacing.lg) {
                statBadge("\(activeMembers.count)", label: "Members", icon: "person.2")

                if let avg = avgDaysSinceContact {
                    statBadge("\(avg)d", label: "Avg gap", icon: "clock")
                }

                if !driftingMembers.isEmpty {
                    statBadge("\(driftingMembers.count)", label: "Drifting", icon: "exclamationmark.circle", color: .orange)
                }
                
                statBadge("\(groupInteractions.count)", label: "Total logs", icon: "text.bubble")
            }
            .padding(.top, OrbitSpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private func statBadge(_ value: String, label: String, icon: String, color: Color = .secondary) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(value)
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Facet Picker

    private var facetPicker: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab.animation(.easeInOut(duration: 0.2))) {
                Text("Members").tag(DetailTab.members)
                Text("Activity").tag(DetailTab.activity)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.vertical, OrbitSpacing.sm)
            
            Divider()
        }
        .background(.regularMaterial)
    }

    // MARK: - Members Facet

    private var membersFacet: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xl) {
            
            // Add Members
            addMembersSection
                .padding(.horizontal, OrbitSpacing.lg)
                .padding(.top, OrbitSpacing.md)

            // Current Members
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                Text("CURRENT MEMBERS")
                    .font(OrbitTypography.captionMedium)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, OrbitSpacing.lg)

                if activeMembers.isEmpty {
                    Text("No active members.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, OrbitSpacing.lg)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(activeMembers) { contact in
                            memberRow(contact)
                        }
                    }
                }
            }
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }

    private func memberRow(_ contact: Contact) -> some View {
        HStack(spacing: OrbitSpacing.md) {
            if contact.isDrifting {
                Circle()
                    .fill(contact.driftColor)
                    .frame(width: 6, height: 6)
            } else {
                Color.clear.frame(width: 6, height: 6) // Alignment spacer
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                Text(contact.recencyDescription)
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(contact.isDrifting ? contact.driftColor : .secondary)
            }

            Spacer()

            Button {
                withAnimation {
                    constellation.contacts.removeAll { $0.id == contact.id }
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, OrbitSpacing.sm)
        .padding(.horizontal, OrbitSpacing.lg)
        .background(Color.secondary.opacity(0.02))
        .padding(.vertical, 1)
    }

    private var addMembersSection: some View {
        let nonMembers = allContacts.filter { contact in
            !constellation.contacts.contains(where: { $0.id == contact.id })
        }

        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text("ADD MEMBERS")
                .font(OrbitTypography.captionMedium)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            if nonMembers.isEmpty {
                Text("All your contacts are already in this constellation.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OrbitSpacing.sm) {
                        ForEach(nonMembers.prefix(15)) { contact in
                            Button {
                                withAnimation {
                                    constellation.contacts.append(contact)
                                    try? modelContext.save()
                                }
                            } label: {
                                Label(contact.name, systemImage: "plus")
                                    .font(OrbitTypography.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Activity Facet

    private var activityFacet: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xl) {
            
            // Shared Group Tags
            if !sharedTagStats.isEmpty {
                VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                    Text("SHARED TAGS")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(sharedTagStats.prefix(10), id: \.name) { tag in
                            HStack(spacing: 2) {
                                Text("#\(tag.name)")
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(OrbitColors.syntaxTag)
                                Text("×\(tag.count)")
                                    .font(OrbitTypography.footnote)
                                    .foregroundStyle(OrbitColors.syntaxTag.opacity(0.6))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(OrbitColors.syntaxTag.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, OrbitSpacing.lg)
                .padding(.top, OrbitSpacing.md)
            }

            // Timeline
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                HStack {
                    Text("TIMELINE")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    Button {
                        showAddInteraction = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OrbitSpacing.lg)

                if groupInteractions.isEmpty {
                    // UPDATE THE EMPTY STATE
                    ContentUnavailableView {
                        Label("No Activity", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    } description: {
                        Text("Log a group interaction to see it appear here and on every member's timeline.")
                    } actions: {
                        Button("Log Interaction") {
                            showAddInteraction = true
                        }
                        .buttonStyle(.borderedProminent)
                        }
                    .padding(.top, OrbitSpacing.md)
                } else {
                    LazyVStack(alignment: .leading, spacing: OrbitSpacing.md) {
                        ForEach(groupInteractions) { interaction in
                            InteractionRowView(interaction: interaction)
                                .padding(OrbitSpacing.sm)
                                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, OrbitSpacing.lg)
                        }
                    }
                }
            }
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }
}
