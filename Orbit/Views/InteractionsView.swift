//
//  InteractionsView.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 27/2/26.
//


import SwiftUI
import SwiftData

// MARK: - InteractionsView
// A global, chronological ledger of all interactions across all contacts.
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
        Group {
            if allInteractions.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "text.bubble",
                    description: Text("Interactions logged from the Command Palette or Contact pages will appear here chronologically.")
                )
            } else if filteredInteractions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(groupedInteractions, id: \.key) { group in
                        Section {
                            ForEach(group.interactions) { interaction in
                                GlobalInteractionRowView(interaction: interaction)
                                    .contentShape(Rectangle())
                                    // Tapping navigates to the associated contact
                                    .onTapGesture {
                                        editingInteraction = interaction
                                        }
                                    // Swipe actions for quick management
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) {
                                            interaction.isDeleted = true
                                            interaction.contact?.refreshLastContactDate()
                                            try? modelContext.save()
                                        }
                                        .tint(.blue)
                                    }
                            }
                        } header: {
                            Text(group.key)
                                .font(OrbitTypography.captionMedium)
                                .textCase(.uppercase)
                                .tracking(1.5)
                        }
                    }
                }
                .listStyle(.sidebar) // Matches the clean, edge-to-edge look of PeopleView
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $searchText, prompt: "Search actions, notes, tags, or names")
        .sheet(item: $editingInteraction) { interaction in
            InteractionEditSheet(interaction: interaction)
        }
    }
}

// MARK: - Global Interaction Row View
// Similar to InteractionRowView, but explicitly shows the Contact's name.

struct GlobalInteractionRowView: View {
    let interaction: Interaction

    var body: some View {
        HStack(alignment: .top, spacing: OrbitSpacing.md) {
            // Date Column
            Text(interaction.date.formatted(date: .abbreviated, time: .omitted))
                .font(OrbitTypography.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)

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

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, OrbitSpacing.xs)
    }
}
