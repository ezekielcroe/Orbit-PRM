import SwiftUI
import SwiftData
import CoreSpotlight

// MARK: - OrbitApp (Phase 2)
// Updates from Phase 1:
// - Spotlight indexer injected into environment
// - Data validator injected into environment
// - macOS menu commands enabled
// - Handles Spotlight continuation (user taps a search result)
// - Graceful error handling for ModelContainer initialization
//
// FIX 2: macOS Settings scene passes environment objects and uses
//        a wider default frame. SettingsView itself handles the TabView.

@main
struct OrbitApp: App {
    let container: ModelContainer
    let commandExecutor = CommandExecutor()
    let spotlightIndexer = SpotlightIndexer()
    let dataValidator = DataValidator()

    @State private var spotlightContactID: UUID?

    init() {
        do {
            let schema = Schema(OrbitSchemaV1.models)
            let config = ModelConfiguration(
                "Orbit",
                schema: schema,
                // CloudKit sync enabled. Requires iCloud capability in Xcode.
                // For local-only development, change to .none
                cloudKitDatabase: .automatic
            )

            container = try ModelContainer(
                for: schema,
                configurations: [config]
            )
        } catch {
            // Phase 2: More graceful handling than fatalError.
            // Log the error and attempt a fallback with a fresh store.
            print("❌ ModelContainer initialization failed: \(error.localizedDescription)")
            print("Attempting fallback with fresh store...")

            do {
                let schema = Schema(OrbitSchemaV1.models)
                let fallbackConfig = ModelConfiguration(
                    "Orbit-Recovery",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfig]
                )
                print("⚠️ Running in recovery mode (local only, no sync)")
            } catch {
                fatalError("Cannot initialize any ModelContainer: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(spotlightContactID: $spotlightContactID)
                .environment(commandExecutor)
                .environment(spotlightIndexer)
                .environment(dataValidator)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    // Handle Spotlight result taps
                    spotlightContactID = SpotlightIndexer.contactID(from: activity)
                }
        }
        .modelContainer(container)
        // Phase 2: macOS menu commands
        .commands {
            OrbitCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
                .environment(dataValidator)
                .frame(minWidth: 520, minHeight: 420)
        }
        #endif
    }
}
