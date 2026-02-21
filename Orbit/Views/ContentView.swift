import SwiftUI
import SwiftData

// MARK: - ContentView (Refactored)
// No sidebar. PeopleView IS the primary content. Settings is accessed
// via a toolbar gear button (sheet on iOS, Settings window on macOS).
//
// Two-column NavigationSplitView:
//   People list → Contact detail

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CommandExecutor.self) private var executor
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Binding var spotlightContactID: UUID?

    @State private var selectedContact: Contact?
    @State private var showCommandPalette = false
    @State private var showSettings = false
    @State private var commandResultMessage: String?

    var body: some View {
        NavigationSplitView {
            PeopleView(
                selectedContact: $selectedContact,
                showCommandPalette: $showCommandPalette,
                showSettings: $showSettings
            )
        } detail: {
            detailPanel
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                isPresented: $showCommandPalette,
                onNavigateToContact: { contact in
                    selectedContact = contact
                    spotlightIndexer.index(contact: contact)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
        .overlay(alignment: .bottom) {
            resultToast
        }
        .onChange(of: spotlightContactID) { _, newID in
            if let id = newID {
                navigateToContact(id: id)
                spotlightContactID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newContactRequested)) { _ in
            // Already on People
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDashboardRequested)) { _ in
            // Already on People
        }
        .onReceive(NotificationCenter.default.publisher(for: .showContactsRequested)) { _ in
            // Already on People
        }
        .task {
            spotlightIndexer.reindexAll(from: modelContext)
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
        }
    }
}
