//
//  ConstellationDetailView.swift
//  Orbit
//

import SwiftUI
import SwiftData

// MARK: - Constellation Detail View
// Editorial one-pager, matching ContactDetailView's grammar.
// Single scroll: name → status sentence → notes lede → member roster →
// flush timeline. Color appears only where drift does. Batch member
// removal lives behind an explicit Select mode instead of a permanent
// checkbox column.

struct ConstellationDetailView: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Bindable var constellation: Constellation
    @Binding var selectedContact: Contact?

    // Sheet State
    @State private var showAddMembers = false
    @State private var showEditGroup = false

    // Select Mode State
    @State private var isSelecting = false
    @State private var selectedMembers: Set<UUID> = []
    @State private var showRemoveConfirmation = false

    // Timeline State
    @State private var collapsedMonths: Set<String> = []   // empty = everything visible

    private let dateGutterWidth: CGFloat = 52

    // MARK: - Computed Data

    /// Drifting members first (most severe on top), then the rest A–Z.
    /// The roster doubles as a review surface: who needs attention leads.
    private var activeMembers: [Contact] {
        let members = (constellation.contacts ?? []).filter { !$0.isArchived }
        let drifting = members.filter(\.isDrifting).sorted { $0.driftRatio > $1.driftRatio }
        let onCadence = members.filter { !$0.isDrifting }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return drifting + onCadence
    }

    private var driftingMembers: [Contact] {
        activeMembers.filter(\.isDrifting)
    }

    private var avgDaysSinceContact: Int? {
        let days = activeMembers.compactMap { $0.daysSinceLastContact }
        guard !days.isEmpty else { return nil }
        return days.reduce(0, +) / days.count
    }

    private var groupedMemberInteractions: [InteractionGroup] {
        let allInteractions = activeMembers.flatMap { $0.interactions ?? [] }
        let activeInteractions = allInteractions.filter { !$0.isDeleted }
        let grouped = Dictionary(grouping: activeInteractions) { interaction in
            interaction.batchID ?? UUID()
        }
        return grouped.map { (_, interactions) in
            InteractionGroup(
                id: interactions.first?.batchID ?? UUID(),
                interactions: interactions
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Timeline grouped by month, mirroring ContactDetailView.
    private var groupedByMonth: [(key: String, groups: [InteractionGroup])] {
        let byMonth = Dictionary(grouping: groupedMemberInteractions) {
            $0.date.formatted(.dateTime.year().month(.wide))
        }
        return byMonth.map { (key: $0.key, groups: $0.value.sorted { $0.date > $1.date }) }
            .sorted { ($0.groups.first?.date ?? .distantPast) > ($1.groups.first?.date ?? .distantPast) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.top, OrbitSpacing.lg)
                    .padding(.bottom, OrbitSpacing.xl)

                if !constellation.notes.isEmpty {
                    lede
                        .padding(.bottom, OrbitSpacing.xl)
                }

                membersSection
                timelineSection
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.bottom, OrbitSpacing.xxxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle(constellation.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                selectionBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelecting)
        .sheet(isPresented: $showAddMembers) {
            AddMembersSheet(constellation: constellation)
        }
        .sheet(isPresented: $showEditGroup) {
            ConstellationFormSheet(editingConstellation: constellation)
        }
        .alert(
            "Remove \(selectedMembers.count) Member\(selectedMembers.count == 1 ? "" : "s")?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) { removeSelectedMembers() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll be removed from ✦ \(constellation.name). Nothing else about them changes, and you can undo this.")
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text("✦ \(constellation.name)")
                .font(.system(size: 28, weight: .semibold, design: .default))

            Text(statusSentence)
                .font(OrbitTypography.body)
                .foregroundStyle(driftingMembers.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))

            if !constellation.aliasList.isEmpty {
                Text("aka " + constellation.aliasList.joined(separator: ", "))
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusSentence: String {
        guard !activeMembers.isEmpty else {
            return "No active members yet."
        }
        let count = "\(activeMembers.count) member\(activeMembers.count == 1 ? "" : "s")"
        var clauses: [String] = []
        if !driftingMembers.isEmpty {
            clauses.append("\(driftingMembers.count) due for a catch-up")
        } else {
            clauses.append("everyone on track")
        }
        if let avg = avgDaysSinceContact {
            clauses.append("average gap \(avg) day\(avg == 1 ? "" : "s")")
        }
        return "\(count) — \(clauses.joined(separator: ", "))."
    }

    // MARK: - Lede

    private var lede: some View {
        Text(constellation.notes)
            .font(OrbitTypography.headline.weight(.regular))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Members Section
    // Flush roster: name in orbit weight with recency opacity, recency
    // right-aligned. Drifting members lead. Tap navigates; long-press
    // removes; Select mode enables batch removal.

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "MEMBERS") {
                HStack(spacing: OrbitSpacing.md) {
                    Text("\(activeMembers.count)")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.quaternary)
                    Button("Add") { showAddMembers = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if activeMembers.isEmpty {
                Text("No active members.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, OrbitSpacing.md)
                    .padding(.bottom, OrbitSpacing.xl)
            } else {
                VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    ForEach(activeMembers) { contact in
                        memberRow(contact)
                    }
                }
                .padding(.top, OrbitSpacing.md)
                .padding(.bottom, OrbitSpacing.xl)
            }
        }
    }

    private func memberRow(_ contact: Contact) -> some View {
        let isSelected = selectedMembers.contains(contact.id)

        return HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }

            Text(contact.name)
                .font(OrbitTypography.contactName(orbit: contact.targetOrbit))

            Spacer(minLength: OrbitSpacing.md)

            Text(contact.recencyDescription)
                .font(OrbitTypography.caption)
                .foregroundStyle(contact.isDrifting ? AnyShapeStyle(contact.driftColor) : AnyShapeStyle(.secondary))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleMemberSelection(for: contact.id)
            } else {
                selectedContact = contact
            }
        }
        .contextMenu {
            Button("Log…", systemImage: "plus.bubble") { router.log([contact]) }
            Button("Remove from group", systemImage: "person.badge.minus", role: .destructive) {
                withAnimation { store.removeFromGroup([contact], group: constellation) }
            }
        }
    }

    private func toggleMemberSelection(for id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedMembers.contains(id) {
                selectedMembers.remove(id)
            } else {
                selectedMembers.insert(id)
            }
        }
    }

    // MARK: - Selection Bar
    // Plain bottom bar in Select mode: hairline, text actions, no capsule.

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: OrbitSpacing.lg) {
                Text("\(selectedMembers.count) selected")
                    .font(OrbitTypography.captionMedium)

                Button("Select All") {
                    selectedMembers = Set(activeMembers.map(\.id))
                }
                .font(OrbitTypography.caption)

                Spacer()

                Button("Remove", role: .destructive) {
                    showRemoveConfirmation = true
                }
                .font(OrbitTypography.captionMedium)
                .disabled(selectedMembers.isEmpty)

                Button("Done") {
                    exitSelectMode()
                }
                .font(OrbitTypography.captionMedium)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.vertical, OrbitSpacing.md)
            .background(OrbitColors.commandBackground)
        }
    }

    private func exitSelectMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = false
            selectedMembers.removeAll()
        }
    }

    private func removeSelectedMembers() {
        let targets = activeMembers.filter { selectedMembers.contains($0.id) }
        withAnimation { store.removeFromGroup(targets, group: constellation) }
        exitSelectMode()
    }

    // MARK: - Timeline Section
    // Group events flush-left with a date gutter, month headers expanded
    // by default. Participants render as a plain text line.

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "ACTIVITY") {
                HStack(spacing: OrbitSpacing.md) {
                    Text("\(groupedMemberInteractions.count)")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.quaternary)
                    Button("Log for everyone") { router.log(group: constellation) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if groupedMemberInteractions.isEmpty {
                Text("No group activity logged. Logged events appear here and on every member's timeline.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, OrbitSpacing.md)
            } else {
                VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                    ForEach(groupedByMonth, id: \.key) { month in
                        monthGroup(month)
                    }
                }
                .padding(.top, OrbitSpacing.md)
            }
        }
    }

    private func monthGroup(_ month: (key: String, groups: [InteractionGroup])) -> some View {
        let isCollapsed = collapsedMonths.contains(month.key)

        return VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsedMonths.remove(month.key) }
                    else { collapsedMonths.insert(month.key) }
                }
            } label: {
                HStack(spacing: OrbitSpacing.sm) {
                    Text(month.key)
                        .font(OrbitTypography.footnote)
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(.tertiary)
                    if isCollapsed {
                        Text("(\(month.groups.count))")
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
                    ForEach(month.groups) { group in
                        timelineRow(group)
                    }
                }
            }
        }
    }

    private func timelineRow(_ group: InteractionGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Text(group.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(OrbitTypography.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: dateGutterWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                Text(group.impulse)
                    .font(OrbitTypography.bodyMedium)

                Text(participantLine(for: group))
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)

                if !group.content.isEmpty {
                    Text(group.content)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                if !group.tagNames.isEmpty {
                    Text(group.tagList.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { router.edit(group.representative) }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { router.edit(group.representative) }
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(group.representative, includeBatch: true)
            }
        }
    }

    /// "everyone" when the event covers every active member; otherwise
    /// names up to four, then "+N more".
    private func participantLine(for group: InteractionGroup) -> String {
        let participants = group.contacts
        let memberIDs = Set(activeMembers.map(\.id))
        let participantIDs = Set(participants.map(\.id))

        if participants.count > 1 && participantIDs == memberIDs {
            return "with everyone"
        }
        let names = participants.map(\.name)
        if names.count <= 4 {
            return "with \(names.joined(separator: ", "))"
        }
        let shown = names.prefix(4).joined(separator: ", ")
        return "with \(shown) +\(names.count - 4) more"
    }

    // MARK: - Section Rule

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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Add Members", systemImage: "person.badge.plus") {
                showAddMembers = true
            }
            Button("Log for everyone", systemImage: "plus.bubble") {
                router.log(group: constellation)
            }
            Menu {
                Button("Edit group", systemImage: "pencil") { showEditGroup = true }
                Button("Select Members", systemImage: "checkmark.circle") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Add Members Sheet

struct AddMembersSheet: View {
    @Environment(OrbitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Bindable var constellation: Constellation

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var allContacts: [Contact]

    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText = ""

    /// Contacts not already in this constellation.
    private var availableContacts: [Contact] {
        let memberIDs = Set((constellation.contacts ?? []).map(\.id))
        let available = allContacts.filter { !memberIDs.contains($0.id) }
        if searchText.isEmpty { return available }
        let query = searchText.lowercased()
        return available.filter { $0.matchesSearch(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableContacts.isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "Everyone's Here",
                        systemImage: "person.2.fill",
                        description: Text("All your active contacts are already in this group.")
                    )
                } else {
                    List {
                        if !availableContacts.isEmpty {
                            Section {
                                selectAllButton
                            }
                        }

                        Section(header: Text("\(availableContacts.count) Available")) {
                            ForEach(availableContacts) { contact in
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        if selectedIDs.contains(contact.id) {
                                            selectedIDs.remove(contact.id)
                                        } else {
                                            selectedIDs.insert(contact.id)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: OrbitSpacing.md) {
                                        Image(systemName: selectedIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedIDs.contains(contact.id) ? .blue : .secondary)
                                            .font(.title3)
                                            .contentTransition(.symbolEffect(.replace))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(contact.name)
                                                .font(OrbitTypography.bodyMedium)
                                                .foregroundStyle(.primary)
                                            Text(contact.orbitZoneName)
                                                .font(OrbitTypography.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search contacts...")
                }
            }
            .navigationTitle("Add Members")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addSelectedMembers()
                        dismiss()
                    } label: {
                        Text(selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    // MARK: - Select All

    private var allFilteredAreSelected: Bool {
        guard !availableContacts.isEmpty else { return false }
        return availableContacts.allSatisfy { selectedIDs.contains($0.id) }
    }

    private var selectAllButton: some View {
        Button {
            let newState = !allFilteredAreSelected
            for contact in availableContacts {
                if newState {
                    selectedIDs.insert(contact.id)
                } else {
                    selectedIDs.remove(contact.id)
                }
            }
        } label: {
            HStack {
                Image(systemName: allFilteredAreSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(allFilteredAreSelected ? .blue : .secondary)
                    .font(.title3)
                Text(allFilteredAreSelected ? "Deselect All" : "Select All")
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save

    private func addSelectedMembers() {
        let contactsToAdd = allContacts.filter { selectedIDs.contains($0.id) }
        store.addToGroup(contactsToAdd, group: constellation)
    }
}
