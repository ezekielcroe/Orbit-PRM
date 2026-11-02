import SwiftUI
import SwiftData

// MARK: - OnboardingView
// First-run flow: what Orbit does, how to log, then a way in — add someone,
// import, or try sample data — plus an optional weekly reminder. Replaces the
// seven-page syntax tutorial as the first thing a new user sees.

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router

    @AppStorage("orbit.onboarded") private var onboarded = false
    @AppStorage("hasSampleData") private var hasSampleData = false
    @AppStorage("orbit.notifications.enabled") private var notificationsEnabled = false

    @State private var page = 0
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case 0: intro
                    case 1: logging
                    default: start
                    }
                }
                .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
                .padding(OrbitSpacing.lg)

                HStack {
                    if page > 0 {
                        Button("Back") { withAnimation { page -= 1 } }
                    }
                    Spacer()
                    if page < 2 {
                        Button("Next") { withAnimation { page += 1 } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(OrbitSpacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 520)
        #endif
        .onDisappear { onboarded = true }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
            Text("Keep in touch with the people who matter.")
                .font(.system(size: 28, weight: .semibold))
            bullet("sun.max", "Each day, Today suggests a few people to reach out to — and says why.")
            bullet("text.cursor", "Log in plain words when you catch up. No forms, no syntax.")
            bullet("person.2", "Choose how close each person is. Only the ones you choose get reminders.")
        }
    }

    private var logging: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
            Text("Log in plain words")
                .font(.system(size: 28, weight: .semibold))
            Text("Tap \(Image(systemName: "square.and.pencil")) or press ⌘K and type what happened:")
                .font(OrbitTypography.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                Text("Coffee with Sarah yesterday, talked about her move")
                Text("Called Mum about her surgery")
                Text("Dinner with Sam and Jo on Friday")
            }
            .font(OrbitTypography.bodyMedium)
            .padding(OrbitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Text("Orbit shows what it understood before saving. New names can be added on the spot, and every change can be undone.")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
            Text("Get started")
                .font(.system(size: 28, weight: .semibold))

            Button {
                finish { router.showNewContact = true }
            } label: {
                startOption("person.badge.plus", "Add someone", "Start with the people you think of first.")
            }
            .buttonStyle(.plain)

            #if os(macOS)
            Button {
                finish { openSettings() }
            } label: {
                startOption("person.crop.rectangle.stack", "Import from Contacts", "Opens Settings → Data. Imported people stay quiet until you set their closeness.")
            }
            .buttonStyle(.plain)
            #else
            Button {
                finish { router.tab = .settings }
            } label: {
                startOption("person.crop.rectangle.stack", "Import from Contacts", "Opens Settings → Data. Imported people stay quiet until you set their closeness.")
            }
            .buttonStyle(.plain)
            #endif

            Button {
                SampleDataGenerator.generate(in: modelContext)
                hasSampleData = true
                store.refresh(store.activeContacts(includeArchived: true))
                store.save("sample data")
                finish()
            } label: {
                startOption("sparkles", "Try sample data", "Explore with made-up people. Remove it later in Settings.")
            }
            .buttonStyle(.plain)

            Toggle(isOn: Binding(
                get: { notificationsEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            notificationsEnabled = await NotificationScheduler.shared.requestAuthorization()
                        }
                    } else {
                        notificationsEnabled = false
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly reminder and birthdays").font(OrbitTypography.bodyMedium)
                    Text("A short nudge on Sunday evening, and a heads-up before birthdays.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Color.accentColor)
            Text(text).font(OrbitTypography.body)
        }
    }

    private func startOption(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: OrbitSpacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(OrbitTypography.bodyMedium).foregroundStyle(.primary)
                Text(detail).font(OrbitTypography.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(OrbitSpacing.md)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func finish(then next: (() -> Void)? = nil) {
        onboarded = true
        dismiss()
        if let next {
            // Let this sheet finish dismissing before presenting another.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { next() }
        }
    }
}

// MARK: - ClosenessReviewSheet
// Quickly set closeness for people who have none yet (usually imported).
// Choosing one confirms it, which lets Today start suggesting that person.

struct ClosenessReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OrbitStore.self) private var store

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    /// Captured on appear so rows don't vanish as they're confirmed.
    @State private var ids: [UUID] = []
    @State private var search = ""

    private var rows: [Contact] {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let list = ids.compactMap { byID[$0] }
        return search.isEmpty ? list : list.filter { $0.matchesSearch(search) }
    }

    private var remaining: [Contact] { rows.filter { !$0.closenessConfirmed } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { contact in
                        HStack {
                            Text(contact.name)
                                .foregroundStyle(contact.closenessConfirmed ? .secondary : .primary)
                            Spacer()
                            Menu {
                                ForEach(OrbitZone.allZones, id: \.id) { zone in
                                    Button("\(zone.name) · \(AttentionEngine.cadenceWord(forOrbit: zone.id))") {
                                        store.setCloseness(zone.id, for: [contact])
                                    }
                                }
                            } label: {
                                Text(contact.closenessConfirmed ? contact.orbitZoneName : "Choose…")
                                    .font(OrbitTypography.captionMedium)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                } footer: {
                    Text("Inner Circle is weekly, Near Orbit monthly, Mid Orbit every few months, Outer Orbit yearly. Deep Space never reminds you.")
                }
            }
            .searchable(text: $search, prompt: "Search")
            .navigationTitle("Set closeness")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Leave the rest quiet") {
                        store.setCloseness(4, for: remaining)
                    }
                    .disabled(remaining.isEmpty)
                }
            }
            .onAppear {
                if ids.isEmpty {
                    ids = contacts
                        .filter { !$0.closenessConfirmed && $0.cachedInteractionCount == 0 && $0.targetOrbit < 4 }
                        .map(\.id)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}
