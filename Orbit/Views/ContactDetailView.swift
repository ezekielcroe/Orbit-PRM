import SwiftUI
import SwiftData

// MARK: - ContactDetailView (Phase 2)
// Updates from Phase 1:
// - Lazy-loaded interaction timeline (performance for contacts with many logs)
// - Spotlight re-indexing on interaction log
// - Inline artifact value editing on long-press (bypasses command palette)
// - Interaction grouping by month for easier scanning
// - Quick-action buttons for common operations

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer
    @Bindable var contact: Contact

    @State private var showEditForm = false
    @State private var showAddArtifact = false
    @State private var showAddInteraction = false
    @State private var editingArtifact: Artifact?
    @State private var interactionLimit = 20 // Lazy loading

    private var activeInteractions: [Interaction] {
        contact.interactions
            .filter { !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }

    /// Group interactions by month for visual clarity
    private var groupedInteractions: [(key: String, interactions: [Interaction])] {
        let limited = Array(activeInteractions.prefix(interactionLimit))

        let grouped = Dictionary(grouping: limited) { interaction in
            interaction.date.formatted(.dateTime.year().month(.wide))
        }

        return grouped
            .map { (key: $0.key, interactions: $0.value) }
            .sorted { a, b in
                // Sort groups by the most recent interaction date in each group
                let aDate = a.interactions.first?.date ?? .distantPast
                let bDate = b.interactions.first?.date ?? .distantPast
                return aDate > bDate
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                headerSection
                quickActionsBar
                Divider()
                artifactSection
                Divider()
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
    // One-tap buttons for common operations without opening the command palette.

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

    // MARK: - Artifacts

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
                ForEach(contact.artifacts.sorted(by: { $0.key < $1.key })) { artifact in
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
    }

    // MARK: - Interactions (Grouped + Lazy)

    private var interactionSection: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            HStack {
                Text("INTERACTIONS")
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

            if activeInteractions.isEmpty {
                Text("No interactions logged yet.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(groupedInteractions, id: \.key) { group in
                    VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                        // Month header
                        Text(group.key)
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(1)
                            .padding(.top, OrbitSpacing.sm)

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

                // Load more button for lazy loading
                if activeInteractions.count > interactionLimit {
                    Button {
                        interactionLimit += 20
                    } label: {
                        Text("Show more (\(activeInteractions.count - interactionLimit) remaining)")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, OrbitSpacing.sm)
                }
            }
        }
    }
}
