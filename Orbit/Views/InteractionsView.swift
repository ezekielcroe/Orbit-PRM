//
//  InteractionsView.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 27/2/26.
//

import SwiftUI
import SwiftData

// MARK: - Row Geometry Tracking for Drag-to-Select (Interactions)
// Uses distinct types to avoid collision with PeopleView's RowFrameData.

struct InteractionRowFrameData: Equatable {
    let id: UUID
    let frame: CGRect
}

struct InteractionRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [InteractionRowFrameData] = []
    static func reduce(value: inout [InteractionRowFrameData], nextValue: () -> [InteractionRowFrameData]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - InteractionsView
// A global, chronological ledger of all interactions across all contacts.
// Supports scrub-to-select for batch tag editing and deletion.
// Interactions sharing a batchID (constellation logs) are grouped into
// a single row showing "Coffee with 4 contacts" instead of 4 identical rows.

struct InteractionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedContact: Contact?

    @Query(
        filter: #Predicate<Interaction> { !$0.isDeleted },
        sort: \Interaction.date,
        order: .reverse
    )
    private var allInteractions: [Interaction]

    @State private var searchText = ""
    @State private var editingInteraction: Interaction?

    // Selection State — tracks individual interaction IDs even when displayed as groups
    @State private var selectedInteractions: Set<UUID> = []
    @State private var showBatchEdit = false

    // Drag-to-select State
    @State private var rowFrames: [InteractionRowFrameData] = []
    @State private var dragSelectionState: Bool? = nil
    @State private var isScrubbing = false

    // MARK: - Computed Data

    private var filteredInteractions: [Interaction] {
        if searchText.isEmpty { return allInteractions }
        let query = searchText.lowercased()
        return allInteractions.filter { interaction in
            interaction.impulse.lowercased().contains(query) ||
            interaction.content.lowercased().contains(query) ||
            interaction.tagNames.lowercased().contains(query) ||
            (interaction.contact?.name.lowercased().contains(query) ?? false)
        }
    }

    /// Group filtered interactions by month, then collapse batch interactions within each month.
    private var groupedInteractions: [(key: String, groups: [InteractionGroup])] {
        let byMonth = Dictionary(grouping: filteredInteractions) { interaction in
            interaction.date.formatted(.dateTime.year().month(.wide))
        }
        return byMonth
            .map { (key: $0.key, groups: InteractionGroup.group($0.value)) }
            .sorted { a, b in
                let aDate = a.groups.first?.date ?? .distantPast
                let bDate = b.groups.first?.date ?? .distantPast
                return aDate > bDate
            }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            if allInteractions.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "text.bubble",
                    description: Text("Interactions logged from the Command Palette or Contact pages will appear here chronologically.")
                )
                .frame(maxHeight: .infinity)
            } else if filteredInteractions.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                interactionList
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $searchText, prompt: "Search actions, notes, tags, or names")
        .overlay(alignment: .bottom) {
            if !selectedInteractions.isEmpty {
                floatingActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, OrbitSpacing.xl)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedInteractions.isEmpty)
        .sheet(item: $editingInteraction) { interaction in
            InteractionEditSheet(interaction: interaction)
        }
        .sheet(isPresented: $showBatchEdit) {
            InteractionBatchEditSheet(
                selectedCount: selectedInteractions.count,
                onApply: { edit in
                    applyBatchEdit(edit)
                    showBatchEdit = false
                }
            )
        }
    }

    // MARK: - Interaction List (ScrollView for scrub support)

    private var interactionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedInteractions, id: \.key) { monthGroup in
                    // Section Header
                    HStack {
                        Text(monthGroup.key)
                            .font(OrbitTypography.captionMedium)
                            .textCase(.uppercase)
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, OrbitSpacing.lg)
                    .padding(.top, OrbitSpacing.lg)
                    .padding(.bottom, OrbitSpacing.xs)

                    ForEach(monthGroup.groups) { group in
                        interactionGroupRow(group)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: InteractionRowFramePreferenceKey.self,
                                        value: [InteractionRowFrameData(
                                            id: group.id,
                                            frame: geo.frame(in: .named("InteractionTableSpace"))
                                        )]
                                    )
                                }
                            )
                        Divider()
                            .padding(.leading, 44)
                    }
                }

                // Bottom spacer for floating bar clearance
                Color.clear
                    .frame(height: 100)
            }
        }
        .scrollDisabled(isScrubbing)
        .coordinateSpace(name: "InteractionTableSpace")
        .onPreferenceChange(InteractionRowFramePreferenceKey.self) { frames in
            self.rowFrames = frames
        }
        // Scrub Selection Gesture
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    // Only activate if drag starts in the checkbox column (left 50pt)
                    guard value.startLocation.x < 50 else { return }

                    if !isScrubbing {
                        isScrubbing = true
                    }

                    if let row = rowFrames.first(where: {
                        $0.frame.minY <= value.location.y && $0.frame.maxY >= value.location.y
                    }) {
                        // row.id is the group ID — find the group to select/deselect all its interactions
                        if let group = findGroup(by: row.id) {
                            if dragSelectionState == nil {
                                dragSelectionState = !group.allIDs.isSubset(of: selectedInteractions)
                            }

                            if dragSelectionState == true {
                                selectedInteractions.formUnion(group.allIDs)
                            } else {
                                selectedInteractions.subtract(group.allIDs)
                            }
                        }
                    }
                }
                .onEnded { _ in
                    isScrubbing = false
                    dragSelectionState = nil
                }
        )
    }

    // MARK: - Group Row (Checkbox + Standardized Content)

    private func interactionGroupRow(_ group: InteractionGroup) -> some View {
        let isSelected = group.allIDs.isSubset(of: selectedInteractions)
        let isPartiallySelected = !isSelected && !group.allIDs.isDisjoint(with: selectedInteractions)

        return HStack(alignment: .top, spacing: OrbitSpacing.md) {
            // Checkbox Column
            Button {
                toggleGroupSelection(group)
            } label: {
                Image(systemName: checkboxIcon(selected: isSelected, partial: isPartiallySelected))
                    .font(.title3)
                    .foregroundStyle(isSelected || isPartiallySelected ? .blue : .secondary)
                    .padding(.vertical, OrbitSpacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Standardized content
            InteractionRowContent(
                group: group,
                showContactNames: true,
                showChevron: false
            )
            .onTapGesture {
                if group.isGroup {
                    // For groups, navigate to the first contact
                    if let contact = group.contacts.first {
                        selectedContact = contact
                    }
                } else {
                    // For single interactions, open the edit sheet
                    editingInteraction = group.representative
                }
            }
        }
        .padding(.horizontal, OrbitSpacing.md)
        .background(isSelected ? Color.blue.opacity(0.05) : (isPartiallySelected ? Color.blue.opacity(0.02) : Color.clear))
    }

    private func checkboxIcon(selected: Bool, partial: Bool) -> String {
        if selected { return "checkmark.square.fill" }
        if partial { return "minus.square.fill" }
        return "square"
    }

    // MARK: - Selection Helpers

    private func toggleGroupSelection(_ group: InteractionGroup) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if group.allIDs.isSubset(of: selectedInteractions) {
                selectedInteractions.subtract(group.allIDs)
            } else {
                selectedInteractions.formUnion(group.allIDs)
            }
        }
    }

    private func findGroup(by id: UUID) -> InteractionGroup? {
        for monthGroup in groupedInteractions {
            if let group = monthGroup.groups.first(where: { $0.id == id }) {
                return group
            }
        }
        return nil
    }

    // MARK: - Floating Action Bar

    private var floatingActionBar: some View {
        HStack(spacing: OrbitSpacing.md) {
            Text("\(selectedInteractions.count) selected")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(.primary)

            Divider()
                .frame(height: 16)

            Button("Select All") {
                selectedInteractions = Set(filteredInteractions.map(\.id))
            }
            .font(OrbitTypography.caption)
            .foregroundStyle(.blue)

            Spacer()

            Button {
                selectedInteractions.removeAll()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                showBatchEdit = true
            } label: {
                Label("Edit", systemImage: "sparkles")
                    .font(OrbitTypography.captionMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
        }
        .padding(.horizontal, OrbitSpacing.lg)
        .padding(.vertical, OrbitSpacing.sm)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    // MARK: - Apply Batch Edit

    private func applyBatchEdit(_ edit: InteractionBatchEdit) {
        let descriptor = FetchDescriptor<Interaction>()
        guard let allFetched = try? modelContext.fetch(descriptor) else { return }

        let targets = allFetched.filter { selectedInteractions.contains($0.id) }

        if edit.deleteAll {
            for interaction in targets {
                interaction.isDeleted = true
                interaction.contact?.refreshCachedFields()
            }
            try? modelContext.save()
            withAnimation { selectedInteractions.removeAll() }
            return
        }

        if !edit.tagsToAdd.isEmpty {
            for interaction in targets {
                let existing = interaction.tagList.map { $0.lowercased() }
                let toAdd = edit.tagsToAdd.filter { !existing.contains($0.lowercased()) }
                if !toAdd.isEmpty {
                    if interaction.tagNames.trimmingCharacters(in: .whitespaces).isEmpty {
                        interaction.tagNames = toAdd.joined(separator: ", ")
                    } else {
                        interaction.tagNames += ", " + toAdd.joined(separator: ", ")
                    }
                    interaction.contact?.modifiedAt = Date()
                }
            }
            TagRegistry.ensureTagsExist(named: edit.tagsToAdd, in: modelContext)
        }

        if !edit.tagsToRemove.isEmpty {
            let removeSet = Set(edit.tagsToRemove.map { $0.lowercased() })
            for interaction in targets {
                let current = interaction.tagList
                let filtered = current.filter { !removeSet.contains($0.lowercased()) }
                interaction.tagNames = filtered.joined(separator: ", ")
                interaction.contact?.modifiedAt = Date()
            }
        }

        try? modelContext.save()
        withAnimation { selectedInteractions.removeAll() }
    }
}

// MARK: - Interaction Batch Edit Model

struct InteractionBatchEdit {
    var tagsToAdd: [String] = []
    var tagsToRemove: [String] = []
    var deleteAll: Bool = false

    var pendingChangeCount: Int {
        var count = 0
        count += tagsToAdd.count
        count += tagsToRemove.count
        if deleteAll { count += 1 }
        return count
    }

    var hasPendingChanges: Bool { pendingChangeCount > 0 }
}

// MARK: - Interaction Batch Edit Sheet

struct InteractionBatchEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Tag.name) private var allTags: [Tag]

    let selectedCount: Int
    let onApply: (InteractionBatchEdit) -> Void

    @State private var edit = InteractionBatchEdit()
    @State private var newTagText = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                addTagSection
                removeTagSection
                deleteSection
            }
            .navigationTitle("\(selectedCount) Selected")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(edit)
                        dismiss()
                    } label: {
                        Text(saveButtonLabel)
                            .fontWeight(.semibold)
                    }
                    .disabled(!edit.hasPendingChanges)
                }
            }
            .alert("Delete \(selectedCount) Interaction\(selectedCount == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    edit.deleteAll = true
                    onApply(edit)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    edit.deleteAll = false
                }
            } message: {
                Text("This will soft-delete the selected interactions. They can be permanently removed from Settings.")
            }
        }
    }

    private var saveButtonLabel: String {
        let count = edit.pendingChangeCount
        if count == 0 { return "Save" }
        return "Save \(count) Change\(count == 1 ? "" : "s")"
    }

    // MARK: - Add Tags Section

    private var addTagSection: some View {
        Section {
            HStack {
                TextField("Add a tag…", text: $newTagText)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { addTagFromTextField() }

                Button("Add") { addTagFromTextField() }
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !allTags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(allTags.prefix(15)) { tag in
                        let isStaged = edit.tagsToAdd.contains(where: { $0.lowercased() == tag.searchableName })
                        Button {
                            if isStaged {
                                edit.tagsToAdd.removeAll { $0.lowercased() == tag.searchableName }
                            } else {
                                edit.tagsToRemove.removeAll { $0.lowercased() == tag.searchableName }
                                edit.tagsToAdd.append(tag.name)
                            }
                        } label: {
                            Text("#\(tag.name)")
                                .font(OrbitTypography.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(isStaged ? .green : .secondary)
                        .controlSize(.small)
                    }
                }
            }

            if !edit.tagsToAdd.isEmpty {
                ForEach(edit.tagsToAdd, id: \.self) { tag in
                    HStack(spacing: OrbitSpacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("#\(tag)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            edit.tagsToAdd.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Add Tags")
        } footer: {
            Text("Selected tags will be added to all \(selectedCount) interaction\(selectedCount == 1 ? "" : "s").")
        }
    }

    // MARK: - Remove Tags Section

    private var removeTagSection: some View {
        Section {
            if !allTags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(allTags.prefix(15)) { tag in
                        let isStaged = edit.tagsToRemove.contains(where: { $0.lowercased() == tag.searchableName })
                        Button {
                            if isStaged {
                                edit.tagsToRemove.removeAll { $0.lowercased() == tag.searchableName }
                            } else {
                                edit.tagsToAdd.removeAll { $0.lowercased() == tag.searchableName }
                                edit.tagsToRemove.append(tag.name)
                            }
                        } label: {
                            Text("#\(tag.name)")
                                .font(OrbitTypography.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(isStaged ? .red : .secondary)
                        .controlSize(.small)
                    }
                }
            } else {
                Text("No tags in the registry yet.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            if !edit.tagsToRemove.isEmpty {
                ForEach(edit.tagsToRemove, id: \.self) { tag in
                    HStack(spacing: OrbitSpacing.sm) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("#\(tag)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            edit.tagsToRemove.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Remove Tags")
        } footer: {
            Text("Selected tags will be stripped from all \(selectedCount) interaction\(selectedCount == 1 ? "" : "s").")
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Label("Delete \(selectedCount) Interaction\(selectedCount == 1 ? "" : "s")", systemImage: "trash")
                    Spacer()
                }
            }
        } footer: {
            Text("Soft-deletes the selected interactions. Use Purge Deleted Logs in Settings to remove them permanently.")
                .font(OrbitTypography.footnote)
        }
    }

    // MARK: - Helpers

    private func addTagFromTextField() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !edit.tagsToAdd.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            edit.tagsToRemove.removeAll { $0.lowercased() == trimmed.lowercased() }
            edit.tagsToAdd.append(trimmed)
        }
        newTagText = ""
    }
}
