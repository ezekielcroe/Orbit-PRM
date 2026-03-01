//
//  ConstellationDetailView.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 27/2/26.
//

import SwiftUI
import SwiftData

// MARK: - Row Geometry Tracking for Drag-to-Select (Constellation Members)

struct MemberRowFrameData: Equatable {
    let id: UUID
    let frame: CGRect
}

struct MemberRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MemberRowFrameData] = []
    static func reduce(value: inout [MemberRowFrameData], nextValue: () -> [MemberRowFrameData]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Constellation Detail View

struct ConstellationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var constellation: Constellation
    @Binding var selectedContact: Contact?
    
    // Facet State
        enum DetailTab { case members, activity }
        @State private var selectedTab: DetailTab = .members
        
        @State private var showAddInteraction = false
        @State private var showAddMembers = false

    // Member Selection State
    @State private var selectedMembers: Set<UUID> = []
    @State private var showRemoveConfirmation = false
    @State private var contactToView: Contact?

    // Drag-to-select State
    @State private var memberRowFrames: [MemberRowFrameData] = []
    @State private var dragSelectionState: Bool? = nil
    @State private var isScrubbing = false

    // MARK: - Computed Data
    
    private var activeMembers: [Contact] {
        (constellation.contacts ?? [])
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

    private var groupedMemberInteractions: [InteractionGroup] {
        let allInteractions = activeMembers.flatMap { $0.activeInteractions }
        return InteractionGroup.group(allInteractions)
    }

    private var sharedTagStats: [(name: String, count: Int)] {
            var tagCounts: [String: Int] = [:]
            for contact in activeMembers {
                let tags = contact.cachedTagSummary.split(separator: ",")
                for tag in tags {
                    let name = tag.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        tagCounts[name, default: 0] += 1
                    }
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
        }
        .scrollDisabled(isScrubbing)
        .coordinateSpace(name: "MemberTableSpace")
        .onPreferenceChange(MemberRowFramePreferenceKey.self) { frames in
            self.memberRowFrames = frames
        }
        // Scrub Selection Gesture (only activates in checkbox column)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard selectedTab == .members else { return }
                    guard value.startLocation.x < 50 else { return }

                    if !isScrubbing {
                        isScrubbing = true
                    }

                    if let row = memberRowFrames.first(where: {
                        $0.frame.minY <= value.location.y && $0.frame.maxY >= value.location.y
                    }) {
                        if dragSelectionState == nil {
                            dragSelectionState = !selectedMembers.contains(row.id)
                        }

                        if dragSelectionState == true {
                            selectedMembers.insert(row.id)
                        } else {
                            selectedMembers.remove(row.id)
                        }
                    }
                }
                .onEnded { _ in
                    isScrubbing = false
                    dragSelectionState = nil
                }
        )
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle(constellation.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay(alignment: .bottom) {
            if !selectedMembers.isEmpty {
                floatingActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, OrbitSpacing.xl)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedMembers.isEmpty)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Members", systemImage: "person.badge.plus") {
                    showAddMembers = true
                }
                Button("Log Activity", systemImage: "plus.bubble") {
                    showAddInteraction = true
                }
            }
        }
        .sheet(isPresented: $showAddInteraction) {
            ConstellationInteractionSheet(constellation: constellation)
        }
        .sheet(isPresented: $showAddMembers) {
            AddMembersSheet(constellation: constellation)
        }
        .alert(
            "Remove \(selectedMembers.count) Member\(selectedMembers.count == 1 ? "" : "s")?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) {
                removeSelectedMembers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the selected contacts from ✦ \(constellation.name). Their data is not deleted.")
        }
        .onChange(of: selectedTab) { _, _ in
            // Clear selection when switching tabs
            selectedMembers.removeAll()
        }
        .navigationDestination(item: $contactToView) { contact in
                    ContactDetailView(contact: contact)
        }
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
                
                statBadge("\(groupedMemberInteractions.count)", label: "Events", icon: "text.bubble")
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
            
            // Current Members
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                HStack {
                    Text("CURRENT MEMBERS")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, OrbitSpacing.lg)

                if activeMembers.isEmpty {
                    Text("No active members.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, OrbitSpacing.lg)
                } else {
                    VStack(spacing: 0) {
                        ForEach(activeMembers) { contact in
                            memberRow(contact)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: MemberRowFramePreferenceKey.self,
                                            value: [MemberRowFrameData(
                                                id: contact.id,
                                                frame: geo.frame(in: .named("MemberTableSpace"))
                                            )]
                                        )
                                    }
                                )
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(.top, OrbitSpacing.md)

            // Bottom spacer for floating bar clearance
            Color.clear
                .frame(height: 80)
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }

    private func memberRow(_ contact: Contact) -> some View {
        let isSelected = selectedMembers.contains(contact.id)

        return HStack(spacing: OrbitSpacing.md) {
            // Checkbox Column
            Button {
                toggleMemberSelection(for: contact.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .padding(.vertical, OrbitSpacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Drift indicator
            if contact.isDrifting {
                Circle()
                    .fill(contact.driftColor)
                    .frame(width: 6, height: 6)
            } else {
                Color.clear.frame(width: 6, height: 6)
            }

            // Content Column (tap navigates to contact)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                Text(contact.recencyDescription)
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(contact.isDrifting ? contact.driftColor : .secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, OrbitSpacing.sm)
        .padding(.horizontal, OrbitSpacing.md)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.secondary.opacity(0.02))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedContact = contact // Keeps global state in sync
            contactToView = contact   // Triggers the push
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

    // MARK: - Floating Action Bar

    private var floatingActionBar: some View {
        HStack(spacing: OrbitSpacing.md) {
            Text("\(selectedMembers.count) selected")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(.primary)

            Divider()
                .frame(height: 16)

            Button("Select All") {
                selectedMembers = Set(activeMembers.map(\.id))
            }
            .font(OrbitTypography.caption)
            .foregroundStyle(.blue)

            Spacer()

            Button {
                selectedMembers.removeAll()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                showRemoveConfirmation = true
            } label: {
                Label("Remove", systemImage: "person.badge.minus")
                    .font(OrbitTypography.captionMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.regular)
        }
        .padding(.horizontal, OrbitSpacing.lg)
        .padding(.vertical, OrbitSpacing.sm)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    // MARK: - Remove Selected Members

    private func removeSelectedMembers() {
        withAnimation {
            constellation.contacts?.removeAll { selectedMembers.contains($0.id) }
            try? modelContext.save()
            selectedMembers.removeAll()
        }
    }

    // MARK: - Activity Facet

    private var activityFacet: some View {
        VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("TIMELINE")
                                .font(OrbitTypography.captionMedium)
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, OrbitSpacing.lg)

                        if groupedMemberInteractions.isEmpty {
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
                            VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                                ForEach(groupedMemberInteractions) { group in
                                    InteractionRowContent(
                                        group: group,
                                        showContactNames: true,
                                        showChevron: false
                                    )
                                    .padding(OrbitSpacing.sm)
                                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, OrbitSpacing.lg)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let contact = group.contacts.first {
                                            selectedContact = contact
                                            contactToView = contact
                                        }
                                    }
                                }
                            }
                        }
                    }
        .padding(.top, OrbitSpacing.md)
        .padding(.bottom, OrbitSpacing.xxxl)
    }
}

// MARK: - Add Members Sheet

struct AddMembersSheet: View {
    @Environment(\.modelContext) private var modelContext
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
        return available.filter { $0.searchableName.contains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableContacts.isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "Everyone's Here",
                        systemImage: "person.2.fill",
                        description: Text("All your active contacts are already in this constellation.")
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
        for contact in contactsToAdd {
            if !(constellation.contacts?.contains(where: { $0.id == contact.id }) ?? false) {
                if constellation.contacts == nil {
                    constellation.contacts = []
                }
                constellation.contacts?.append(contact)
                contact.modifiedAt = Date()
            }
        }
        try? modelContext.save()
    }
}
