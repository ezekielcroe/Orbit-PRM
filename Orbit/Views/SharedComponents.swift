//
//  FlowLayout.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 19/2/26.
//


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
// Displays a single artifact key-value pair.
// Used by ContactDetailView.

struct ArtifactRowView: View {
    let artifact: Artifact

    var body: some View {
        HStack(alignment: .top, spacing: OrbitSpacing.md) {
            Text(artifact.key)
                .font(OrbitTypography.artifactKey)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

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
        }
        .padding(.vertical, OrbitSpacing.xs)
    }
}

// MARK: - InteractionRowView
// Displays a single interaction log entry.
// Used by ContactDetailView.

struct InteractionRowView: View {
    let interaction: Interaction

    var body: some View {
        HStack(alignment: .top, spacing: OrbitSpacing.md) {
            // Date column
            Text(interaction.date.formatted(date: .abbreviated, time: .omitted))
                .font(OrbitTypography.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                // Impulse type
                Text(interaction.impulse)
                    .font(OrbitTypography.bodyMedium)
                    .foregroundStyle(OrbitColors.syntaxImpulse)

                // Note content
                if !interaction.content.isEmpty {
                    Text(interaction.content)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.primary)
                }

                // Tags
                if !interaction.tagNames.isEmpty {
                    Text(interaction.tagList.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(OrbitColors.syntaxTag)
                }
            }

            Spacer()
        }
        .padding(.vertical, OrbitSpacing.xs)
    }
}
