import SwiftUI
import SwiftData

// MARK: - LogTabView
// Where a power user spends their time: a chat-style history of everything
// logged (newest at the bottom), with the capture composer docked under it,
// next to the keyboard. Replaces the Activity tab; the full searchable,
// batch-editable list is one tap away in the toolbar.

struct LogTabView: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Binding var selectedContact: Contact?

    @Query private var recent: [Interaction]

    init(selectedContact: Binding<Contact?>) {
        _selectedContact = selectedContact
        var descriptor = FetchDescriptor<Interaction>(
            predicate: #Predicate<Interaction> { !$0.isDeleted },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 150
        _recent = Query(descriptor)
    }

    /// Oldest first, so the newest sits just above the composer.
    private var entries: [InteractionGroup] {
        Array(InteractionGroup.group(recent).reversed())
    }

    private var days: [(day: Date, groups: [InteractionGroup])] {
        let cal = Calendar.current
        var result: [(Date, [InteractionGroup])] = []
        for group in entries {
            let day = cal.startOfDay(for: group.date)
            if let last = result.last, last.0 == day {
                result[result.count - 1].1.append(group)
            } else {
                result.append((day, [group]))
            }
        }
        return result.map { (day: $0.0, groups: $0.1) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    if entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(days, id: \.day) { day in
                            Text(dayLabel(day.day))
                                .font(OrbitTypography.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, OrbitSpacing.sm)
                            ForEach(day.groups) { group in
                                LogBubble(group: group) { contact in selectedContact = contact }
                                    .id(group.id)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, OrbitSpacing.md)
                .padding(.vertical, OrbitSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: recent.first?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CapturePanel(style: .docked)
            }
        }
        .navigationTitle("Log")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    InteractionsView(selectedContact: $selectedContact)
                } label: {
                    Label("All activity", systemImage: "list.bullet")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.md) {
            Text("Type what happened below.")
                .font(OrbitTypography.bodyMedium)
            ForEach(CapturePanel.examples) { ex in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.text).font(OrbitTypography.body)
                    if let note = ex.note {
                        Text(note).font(OrbitTypography.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.top, OrbitSpacing.xl)
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: day, to: cal.startOfDay(for: Date())).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}

// MARK: - LogBubble
// One logged event, shown like a sent message: what, who, note, tags, time.
// Tap to edit; long-press for more.

struct LogBubble: View {
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router

    let group: InteractionGroup
    var openContact: (Contact) -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.xs) {
                    Text(group.impulse).font(OrbitTypography.bodyMedium)
                    Text("with \(who)").font(OrbitTypography.body)
                }
                if !group.content.isEmpty {
                    Text(group.content)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: OrbitSpacing.sm) {
                    if !group.tagList.isEmpty {
                        Text(group.tagList.map { "#\($0)" }.joined(separator: " "))
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(OrbitColors.syntaxTag)
                    }
                    Spacer(minLength: 0)
                    Text(group.date.formatted(date: .omitted, time: .shortened))
                        .font(OrbitTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, OrbitSpacing.md)
            .padding(.vertical, OrbitSpacing.sm + 2)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture { router.edit(group.representative) }
            .contextMenu {
                Button("Edit", systemImage: "pencil") { router.edit(group.representative) }
                ForEach(group.contacts.prefix(6)) { contact in
                    Button("Open \(contact.name)", systemImage: "person") { openContact(contact) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.delete(group.representative, includeBatch: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double-tap to edit")
        }
    }

    private var who: String {
        if group.isGroup {
            return group.mutualConstellationName.map { "✦ \($0)" } ?? store.names(group.contacts)
        }
        return group.contacts.first?.name ?? "—"
    }
}
