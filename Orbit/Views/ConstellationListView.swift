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
