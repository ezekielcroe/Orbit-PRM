import SwiftUI
import SwiftData

// MARK: - DashboardView (Phase 2)
// Updates from Phase 1:
// - Summary stats bar at top (total contacts, needing attention count)
// - Drift indicator dots on contacts exceeding cadence threshold
// - "Review needed" prompt when drifting contacts exceed a threshold

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedContact: Contact?
    @Binding var showCommandPalette: Bool

    @Query(
        filter: #Predicate<Contact> { !$0.isArchived },
        sort: [SortDescriptor(\Contact.targetOrbit), SortDescriptor(\Contact.name)]
    )
    private var contacts: [Contact]

    /// Count of contacts drifting beyond their expected cadence
    private var driftingCount: Int {
        contacts.filter { isDrifting($0) }.count
    }

    var body: some View {
        Group {
            if contacts.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    summaryBar
                    contactsByOrbit
                }
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showCommandPalette = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("Quick Log (⌘K)")
            }
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: OrbitSpacing.lg) {
            summaryItem(count: contacts.count, label: "Contacts", icon: "person.2")

            summaryItem(
                count: contacts.filter { ($0.daysSinceLastContact ?? 999) <= 7 }.count,
                label: "Active (7d)",
                icon: "checkmark.circle"
            )

            if driftingCount > 0 {
                summaryItem(count: driftingCount, label: "Need attention", icon: "exclamationmark.circle", color: .orange)
            }

            Spacer()
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm)
    }

    private func summaryItem(count: Int, label: String, icon: String, color: Color = .secondary) -> some View {
        HStack(spacing: OrbitSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text("\(count)")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(color)

            Text(label)
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Contacts Yet", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Add your first contact to begin mapping your universe.")
        } actions: {
            Button("Open Command Palette") {
                showCommandPalette = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Contacts by Orbit Zone

    private var contactsByOrbit: some View {
        List(selection: $selectedContact) {
            ForEach(OrbitZone.allZones, id: \.id) { zone in
                let zoneContacts = contacts.filter { $0.targetOrbit == zone.id }

                if !zoneContacts.isEmpty {
                    Section {
                        ForEach(zoneContacts) { contact in
                            DashboardContactRow(
                                contact: contact,
                                isDrifting: isDrifting(contact)
                            )
                            .tag(contact)
                            // Right-swipe to quick-log (spec: "Right Swipe pre-fills input")
                            .swipeActions(edge: .leading) {
                                Button {
                                    selectedContact = contact
                                    showCommandPalette = true
                                } label: {
                                    Label("Log", systemImage: "plus.bubble")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        HStack(spacing: OrbitSpacing.sm) {
                            Text(zone.name)
                                .font(OrbitTypography.captionMedium)
                                .textCase(.uppercase)
                                .tracking(1.5)

                            Spacer()

                            Text("\(zoneContacts.count)")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Drift Detection

    /// Check if a contact has exceeded the cadence threshold for their orbit zone
    private func isDrifting(_ contact: Contact) -> Bool {
        guard let days = contact.daysSinceLastContact else {
            return contact.targetOrbit < 4 // Never contacted and not Deep Space
        }

        let threshold: Int
        switch contact.targetOrbit {
        case 0: threshold = 7
        case 1: threshold = 30
        case 2: threshold = 90
        case 3: threshold = 365
        default: return false
        }

        return days > threshold
    }
}

// MARK: - Dashboard Contact Row
// Enhanced from Phase 1 with drift indicator

struct DashboardContactRow: View {
    let contact: Contact
    let isDrifting: Bool

    var body: some View {
        HStack(spacing: OrbitSpacing.md) {
            // Drift indicator dot
            if isDrifting {
                Circle()
                    .fill(driftColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                if let days = contact.daysSinceLastContact {
                    Text(recencyDescription(days: days))
                        .font(OrbitTypography.caption)
                        .foregroundStyle(isDrifting ? driftColor : .secondary)
                } else {
                    Text("No interactions logged")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Tags
            if !contact.tags.isEmpty {
                Text(contact.tags.prefix(2).map(\.name).joined(separator: ", "))
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, OrbitSpacing.xs)
    }

    private var driftColor: Color {
        guard let days = contact.daysSinceLastContact else { return .orange }

        let threshold: Int
        switch contact.targetOrbit {
        case 0: threshold = 7
        case 1: threshold = 30
        case 2: threshold = 90
        case 3: threshold = 365
        default: return .secondary
        }

        let ratio = Double(days) / Double(threshold)
        if ratio > 3.0 { return .red }
        if ratio > 1.5 { return .orange }
        return .yellow
    }

    private func recencyDescription(days: Int) -> String {
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        case 7...13: return "Last week"
        case 14...29: return "\(days / 7) weeks ago"
        case 30...59: return "Last month"
        case 60...364: return "\(days / 30) months ago"
        default: return "Over a year ago"
        }
    }
}
