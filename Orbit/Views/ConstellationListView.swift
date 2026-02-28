import SwiftUI
import SwiftData

// MARK: - ConstellationListView

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
                                Button("Edit") {
                                    constellationToEdit = constellation
                                }
                                
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(constellation)
                                    PersistenceHelper.saveWithLogging(modelContext, operation: "delete constellation")
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

// MARK: - Cached Constellation Stats

/// Pre-computed stats for a constellation row, avoiding repeated traversal.
private struct ConstellationStats {
    let memberCount: Int
    let driftingCount: Int
    let lastActivity: Date?
    let topTags: [String]

    init(constellation: Constellation) {
        let members = (constellation.contacts ?? []).filter { !$0.isArchived }
        self.memberCount = members.count
        self.driftingCount = members.filter { $0.isDrifting }.count
        self.lastActivity = members.compactMap { $0.lastContactDate }.max()

        // Compute top tags using cached summaries instead of traversing interactions.
        // Each contact's cachedTagSummary is a comma-separated string of top tags,
        // already computed by refreshCachedFields(). We aggregate those.
        var tagCounts: [String: Int] = [:]
        for contact in members {
            let tags = contact.cachedTagSummary.split(separator: ",")
            for tag in tags {
                let name = tag.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    tagCounts[name, default: 0] += 1
                }
            }
        }
        self.topTags = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)
    }
}

// MARK: - Constellation Row

struct ConstellationRowView: View {
    let constellation: Constellation

    // FIX P1-1.3: Cache stats on appear instead of recomputing per render
    @State private var stats: ConstellationStats?

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            HStack {
                Text("✦ \(constellation.name)")
                    .font(OrbitTypography.bodyMedium)

                Spacer()

                Text("\(stats?.memberCount ?? 0)")
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(.secondary)
                Image(systemName: "person.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let stats {
                HStack(spacing: OrbitSpacing.md) {
                    if stats.driftingCount > 0 {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 5, height: 5)
                            Text("\(stats.driftingCount) drifting")
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let lastDate = stats.lastActivity {
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

                if !stats.topTags.isEmpty {
                    Text(stats.topTags.map { "#\($0)" }.joined(separator: " "))
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(OrbitColors.syntaxTag.opacity(0.7))
                }
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
        .onAppear {
            stats = ConstellationStats(constellation: constellation)
        }
        .onChange(of: constellation.contacts?.count) { _, _ in
            stats = ConstellationStats(constellation: constellation)
        }
    }
}
