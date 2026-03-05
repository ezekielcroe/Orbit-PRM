//
//  SharedComponents.swift
//  Orbit

import SwiftUI

// MARK: - FlowLayout
// A horizontal wrapping layout for tags, pills, and other inline elements.
// Used by ContactDetailView, ContactFormSheet, ArtifactEditSheet,
// QuickInteractionSheet, and CommandPaletteView.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - ArtifactRowView
// FIX 3: Uses flexible label width with alignment instead of fixed 100pt.
// Long keys no longer truncate.

struct ArtifactRowView: View {
    let artifact: Artifact

    var body: some View {
        HStack(alignment: .top, spacing: OrbitSpacing.md) {
            Text(artifact.key)
                .font(OrbitTypography.artifactKey)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
                .lineLimit(2)

            if artifact.isArray {
                VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                    ForEach(artifact.listValues, id: \.self) { item in
                        Text(item)
                            .font(OrbitTypography.artifactValue)
                    }
                }
            } else {
                Text(artifact.value)
                    .font(OrbitTypography.artifactValue)
            }

            Spacer()

            // FIX 3: Show category badge if explicitly set
            if let category = artifact.category, !category.isEmpty {
                Text(category)
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
    }
}

// MARK: - InteractionGroup
/// Represents one or more interactions that belong to the same real-world event.
/// Interactions with a shared `batchID` (e.g., from a constellation log) are
/// collapsed into a single group. Individually-logged interactions form
/// single-member groups.

struct InteractionGroup: Identifiable {
    let id: UUID
    let interactions: [Interaction]

    /// The first interaction — used for shared fields (impulse, date, content, tags).
    var representative: Interaction { interactions[0] }

    var isGroup: Bool { interactions.count > 1 }
    var date: Date { representative.date }
    var impulse: String { representative.impulse }
    var content: String { representative.content }
    var tagNames: String { representative.tagNames }
    var tagList: [String] { representative.tagList }

