import SwiftUI
import SwiftData

// MARK: - ReviewDashboardView
// The reflective maintenance view. Surfaces three categories:
//
// 1. Upcoming dates — birthdays and anniversaries parsed from artifact keys
// 2. Drifting contacts — those whose last contact exceeds their orbit's cadence threshold
// 3. Recently active — positive reinforcement of maintained relationships
//
// This is a "pull" mechanism: the user opens it when ready to reflect.
// No push notifications, no guilt. Just information presented clearly.

struct ReviewDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Contact> { !$0.isArchived },
        sort: [SortDescriptor(\Contact.name)]
    )
    private var contacts: [Contact]

    @State private var selectedSection: ReviewSection = .needsAttention

    enum ReviewSection: String, CaseIterable, Identifiable {
        case needsAttention = "Needs Attention"
        case upcomingDates = "Upcoming Dates"
        case recentlyActive = "Recently Active"
        case neglected = "Neglected"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .needsAttention: return "exclamationmark.circle"
            case .upcomingDates: return "calendar"
            case .recentlyActive: return "checkmark.circle"
            case .neglected: return "moon.zzz"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(ReviewSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(OrbitSpacing.md)

            // Content
            switch selectedSection {
            case .needsAttention:
                needsAttentionList
            case .upcomingDates:
                upcomingDatesList
            case .recentlyActive:
                recentlyActiveList
            case .neglected:
                neglectedList
            }
        }
        .navigationTitle("Review")
    }

    // MARK: - Needs Attention
    // Contacts whose actual cadence has fallen below what their orbit zone expects.

    private var needsAttentionList: some View {
        let drifting = contacts.filter { contact in
            guard let days = contact.daysSinceLastContact else {
                // Never contacted — always needs attention unless Deep Space
                return contact.targetOrbit < 4
            }
            return days > cadenceThreshold(for: contact.targetOrbit)
        }
        .sorted { priorityScore(for: $0) > priorityScore(for: $1) }

        return Group {
            if drifting.isEmpty {
                ContentUnavailableView(
                    "All Clear",
                    systemImage: "checkmark.circle",
                    description: Text("All contacts are within their expected cadence.")
                )
            } else {
                List {
                    ForEach(drifting) { contact in
                        DriftingContactRow(contact: contact)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Upcoming Dates
    // Birthdays and anniversaries parsed from artifact keys containing date-like values.

    private var upcomingDatesList: some View {
        let upcomingItems = findUpcomingDates()

        return Group {
            if upcomingItems.isEmpty {
                ContentUnavailableView(
                    "No Upcoming Dates",
                    systemImage: "calendar",
                    description: Text("Add birthday or anniversary artifacts to contacts to see upcoming dates here.")
                )
            } else {
                List {
                    ForEach(upcomingItems) { item in
                        UpcomingDateRow(item: item)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Recently Active

    private var recentlyActiveList: some View {
        let active = contacts.filter { contact in
            guard let days = contact.daysSinceLastContact else { return false }
            return days <= 14
        }
        .sorted { ($0.lastContactDate ?? .distantPast) > ($1.lastContactDate ?? .distantPast) }

        return Group {
            if active.isEmpty {
                ContentUnavailableView(
                    "No Recent Activity",
                    systemImage: "clock",
                    description: Text("Contacts you've interacted with in the last 2 weeks will appear here.")
                )
            } else {
                List {
                    ForEach(active) { contact in
                        HStack {
                            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                                Text(contact.name)
                                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))

                                if let date = contact.lastContactDate {
                                    Text("Last contact: \(date.relativeDescription)")
                                        .font(OrbitTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Neglected
    // Contacts with no interactions logged at all — the "cold start" problem.

    private var neglectedList: some View {
        let neverContacted = contacts.filter { $0.lastContactDate == nil && $0.targetOrbit < 4 }

        return Group {
            if neverContacted.isEmpty {
                ContentUnavailableView(
                    "No Neglected Contacts",
                    systemImage: "star.circle",
                    description: Text("All contacts have at least one logged interaction.")
                )
            } else {
                List {
                    Section {
                        ForEach(neverContacted) { contact in
                            HStack {
                                Text(contact.name)
                                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                                    .opacity(0.4)
                                Spacer()
                                Text(contact.orbitZoneName)
                                    .font(OrbitTypography.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } footer: {
                        Text("These contacts have been added but have no logged interactions yet. Consider reaching out or adjusting their orbit zone.")
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Cadence Thresholds
    // Expected maximum days between interactions per orbit zone.
    // These are guidelines, not rigid rules. Phase 3 will make these
    // dynamic based on individual gravity scores.

    private func cadenceThreshold(for orbit: Int) -> Int {
        switch orbit {
        case 0: return 7     // Inner Circle: weekly
        case 1: return 30    // Near Orbit: monthly
        case 2: return 90    // Mid Orbit: quarterly
        case 3: return 365   // Outer Orbit: yearly
        case 4: return Int.max // Deep Space: no threshold
        default: return 90
        }
    }

    /// Priority score for sorting drifting contacts.
    /// Higher = more urgent. Inner circle contacts that are overdue
    /// rank higher than outer orbit contacts that are overdue.
    private func priorityScore(for contact: Contact) -> Double {
        let threshold = Double(cadenceThreshold(for: contact.targetOrbit))
        let days = Double(contact.daysSinceLastContact ?? 999)
        let orbitWeight = Double(5 - contact.targetOrbit) // Inner = 5, Outer = 1

        // How far past the threshold, weighted by orbit importance
        return max(0, (days - threshold) / threshold) * orbitWeight
    }

    // MARK: - Date Parsing

    private func findUpcomingDates() -> [UpcomingDateItem] {
        var items: [UpcomingDateItem] = []
        let calendar = Calendar.current
        let today = Date()

        for contact in contacts {
            for artifact in contact.artifacts where artifact.isDateType {
                if let nextDate = parseAndProjectDate(artifact.value, from: today) {
                    let daysUntil = calendar.dateComponents([.day], from: today, to: nextDate).day ?? 999

                    // Show dates within the next 60 days
                    if daysUntil >= 0 && daysUntil <= 60 {
                        items.append(UpcomingDateItem(
                            contact: contact,
                            key: artifact.key,
                            date: nextDate,
                            daysUntil: daysUntil
                        ))
                    }
                }
            }
        }

        return items.sorted { $0.daysUntil < $1.daysUntil }
    }

    /// Parse date strings like "03/05", "March 5", "1990-03-05" and project to next occurrence
    private func parseAndProjectDate(_ value: String, from reference: Date) -> Date? {
        let calendar = Calendar.current

        // Try MM/DD format
        let slashParts = value.split(separator: "/")
        if slashParts.count >= 2,
           let month = Int(slashParts[0]),
           let day = Int(slashParts[1]),
           (1...12).contains(month),
           (1...31).contains(day) {
            return nextOccurrence(month: month, day: day, from: reference)
        }

        // Try ISO format (YYYY-MM-DD)
        let dashParts = value.split(separator: "-")
        if dashParts.count == 3,
           let month = Int(dashParts[1]),
           let day = Int(dashParts[2]) {
            return nextOccurrence(month: month, day: day, from: reference)
        }

        // Try month name formats ("March 5", "Mar 5")
        let dateFormatter = DateFormatter()
        for format in ["MMMM d", "MMM d", "MMMM dd", "MMM dd", "d MMMM", "d MMM"] {
            dateFormatter.dateFormat = format
            if let parsed = dateFormatter.date(from: value) {
                let components = calendar.dateComponents([.month, .day], from: parsed)
                if let month = components.month, let day = components.day {
                    return nextOccurrence(month: month, day: day, from: reference)
                }
            }
        }

        return nil
    }

    /// Find the next occurrence of a month/day after the reference date
    private func nextOccurrence(month: Int, day: Int, from reference: Date) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: reference)

        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year

        if let thisYear = calendar.date(from: components), thisYear >= reference {
            return thisYear
        }

        components.year = year + 1
        return calendar.date(from: components)
    }
}

// MARK: - Supporting Types

struct UpcomingDateItem: Identifiable {
    let id = UUID()
    let contact: Contact
    let key: String
    let date: Date
    let daysUntil: Int
}

// MARK: - Drifting Contact Row

struct DriftingContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: OrbitSpacing.md) {
            // Drift indicator
            Circle()
                .fill(driftColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))

                HStack(spacing: OrbitSpacing.sm) {
                    Text(contact.orbitZoneName)
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    if let days = contact.daysSinceLastContact {
                        Text("\(days)d since last contact")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(driftColor)
                    } else {
                        Text("Never contacted")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
        }
    }

    private var driftColor: Color {
        guard let days = contact.daysSinceLastContact else { return .orange }

        // How far past the threshold
        let threshold: Int
        switch contact.targetOrbit {
        case 0: threshold = 7
        case 1: threshold = 30
        case 2: threshold = 90
        case 3: threshold = 365
        default: threshold = 90
        }

        let ratio = Double(days) / Double(threshold)
        if ratio > 3.0 { return .red }
        if ratio > 2.0 { return .orange }
        return .yellow
    }
}

// MARK: - Upcoming Date Row

struct UpcomingDateRow: View {
    let item: UpcomingDateItem

    var body: some View {
            #if os(iOS)
            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                HStack {
                    Text(item.contact.name).font(OrbitTypography.bodyMedium)
                    Spacer()
                    Text(daysUntilText).font(OrbitTypography.captionMedium).foregroundStyle(urgencyColor)
                }
                HStack {
                    Text(item.key.capitalized).font(OrbitTypography.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            #else
            // Keep the existing HStack implementation for macOS
            #endif
        }

    private var daysUntilText: String {
        switch item.daysUntil {
        case 0: return "Today!"
        case 1: return "Tomorrow"
        case 2...7: return "In \(item.daysUntil) days"
        default: return "In \(item.daysUntil / 7) weeks"
        }
    }

    private var urgencyColor: Color {
        switch item.daysUntil {
        case 0: return .red
        case 1...3: return .orange
        case 4...7: return .yellow
        default: return .secondary
        }
    }
}
