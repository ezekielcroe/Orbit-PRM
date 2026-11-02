//
//  TodayView.swift
//  Orbit
//
//  The home surface: a short list of people to reach out to today, chosen
//  once per day so it doesn't reshuffle while you work through it. Each row
//  says why in plain words and has visible actions — log, snooze, change
//  closeness — instead of hiding them behind a long-press.
//
//  Sections:
//    (card)     set closeness for imported people, when any are unset
//    TODAY      up to five people from AttentionEngine, ticked off as you go
//    MORE       everyone else the engine would suggest, collapsed
//    COMING UP  birthdays and anniversaries in the next two weeks
//    LATEST     the most recent logs
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Binding var selectedContact: Contact?

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    @Query(filter: #Predicate<Interaction> { !$0.isDeleted }, sort: \Interaction.date, order: .reverse)
    private var allInteractions: [Interaction]

    @AppStorage("today.picks.day") private var picksDay = ""
    @AppStorage("today.picks.ids") private var picksIDs = ""
    @State private var showMore = false

    private let dailyCount = 5

    // MARK: - Data

    private var ranked: [AttentionItem] {
        AttentionEngine.ranked(contacts.map(\.attentionInput), now: Date())
    }

    private var picks: [Contact] {
        let ids = picksIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    private var more: [(Contact, AttentionItem)] {
        let pickIDs = Set(picks.map(\.id))
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ranked.compactMap { item in
            guard !pickIDs.contains(item.id), let c = byID[item.id] else { return nil }
            return (c, item)
        }
    }

    private var unconfirmedCount: Int {
        contacts.filter { !$0.closenessConfirmed && $0.cachedInteractionCount == 0 && $0.targetOrbit < 4 }.count
    }

    private var upcoming: [(Contact, Artifact, Int)] {
        var result: [(Contact, Artifact, Int)] = []
        for contact in contacts {
            for fact in contact.artifacts ?? [] {
                guard let date = fact.dateValue, let days = Birthdays.daysUntil(date, from: Date()), days <= 14 else { continue }
                result.append((contact, fact, days))
            }
        }
        return result.sorted { $0.2 < $1.2 }
    }

    private var latest: [InteractionGroup] {
        Array(InteractionGroup.group(Array(allInteractions.prefix(24))).prefix(5))
    }

    private func isDone(_ c: Contact) -> Bool {
        c.lastContactDate.map { Calendar.current.isDateInToday($0) } ?? false
    }

    private var remainingCount: Int {
        picks.filter { !isDone($0) && !$0.isSnoozed }.count
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                masthead
                    .listRowSeparator(.hidden)
                if unconfirmedCount > 0 {
                    closenessCard
                        .listRowSeparator(.hidden)
                }
            }

            if !picks.isEmpty {
                Section {
                    ForEach(picks) { contact in
                        pickRow(contact)
                    }
                } header: {
                    sectionHeader("TODAY", trailing: remainingCount > 0 ? "\(remainingCount) left" : "done")
                }
            }

            if !more.isEmpty {
                Section {
                    if showMore {
                        ForEach(more, id: \.0.id) { pair in
                            suggestionRow(pair.0, reason: pair.1.reason)
                        }
                    }
                    Button(showMore ? "Show less" : "\(more.count) more could use a hello") {
                        withAnimation { showMore.toggle() }
                    }
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    sectionHeader("MORE", trailing: nil)
                }
            }

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming, id: \.1.id) { entry in
                        upcomingRow(entry.0, fact: entry.1, days: entry.2)
                    }
                } header: {
                    sectionHeader("COMING UP", trailing: nil)
                }
            }

            if !latest.isEmpty {
                Section {
                    ForEach(latest) { group in
                        latestRow(group)
                    }
                } header: {
                    sectionHeader("LATEST", trailing: nil)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: refreshPicks)
        .onChange(of: contacts.count) { _, _ in refreshPicks() }
    }

    private func refreshPicks() {
        let previousIDs = picksIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        let previous = picksDay.isEmpty ? nil : AttentionEngine.DailyPicks(day: picksDay, ids: previousIDs)
        let next = AttentionEngine.dailyPicks(ranked: ranked, previous: previous, now: Date(), count: dailyCount)
        if next.day != picksDay || next.ids != previousIDs {
            picksDay = next.day
            picksIDs = next.ids.map(\.uuidString).joined(separator: ",")
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 28, weight: .semibold))
            Text(statusSentence)
                .font(OrbitTypography.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, OrbitSpacing.md)
    }

    private var statusSentence: String {
        if contacts.isEmpty {
            return "Add a few people, then log when you're in touch. Orbit will suggest who to reach out to."
        }
        if picks.isEmpty {
            return "No one needs a nudge today."
        }
        switch remainingCount {
        case 0: return "You're caught up for today."
        case 1: return "One person to reach out to today."
        default: return "\(remainingCount) people to reach out to today."
        }
    }

    private var closenessCard: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text("\(unconfirmedCount) \(unconfirmedCount == 1 ? "person has" : "people have") no closeness set")
                .font(OrbitTypography.bodyMedium)
            Text("Choose how often you'd like to be in touch with the people who matter, and Orbit will remind you. Everyone else stays quiet.")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
            Button("Set closeness") { router.showClosenessReview = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(OrbitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, OrbitSpacing.sm)
    }

    // MARK: - Rows

    private func pickRow(_ contact: Contact) -> some View {
        let done = isDone(contact)
        let snoozed = contact.isSnoozed
        let reason: String = {
            if done { return "Logged today" }
            if snoozed, let until = contact.snoozedUntil { return "Snoozed until \(until.formatted(.dateTime.day().month(.abbreviated)))" }
            return contact.attentionReason ?? "On track now"
        }()

        return HStack(alignment: .center, spacing: OrbitSpacing.md) {
            Image(systemName: done ? "checkmark.circle.fill" : (snoozed ? "moon.zzz" : "circle"))
                .foregroundStyle(done ? AnyShapeStyle(OrbitColors.success) : AnyShapeStyle(.tertiary))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .foregroundStyle(done || snoozed ? .secondary : .primary)
                Text(reason)
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedContact = contact }

            Spacer(minLength: OrbitSpacing.sm)

            if !done {
                Button("Log") { router.log([contact]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            rowMenu(contact)
        }
        .padding(.vertical, OrbitSpacing.xs)
        .swipeActions(edge: .leading) {
            Button { router.log([contact]) } label: { Label("Log", systemImage: "plus.bubble") }
                .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button { snooze(contact, days: 7) } label: { Label("Snooze", systemImage: "moon.zzz") }
                .tint(.indigo)
        }
    }

    private func suggestionRow(_ contact: Contact, reason: String) -> some View {
        HStack(spacing: OrbitSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                Text(reason).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedContact = contact }
            Spacer()
            rowMenu(contact)
        }
        .swipeActions(edge: .leading) {
            Button { router.log([contact]) } label: { Label("Log", systemImage: "plus.bubble") }
                .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button { snooze(contact, days: 7) } label: { Label("Snooze", systemImage: "moon.zzz") }
                .tint(.indigo)
        }
    }

    private func rowMenu(_ contact: Contact) -> some View {
        Menu {
            Section("Quick log") {
                ForEach(store.actionSuggestions(limit: 3), id: \.self) { action in
                    Button(action) { store.log(contacts: [contact], action: action) }
                }
                Button("Log with details…", systemImage: "square.and.pencil") { router.log([contact]) }
            }
            Section("Snooze") {
                Button("For a week") { snooze(contact, days: 7) }
                Button("For a month") { snooze(contact, days: 30) }
                Button("For three months") { snooze(contact, days: 90) }
                if contact.isSnoozed {
                    Button("Unsnooze") { store.snooze([contact], until: nil) }
                }
            }
            Menu("Closeness") {
                ForEach(OrbitZone.allZones, id: \.id) { zone in
                    Button {
                        store.setCloseness(zone.id, for: [contact])
                    } label: {
                        if zone.id == contact.targetOrbit {
                            Label("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))", systemImage: "checkmark")
                        } else {
                            Text("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))")
                        }
                    }
                }
            }
            Button("Open", systemImage: "arrow.right") { selectedContact = contact }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel("More for \(contact.name)")
    }

    private func snooze(_ contact: Contact, days: Int) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))
        store.snooze([contact], until: until)
    }

    private func upcomingRow(_ contact: Contact, fact: Artifact, days: Int) -> some View {
        HStack(spacing: OrbitSpacing.md) {
            Image(systemName: "gift").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(contact.name)'s \(fact.key.lowercased())")
                    .font(OrbitTypography.body)
                Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(days <= 1 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
            Spacer()
            Button("Log") { router.log([contact]) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedContact = contact }
    }

    private func latestRow(_ group: InteractionGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Text(group.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(OrbitTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(latestHeadline(for: group)).font(OrbitTypography.body)
                if !group.content.isEmpty {
                    Text(group.content)
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let contact = group.contacts.first { selectedContact = contact }
        }
        .swipeActions(edge: .trailing) {
            Button { router.edit(group.representative) } label: { Label("Edit", systemImage: "pencil") }
        }
    }

    private func latestHeadline(for group: InteractionGroup) -> String {
        let names: String
        if group.isGroup {
            names = group.mutualConstellationName.map { "✦ \($0)" } ?? "\(group.contacts.count) people"
        } else {
            names = group.contacts.first?.name ?? "—"
        }
        return "\(group.impulse) with \(names)"
    }

    private func sectionHeader(_ label: String, trailing: String?) -> some View {
        HStack {
            Text(label)
                .font(OrbitTypography.captionMedium)
                .tracking(2)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(OrbitTypography.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