    /// Contacts involved in this group, deduplicated by ID and sorted by name.
    var contacts: [Contact] {
        var seen = Set<UUID>()
        return interactions.compactMap { interaction -> Contact? in
            guard let contact = interaction.contact,
                  seen.insert(contact.id).inserted else { return nil }
            return contact
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// All interaction IDs in this group (for batch selection).
    var allIDs: Set<UUID> { Set(interactions.map(\.id)) }

    /// Build groups from a flat list of interactions.
    /// Interactions sharing a batchID are merged. Others become solo groups.
    /// The returned array is sorted by date descending.
    static func group(_ interactions: [Interaction]) -> [InteractionGroup] {
        var batchGroups: [UUID: [Interaction]] = [:]
        var soloInteractions: [Interaction] = []

        for interaction in interactions {
            if let batchID = interaction.batchID {
                batchGroups[batchID, default: []].append(interaction)
            } else {
                soloInteractions.append(interaction)
            }
        }

        var result: [InteractionGroup] = []

        for (batchID, batch) in batchGroups {
            // Sort within each batch by contact name for stable ordering
            let sorted = batch.sorted {
                ($0.contact?.name ?? "").localizedCaseInsensitiveCompare($1.contact?.name ?? "") == .orderedAscending
            }
            result.append(InteractionGroup(id: batchID, interactions: sorted))
        }

        for interaction in soloInteractions {
            result.append(InteractionGroup(id: interaction.id, interactions: [interaction]))
        }

        result.sort { $0.date > $1.date }
        return result
    }
    
    /// Checks if all contacts in this group exactly match a constellation's active members
    var mutualConstellationName: String? {
        guard contacts.count > 1 else { return nil }
        
        // 1. Get the constellations of the first contact
        let firstContactConstellations = contacts[0].constellations ?? []
        guard !firstContactConstellations.isEmpty else { return nil }
        
        // 2. Intersect IDs to find constellations shared by EVERYONE in the group
        var mutualIDs = Set(firstContactConstellations.map(\.id))
        for contact in contacts.dropFirst() {
            let contactConstellationIDs = Set((contact.constellations ?? []).map(\.id))
            mutualIDs.formIntersection(contactConstellationIDs)
        }
        
        // 3. Filter down to the actual shared constellation objects
        let sharedConstellations = firstContactConstellations.filter { mutualIDs.contains($0.id) }
        
        // 4. Find the EXACT match: constellation's active members == group's members
        let groupContactIDs = Set(contacts.map(\.id))
        
        let exactMatch = sharedConstellations.first { constellation in
            // We filter out archived members because group interactions usually ignore them
            let activeMembers = (constellation.contacts ?? []).filter { !$0.isArchived }
            let memberIDs = Set(activeMembers.map(\.id))
            
            return memberIDs == groupContactIDs
        }
        
        return exactMatch?.name
    }
}


// MARK: - InteractionRowContent
/// The standardized interaction row used across all views:
///   - InteractionsView (global activity tab)
///   - ConstellationDetailView (group timeline)
///   - ContactDetailView (individual timeline)
///
/// Adapts to context via configuration:
///   - `showContactNames`: Whether to show "with ContactName" or "with N contacts"
///   - `showChevron`: Whether to show a trailing disclosure indicator
///
/// Selection (checkboxes) and gesture handling are the caller's responsibility;
/// this component renders the content only.

struct InteractionRowContent: View {
    let group: InteractionGroup
    var showContactNames: Bool = true
    var showChevron: Bool = true

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            // Line 1: Impulse + Contact(s) + Date
            HStack(spacing: OrbitSpacing.xs) {
                Text(group.impulse)
                    .font(OrbitTypography.bodyMedium)
                    .foregroundStyle(OrbitColors.syntaxImpulse)

                if showContactNames {
                    contactLabel
                }

                Spacer()

                Text(group.date.formatted(date: .abbreviated, time: .omitted))
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            // Expanded: show individual contact names within the group
            if group.isGroup && isExpanded {
                expandedContactList
            }

            // Note content
            if !group.content.isEmpty {
                Text(group.content)
                    .font(OrbitTypography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Tags
            if !group.tagNames.isEmpty {
                Text(group.tagList.map { "#\($0)" }.joined(separator: " "))
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(OrbitColors.syntaxTag)
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Contact Label

    @ViewBuilder
    private var contactLabel: some View {
        let contacts = group.contacts

        if group.isGroup {
            HStack(spacing: OrbitSpacing.xs) {
                Text("with")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        // NEW LOGIC: Show Constellation name if it exists, otherwise fallback to count
                        if let constellationName = group.mutualConstellationName {
                            Text("✦ \(constellationName)")
                                .font(OrbitTypography.bodyMedium)
                                .foregroundStyle(.purple)
                        } else {
                            Text("\(contacts.count) contacts")
                                .font(OrbitTypography.bodyMedium)
                                .foregroundStyle(.primary)
                        }
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } else if let contact = contacts.first {
            Text("with")
                .font(OrbitTypography.caption)
                .foregroundStyle(.tertiary)
            Text(contact.name)
                .font(OrbitTypography.bodyMedium)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Expanded Contact List

    private var expandedContactList: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            ForEach(group.contacts) { contact in
                HStack(spacing: OrbitSpacing.sm) {
                    Circle()
                        .fill(contact.isDrifting ? contact.driftColor : Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                    Text(contact.name)
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(contact.orbitZoneName)
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.leading, OrbitSpacing.sm)
        .padding(.vertical, OrbitSpacing.xs)
    }
}


// MARK: - Legacy InteractionRowView
/// Thin wrapper around InteractionRowContent for backward compatibility.
/// Call sites that pass a single Interaction can use this without changes.
/// New code should prefer InteractionRowContent with InteractionGroup directly.

struct InteractionRowView: View {
    let interaction: Interaction

    var body: some View {
        InteractionRowContent(
            group: InteractionGroup(id: interaction.id, interactions: [interaction]),
            showContactNames: false,
            showChevron: true
        )
    }
}
