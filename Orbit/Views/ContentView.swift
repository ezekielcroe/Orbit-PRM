import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CommandExecutor.self) private var executor
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Binding var spotlightContactID: UUID?

    // 1. ADD: interactions to NavTab
    enum NavTab: Hashable {
        case people
        case constellations
        case interactions
        case settings
    }
    
    @State private var selectedTab: NavTab = .people
    @State private var selectedContact: Contact?
    @State private var selectedConstellation: Constellation?
    
    @State private var showCommandPalette = false
    @State private var showSettings = false
    
    @Query(sort: \Constellation.name) private var constellations: [Constellation]

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            threeColumnMacLayout
            #else
            if horizontalSizeClass == .compact {
                mobileTabLayout
            } else {
                threeColumnMacLayout
            }
            #endif
        }
        // 1. Present the Command Palette directly here
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                isPresented: $showCommandPalette,
                onNavigateToContact: { contact in
                    // Direct navigation control!
                    selectedTab = .people
                    selectedContact = contact
                },
                onNavigateToConstellation: { constellation in
                    selectedTab = .constellations
                    selectedConstellation = constellation
                }
            )
            .presentationDetents([.medium, .large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
        }
        // 2. Listen for the keyboard shortcut
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in
            showCommandPalette = true
        }
        // 3. FIX: Handle Apple Spotlight deep links
        .onChange(of: spotlightContactID) { _, newID in
            if let id = newID {
                let descriptor = FetchDescriptor<Contact>(predicate: #Predicate { $0.id == id })
                if let match = try? modelContext.fetch(descriptor).first {
                    selectedTab = .people
                    selectedContact = match
                }
                spotlightContactID = nil // Reset after consuming
            }
        }
    }

    // MARK: - macOS & iPadOS Layout (3-Column)
    private var threeColumnMacLayout: some View {
        NavigationSplitView {
            // 1. Sidebar Column
            List(selection: Binding<NavTab?>(
                get: { selectedTab },
                set: { if let newTab = $0 { selectedTab = newTab } }
            )) {
                Section("Library") {
                    NavigationLink(value: NavTab.people) {
                        Label("People", systemImage: "person.2")
                    }
                    NavigationLink(value: NavTab.constellations) {
                        Label("Constellations", systemImage: "star")
                    }
                    NavigationLink(value: NavTab.interactions) {
                        Label("Activity", systemImage: "text.bubble")
                    }
                }
                
                Section("Preferences") {
                    NavigationLink(value: NavTab.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 250)
            .navigationTitle("Orbit")
            
        } content: {
            // 2. Middle Content Column
            switch selectedTab {
            case .people:
                PeopleView(
                    selectedContact: $selectedContact,
                    showCommandPalette: $showCommandPalette,
                    showSettings: .constant(false)
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                
            case .constellations:
                ConstellationListView(selectedConstellation: $selectedConstellation)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                
            // 3. ADD: Interactions Middle Column
            case .interactions:
                InteractionsView(selectedContact: $selectedContact)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 350) // Slightly wider for log reading
                
            case .settings:
                SettingsView()
            }
            
        } detail: {
            // 3. Detail Column
            switch selectedTab {
            case .people, .interactions: // 4. ADD: .interactions shares People's detail view (the contact)
                if let contact = selectedContact {
                    ContactDetailView(contact: contact)
                } else {
                    ContentUnavailableView(
                        selectedTab == .people ? "Select a Contact" : "Select an Interaction",
                        systemImage: selectedTab == .people ? "person.crop.circle" : "text.bubble",
                        description: Text(selectedTab == .people ? "Choose someone from the list to view their details." : "Choose an interaction to view the contact's details.")
                    )
                }
                
            case .constellations:
                if let constellation = selectedConstellation {
                    NavigationStack {
                        ConstellationDetailView(constellation: constellation, selectedContact: $selectedContact)
                    }
                } else {
                    ContentUnavailableView("Select a Constellation", systemImage: "star")
                }
                
            case .settings:
                ContentUnavailableView("Settings", systemImage: "gear", description: Text("Manage your Orbit preferences."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showCommandPalette = true }) {
                    Label("Command Palette", systemImage: "command")
                }
            }
        }
    }

    // MARK: - iOS Layout (Tab Bar)
    private var mobileTabLayout: some View {
        TabView(selection: $selectedTab) {
            
            // People Tab
            NavigationStack {
                PeopleView(
                    selectedContact: $selectedContact,
                    showCommandPalette: $showCommandPalette,
                    showSettings: $showSettings
                )
                .navigationDestination(item: $selectedContact) { contact in
                    ContactDetailView(contact: contact)
                }
            }
            .tabItem { Label("People", systemImage: "person.2") }
            .tag(NavTab.people)

            // Constellations Tab
            NavigationStack {
                ConstellationListView(selectedConstellation: $selectedConstellation)
                    .navigationDestination(item: $selectedConstellation) { constellation in
                        ConstellationDetailView(constellation: constellation, selectedContact: $selectedContact)
                    }
            }
            .tabItem { Label("Constellations", systemImage: "star") }
            .tag(NavTab.constellations)

            // 5. ADD: Interactions Tab
            NavigationStack {
                InteractionsView(selectedContact: $selectedContact)
                    .navigationDestination(item: $selectedContact) { contact in
                        ContactDetailView(contact: contact)
                    }
            }
            .tabItem { Label("Activity", systemImage: "text.bubble") }
            .tag(NavTab.interactions)

            // Settings Tab
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(NavTab.settings)
        }
    }
}

// MARK: - Logic Attachment Extension
extension View {
    func attachCommonLogic(showCommandPalette: Binding<Bool>, spotlightContactID: Binding<UUID?>) -> some View {
        self.modifier(NavigationLogicModifier(showCommandPalette: showCommandPalette, spotlightContactID: spotlightContactID))
    }
}

struct NavigationLogicModifier: ViewModifier {
    @Binding var showCommandPalette: Bool
    @Binding var spotlightContactID: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showCommandPalette) {
                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    onNavigateToContact: { contact in
                        // Deep link logic for command palette
                        spotlightContactID = contact.id
                    }
                )
                .presentationDetents([.medium, .large])
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
            }
            // Listen for global menu bar commands
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in
                showCommandPalette = true
            }
    }
}
