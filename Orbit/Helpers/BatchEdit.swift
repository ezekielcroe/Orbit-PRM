//
//  BatchEdit.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 28/2/26.
//


import SwiftUI
import SwiftData

// MARK: - Batch Edit Model

/// Accumulates all staged changes before a single commit.
struct BatchEdit {
    var orbitZone: Int?                             // nil = no change
    var archiveStatus: ArchiveIntent = .noChange
    var constellationsToAdd: Set<UUID> = []
    var constellationsToRemove: Set<UUID> = []
    var deleteAll: Bool = false

    enum ArchiveIntent: Equatable {
        case noChange
        case archive
        case unarchive
    }

    /// How many discrete changes are staged.
    var pendingChangeCount: Int {
        var count = 0
        if orbitZone != nil { count += 1 }
        if archiveStatus != .noChange { count += 1 }
        count += constellationsToAdd.count
        count += constellationsToRemove.count
        if deleteAll { count += 1 }
        return count
    }

    var hasPendingChanges: Bool { pendingChangeCount > 0 }
}

// MARK: - Batch Action Sheet

struct BatchActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Constellation.name) private var constellations: [Constellation]

    let selectedCount: Int
    let onApply: (BatchEdit) -> Void

    @State private var edit = BatchEdit()
    @State private var showConstellationPicker = false
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                orbitSection
                constellationSection
                archiveSection
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
            .sheet(isPresented: $showConstellationPicker) {
                ConstellationBatchPicker(
                    constellationsToAdd: $edit.constellationsToAdd,
                    constellationsToRemove: $edit.constellationsToRemove
                )
            }
            .alert("Delete \(selectedCount) Contact\(selectedCount == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    edit.deleteAll = true
                    onApply(edit)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    edit.deleteAll = false
                }
            } message: {
                Text("This will permanently delete the selected contacts and all their interactions, artifacts, and constellation memberships. This cannot be undone.")
            }
        }
    }

    private var saveButtonLabel: String {
        let count = edit.pendingChangeCount
        if count == 0 { return "Save" }
        return "Save \(count) Change\(count == 1 ? "" : "s")"
    }

    // MARK: - Orbit Section

    private var orbitSection: some View {
        Section {
            ForEach(OrbitZone.allZones, id: \.id) { zone in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        edit.orbitZone = (edit.orbitZone == zone.id) ? nil : zone.id
                    }
                } label: {
                    HStack(spacing: OrbitSpacing.md) {
                        Image(systemName: edit.orbitZone == zone.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(edit.orbitZone == zone.id ? Color.accentColor : .secondary)
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.name)
                                .font(OrbitTypography.bodyMedium)
                                .foregroundStyle(.primary)
                            Text(zone.description)
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Orbit Zone")
        } footer: {
            if edit.orbitZone != nil {
                Text("Will move all selected contacts to \(OrbitZone.name(for: edit.orbitZone!)).")
                    .font(OrbitTypography.footnote)
            }
        }
    }

    // MARK: - Constellation Section

    private var constellationSection: some View {
        Section {
            Button {
                showConstellationPicker = true
            } label: {
                HStack {
                    Label("Edit Constellations", systemImage: "star.circle")
                        .foregroundStyle(.primary)
                    Spacer()
                    let totalChanges = edit.constellationsToAdd.count + edit.constellationsToRemove.count
                    if totalChanges > 0 {
                        Text("\(totalChanges) change\(totalChanges == 1 ? "" : "s")")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Show staged changes inline
            if !edit.constellationsToAdd.isEmpty {
                let names = constellations.filter { edit.constellationsToAdd.contains($0.id) }.map(\.name)
                ForEach(names, id: \.self) { name in
                    HStack(spacing: OrbitSpacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Add to ✦ \(name)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !edit.constellationsToRemove.isEmpty {
                let names = constellations.filter { edit.constellationsToRemove.contains($0.id) }.map(\.name)
                ForEach(names, id: \.self) { name in
                    HStack(spacing: OrbitSpacing.sm) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("Remove from ✦ \(name)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Constellations")
        }
    }

    // MARK: - Archive Section

    private var archiveSection: some View {
        Section {
            ForEach([
                (BatchEdit.ArchiveIntent.noChange, "No Change", "minus.circle", Color.secondary),
                (BatchEdit.ArchiveIntent.archive, "Archive", "archivebox", Color.orange),
                (BatchEdit.ArchiveIntent.unarchive, "Unarchive", "arrow.uturn.backward", Color.blue)
            ], id: \.1) { intent, label, icon, tint in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        edit.archiveStatus = intent
                    }
                } label: {
                    HStack(spacing: OrbitSpacing.md) {
                        Image(systemName: edit.archiveStatus == intent ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(edit.archiveStatus == intent ? tint : .secondary)
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))

                        Label(label, systemImage: icon)
                            .font(OrbitTypography.bodyMedium)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Archive Status")
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Label("Delete \(selectedCount) Contact\(selectedCount == 1 ? "" : "s")", systemImage: "trash")
                    Spacer()
                }
            }
        } footer: {
            Text("Permanently removes the selected contacts and all associated data.")
                .font(OrbitTypography.footnote)
        }
    }
}

// MARK: - Constellation Batch Picker

/// Intent for each constellation in the batch picker.
private enum ConstellationIntent {
    case noChange, add, remove
}

/// A sub-sheet that lets users toggle add/remove per constellation.
struct ConstellationBatchPicker: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Constellation.name) private var constellations: [Constellation]

    @Binding var constellationsToAdd: Set<UUID>
    @Binding var constellationsToRemove: Set<UUID>

    var body: some View {
        NavigationStack {
            Group {
                if constellations.isEmpty {
                    ContentUnavailableView(
                        "No Constellations",
                        systemImage: "star.circle",
                        description: Text("Create constellations first to manage group membership here.")
                    )
                } else {
                    List {
                        ForEach(constellations) { constellation in
                            ConstellationBatchRow(
                                constellation: constellation,
                                intent: intentFor(constellation),
                                onCycle: { cycleIntent(for: constellation) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Edit Constellations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Intent Logic

    private func intentFor(_ constellation: Constellation) -> ConstellationIntent {
        if constellationsToAdd.contains(constellation.id) { return .add }
        if constellationsToRemove.contains(constellation.id) { return .remove }
        return .noChange
    }

    /// Cycles: noChange → add → remove → noChange
    private func cycleIntent(for constellation: Constellation) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch intentFor(constellation) {
            case .noChange:
                constellationsToAdd.insert(constellation.id)
                constellationsToRemove.remove(constellation.id)
            case .add:
                constellationsToAdd.remove(constellation.id)
                constellationsToRemove.insert(constellation.id)
            case .remove:
                constellationsToAdd.remove(constellation.id)
                constellationsToRemove.remove(constellation.id)
            }
        }
    }
}

// MARK: - Constellation Batch Row

private struct ConstellationBatchRow: View {
    let constellation: Constellation
    let intent: ConstellationIntent
    let onCycle: () -> Void

    private var stateIcon: String {
        switch intent {
        case .noChange: return "circle"
        case .add: return "plus.circle.fill"
        case .remove: return "minus.circle.fill"
        }
    }

    private var stateColor: Color {
        switch intent {
        case .noChange: return .secondary
        case .add: return .green
        case .remove: return .red
        }
    }

    private var stateLabel: String {
        switch intent {
        case .noChange: return ""
        case .add: return "Add"
        case .remove: return "Remove"
        }
    }

    var body: some View {
        Button {
            onCycle()
        } label: {
            HStack(spacing: OrbitSpacing.md) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("✦ \(constellation.name)")
                        .font(OrbitTypography.bodyMedium)
                        .foregroundStyle(.primary)

                    let memberCount = (constellation.contacts ?? []).filter { !$0.isArchived }.count
                    Text("\(memberCount) member\(memberCount == 1 ? "" : "s")")
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !stateLabel.isEmpty {
                    Text(stateLabel)
                        .font(OrbitTypography.captionMedium)
                        .foregroundStyle(stateColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}