import SwiftUI
import SwiftData

// MARK: - ContentView (Phase 2)
// Updates from Phase 1:
// - Added Review, Table View, and Settings sections
// - Handles Spotlight deep-linking (navigates to contact from system search)
// - Notification-based menu command handling for macOS
// - Result toast with animation
//
// FIX 2: On macOS, Settings is accessed via the menu bar (⌘,),
//        so it's hidden from the sidebar to avoid redundancy.

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CommandExecutor.self) private var executor
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Binding var spotlightContactID: UUID?

    @State private var selectedSection: NavigationSection? = .dashboard
    @State private var selectedContact: Contact?
    @State private var showCommandPalette = false
    @State private var commandResultMessage: String?

    enum NavigationSection: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case contacts = "Contacts"
        case review = "Review"
        case table = "Table"
        case constellations = "Constellations"
        case tags = "Tags"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "circle.grid.2x2"
            case .contacts: return "person.2"
            case .review: return "eye"
            case .table: return "tablecells"
            case .constellations: return "star.circle"
            case .tags: return "tag"
            case .settings: return "gear"
            }
        }

        /// Group sections for sidebar display
        static var primarySections: [NavigationSection] {
            [.dashboard, .contacts, .review, .table]
        }

        static var organizationSections: [NavigationSection] {
            [.constellations, .tags]
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentPanel
        } detail: {
            detailPanel
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                isPresented: $showCommandPalette,
                onNavigateToContact: { contact in
                    selectedContact = contact
                    selectedSection = .contacts
                    // Re-index the contact in Spotlight after modification
                    spotlightIndexer.index(contact: contact)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            resultToast
        }
        // Handle Spotlight deep-link
        .onChange(of: spotlightContactID) { _, newID in
            if let id = newID {
                navigateToContact(id: id)
                spotlightContactID = nil
            }
        }
        // macOS menu command handlers
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newContactRequested)) { _ in
            selectedSection = .contacts
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDashboardRequested)) { _ in
            selectedSection = .dashboard
        }
        .onReceive(NotificationCenter.default.publisher(for: .showContactsRequested)) { _ in
            selectedSection = .contacts
        }
        // Initial Spotlight indexing
        .task {
            spotlightIndexer.reindexAll(from: modelContext)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Section("Views") {
                ForEach(NavigationSection.primarySections) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }

            Section("Organize") {
                ForEach(NavigationSection.organizationSections) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }

            // FIX 2: On macOS, Settings is accessed via the menu bar (⌘,)
            // so we don't show it in the sidebar. On iOS, it stays.
            #if os(iOS)
            Section {
                Label(NavigationSection.settings.rawValue, systemImage: NavigationSection.settings.icon)
                    .tag(NavigationSection.settings)
            }
            #endif
        }
        .navigationTitle("Orbit")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showCommandPalette = true
                } label: {
                    Image(systemName: "terminal")
                }
                .help("Command Palette (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        #endif
    }

    // MARK: - Content Panel

    @ViewBuilder
    private var contentPanel: some View {
        switch selectedSection {
        case .dashboard:
            DashboardView(
                selectedContact: $selectedContact,
                showCommandPalette: $showCommandPalette
            )
        case .contacts:
            ContactListView(selectedContact: $selectedContact)
        case .review:
            ReviewDashboardView()
        case .table:
            TabularView()
        case .constellations:
            ConstellationListView()
        case .tags:
            TagListView()
        case .settings:
            SettingsView()
        case .none:
            Text("Select a section")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let contact = selectedContact {
            ContactDetailView(contact: contact)
        } else {
            ContentUnavailableView(
                "Select a Contact",
                systemImage: "person.crop.circle",
                description: Text("Choose a contact from the list, or use the command palette (⌘K) to get started.")
            )
        }
    }

    // MARK: - Result Toast

    @ViewBuilder
    private var resultToast: some View {
        if let message = commandResultMessage {
            Text(message)
                .font(OrbitTypography.caption)
                .padding(.horizontal, OrbitSpacing.md)
                .padding(.vertical, OrbitSpacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, OrbitSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { commandResultMessage = nil }
                    }
                }
        }
    }

    // MARK: - Spotlight Navigation

    private func navigateToContact(id: UUID) {
        let predicate = #Predicate<Contact> { contact in
            contact.id == id
        }
        var descriptor = FetchDescriptor<Contact>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let contact = try? modelContext.fetch(descriptor).first {
            selectedContact = contact
            selectedSection = .contacts
        }
    }
}
