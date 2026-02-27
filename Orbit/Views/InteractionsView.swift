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

    // Selection State
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

    private var groupedInteractions: [(key: String, interactions: [Interaction])] {
        let grouped = Dictionary(grouping: filteredInteractions) { interaction in
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
                ForEach(groupedInteractions, id: \.key) { group in
                    // Section Header
                    HStack {
                        Text(group.key)
                            .font(OrbitTypography.captionMedium)
                            .textCase(.uppercase)
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, OrbitSpacing.lg)
                    .padding(.top, OrbitSpacing.lg)
                    .padding(.bottom, OrbitSpacing.xs)

                    ForEach(group.interactions) { interaction in
                        interactionRow(interaction)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: InteractionRowFramePreferenceKey.self,
                                        value: [InteractionRowFrameData(
                                            id: interaction.id,
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
                        if dragSelectionState == nil {
                            dragSelectionState = !selectedInteractions.contains(row.id)
                        }

                        if dragSelectionState == true {
                            selectedInteractions.insert(row.id)
                        } else {
                            selectedInteractions.remove(row.id)
                        }
                    }
                }
                .onEnded { _ in
                    isScrubbing = false
                    dragSelectionState = nil
                }
        )
    }

    // MARK: - Interaction Row

    private func interactionRow(_ interaction: Interaction) -> some View {
        let isSelected = selectedInteractions.contains(interaction.id)

        return HStack(alignment: .top, spacing: OrbitSpacing.md) {
            // Checkbox Column
            Button {
                toggleSelection(for: interaction.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .padding(.vertical, OrbitSpacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content Column (tap opens edit sheet)
            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                // Action & Contact
                HStack(spacing: OrbitSpacing.xs) {
                    Text(interaction.impulse)
                        .font(OrbitTypography.bodyMedium)
                        .foregroundStyle(OrbitColors.syntaxImpulse)

                    if let contactName = interaction.contact?.name {
                        Text("with")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.tertiary)
                        Text(contactName)
                            .font(OrbitTypography.bodyMedium)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text(interaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                }

                // Note Content
                if !interaction.content.isEmpty {
                    Text(interaction.content)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Tags
                if !interaction.tagNames.isEmpty {
                    Text(interaction.tagList.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(OrbitColors.syntaxTag)
                }
            }
            .padding(.vertical, OrbitSpacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                editingInteraction = interaction
            }
        }
        .padding(.horizontal, OrbitSpacing.md)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
    }

    private func toggleSelection(for id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedInteractions.contains(id) {
                selectedInteractions.remove(id)
            } else {
                selectedInteractions.insert(id)
            }
        }
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

        // Handle delete (overrides everything else)
        if edit.deleteAll {
            for interaction in targets {
                interaction.isDeleted = true
                interaction.contact?.refreshLastContactDate()
            }
            try? modelContext.save()
            withAnimation { selectedInteractions.removeAll() }
            return
        }

        // Add tags
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

            // Ensure tags exist in registry
            for tagName in edit.tagsToAdd {
                ensureTagExists(named: tagName)
            }
        }

        // Remove tags
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
        withAnimation {
            selectedInteractions.removeAll()
        }
    }

    private func ensureTagExists(named name: String) {
        let searchName = name.lowercased()
        let predicate = #Predicate<Tag> { tag in
            tag.searchableName == searchName
        }
        var descriptor = FetchDescriptor<Tag>(predicate: predicate)
        descriptor.fetchLimit = 1

        if (try? modelContext.fetch(descriptor).first) == nil {
            let tag = Tag(name: name)
            modelContext.insert(tag)
        }
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
                addTagsSection
                removeTagsSection
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
            .alert(
                "Delete \(selectedCount) Interaction\(selectedCount == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    edit.deleteAll = true
                    onApply(edit)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    edit.deleteAll = false
                }
            } message: {
                Text("This will soft-delete the selected interactions. They can be permanently purged later from Settings.")
            }
        }
    }

    private var saveButtonLabel: String {
        let count = edit.pendingChangeCount
        if count == 0 { return "Save" }
        return "Save \(count) Change\(count == 1 ? "" : "s")"
    }

    // MARK: - Add Tags Section

    private var addTagsSection: some View {
        Section {
            // Manual entry
            HStack {
                TextField("New tag name", text: $newTagText)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { addTagFromTextField() }

                Button {
                    addTagFromTextField()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.plain)
            }

            // Quick-pick from existing tags
            if !allTags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(allTags.prefix(15)) { tag in
                        let isStaged = edit.tagsToAdd.contains(where: { $0.lowercased() == tag.searchableName })
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isStaged {
                                    edit.tagsToAdd.removeAll { $0.lowercased() == tag.searchableName }
                                } else {
                                    // Also clear from remove list if present
                                    edit.tagsToRemove.removeAll { $0.lowercased() == tag.searchableName }
                                    edit.tagsToAdd.append(tag.name)
                                }
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

            // Show staged additions
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
            Text("Selected tags will be added to all \(selectedCount) interaction\(selectedCount == 1 ? "" : "s"). Duplicates on individual interactions are skipped.")
        }
    }

    // MARK: - Remove Tags Section

    private var removeTagsSection: some View {
        Section {
            if !allTags.isEmpty {
                FlowLayout(spacing: OrbitSpacing.sm) {
                    ForEach(allTags.prefix(15)) { tag in
                        let isStaged = edit.tagsToRemove.contains(where: { $0.lowercased() == tag.searchableName })
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isStaged {
                                    edit.tagsToRemove.removeAll { $0.lowercased() == tag.searchableName }
                                } else {
                                    // Also clear from add list if present
                                    edit.tagsToAdd.removeAll { $0.lowercased() == tag.searchableName }
                                    edit.tagsToRemove.append(tag.name)
                                }
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

            // Show staged removals
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
