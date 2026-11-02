import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OrbitStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @Binding var spotlightContactID: UUID?

    @AppStorage("orbit.onboarded") private var onboarded = false
    @AppStorage("orbit.notifications.enabled") private var notificationsEnabled = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        @Bindable var router = router

        Group {
            #if os(macOS)
            splitLayout
            #else
            if horizontalSizeClass == .compact {
                tabLayout
            } else {
                splitLayout
            }
            #endif
        }
        .overlay(alignment: toastAtTop ? .top : .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(toastAtTop ? .top : .bottom, toastAtTop ? OrbitSpacing.sm : OrbitSpacing.xl + OrbitSpacing.md)
                    .transition(.move(edge: toastAtTop ? .top : .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.toast?.id)
        .sheet(isPresented: $router.showPalette) {
            CommandPaletteView(seed: router.paletteSeed)
                .presentationDetents([.large])
        }
        .sheet(item: $router.composer) { request in
            LogComposer(mode: request.mode)
        }
        .sheet(isPresented: $router.showNewContact) {
            ContactFormSheet(mode: .add) { router.open($0) }
        }
        .sheet(isPresented: $router.showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $router.showClosenessReview) {
            ClosenessReviewSheet()
        }
        // Menu bar commands (macOS) and keyboard shortcuts (iPad).
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in router.openPalette() }
        .onReceive(NotificationCenter.default.publisher(for: .newContactRequested)) { _ in router.showNewContact = true }
        .onReceive(NotificationCenter.default.publisher(for: .undoRequested)) { _ in store.undo() }
        .onReceive(NotificationCenter.default.publisher(for: .navigateRequested)) { note in
            if let tab = note.object as? AppRouter.Tab { router.tab = tab }
        }
        .task {
            store.runV2MaintenanceIfNeeded()
            MomentumEngine.recomputeAll(in: modelContext)
            if !onboarded && store.activeContacts(includeArchived: true).isEmpty {
                router.showOnboarding = true
            }
            await rescheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                MomentumEngine.recomputeAll(in: modelContext)
                Task { await rescheduleNotifications() }
            }
        }
        .onChange(of: spotlightContactID) { _, newID in
            guard let id = newID else { return }
            let descriptor = FetchDescriptor<Contact>(predicate: #Predicate { $0.id == id })
            if let match = try? modelContext.fetch(descriptor).first {
                router.open(match)
            }
            spotlightContactID = nil
        }
    }

    /// In the Log tab the composer owns the bottom edge, so banners go on top.
    private var toastAtTop: Bool { router.tab == .log }

    private func rescheduleNotifications() async {
        guard notificationsEnabled else { return }
        await NotificationScheduler.shared.reschedule(using: store)
    }

    // MARK: - Split layout (macOS, iPad)

    private var splitLayout: some View {
        @Bindable var router = router
        return NavigationSplitView {
            List(selection: Binding<AppRouter.Tab?>(
                get: { router.tab },
                set: { if let tab = $0 { router.tab = tab } }
            )) {
                Section {
                    NavigationLink(value: AppRouter.Tab.today) { Label("Today", systemImage: "sun.max") }
                    NavigationLink(value: AppRouter.Tab.log) { Label("Log", systemImage: "text.bubble") }
                    NavigationLink(value: AppRouter.Tab.people) { Label("People", systemImage: "person.2") }
                    NavigationLink(value: AppRouter.Tab.groups) { Label("Groups", systemImage: "star") }
                }
                #if os(iOS)
                // macOS uses the standard Settings window (⌘,).
                Section {
                    NavigationLink(value: AppRouter.Tab.settings) { Label("Settings", systemImage: "gearshape") }
                }
                #endif
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 250)
            .navigationTitle("Orbit")
        } content: {
            switch router.tab {
            case .today:
                TodayView(selectedContact: $router.todaySelection)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            case .people:
                PeopleView(selectedContact: $router.peopleSelection)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            case .groups:
                ConstellationListView(selectedConstellation: $router.groupSelection)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            case .log:
                NavigationStack {
                    LogTabView(selectedContact: $router.logSelection)
                }
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            case .settings:
                SettingsView()
            }
        } detail: {
            NavigationStack {
                switch router.tab {
                case .today:
                    contactDetail(router.todaySelection, empty: "Pick someone from Today")
                case .people:
                    contactDetail(router.peopleSelection, empty: "Choose someone from the list")
                case .log:
                    contactDetail(router.logSelection, empty: "Log something, or open someone from a log")
                case .groups:
                    if let group = router.groupSelection {
                        ConstellationDetailView(constellation: group, selectedContact: $router.groupMemberSelection)
                            .navigationDestination(item: $router.groupMemberSelection) { ContactDetailView(contact: $0) }
                    } else {
                        ContentUnavailableView("Select a group", systemImage: "star")
                    }
                case .settings:
                    ContentUnavailableView("Settings", systemImage: "gearshape")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { router.openPalette() } label: {
                    Label("Log or find", systemImage: "square.and.pencil")
                }
                .help("Log or find (⌘K)")
            }
        }
    }

    @ViewBuilder
    private func contactDetail(_ contact: Contact?, empty: String) -> some View {
        if let contact {
            ContactDetailView(contact: contact)
        } else {
            ContentUnavailableView(empty, systemImage: "person.crop.circle")
        }
    }

    // MARK: - Tab layout (iPhone)
    // Each tab has its own selection, so opening someone in Today no longer
    // pushes them onto the other tabs' stacks too.
    // The Log tab sits second, by the thumb, and holds the capture composer.

    private var tabLayout: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            NavigationStack {
                TodayView(selectedContact: $router.todaySelection)
                    .navigationDestination(item: $router.todaySelection) { ContactDetailView(contact: $0) }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppRouter.Tab.today)

            NavigationStack {
                LogTabView(selectedContact: $router.logSelection)
                    .navigationDestination(item: $router.logSelection) { ContactDetailView(contact: $0) }
            }
            .tabItem { Label("Log", systemImage: "square.and.pencil") }
            .tag(AppRouter.Tab.log)

            NavigationStack {
                PeopleView(selectedContact: $router.peopleSelection)
                    .navigationDestination(item: $router.peopleSelection) { ContactDetailView(contact: $0) }
            }
            .tabItem { Label("People", systemImage: "person.2") }
            .tag(AppRouter.Tab.people)

            NavigationStack {
                ConstellationListView(selectedConstellation: $router.groupSelection)
                    .navigationDestination(item: $router.groupSelection) { group in
                        ConstellationDetailView(constellation: group, selectedContact: $router.groupMemberSelection)
                    }
                    .navigationDestination(item: $router.groupMemberSelection) { ContactDetailView(contact: $0) }
            }
            .tabItem { Label("Groups", systemImage: "star") }
            .tag(AppRouter.Tab.groups)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppRouter.Tab.settings)
        }
    }
}
