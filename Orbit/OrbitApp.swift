import SwiftUI
import SwiftData
import CoreSpotlight

// MARK: - OrbitApp (Phase 2 + Fix 1)
// FIX 1: Recovery mode now sets a flag that the UI can display,
// alerting the user they're running without iCloud sync.

@main
struct OrbitApp: App {
    let container: ModelContainer
    let commandExecutor = CommandExecutor()
    let spotlightIndexer = SpotlightIndexer()
    let dataValidator = DataValidator()

    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appTint") private var appTint: AppTint = .blue
    
    @State private var spotlightContactID: UUID?
    @State private var isRecoveryBannerVisible: Bool = false

    // FIX 1: Track if we're in recovery mode
    private let isRecoveryMode: Bool

    init() {
        var recoveryMode = false

        do {
            let schema = Schema(OrbitSchemaV1.models)
            let config = ModelConfiguration(
                "Orbit",
                schema: schema,
                cloudKitDatabase: .automatic
            )

            container = try ModelContainer(
                for: schema,
                configurations: [config]
            )
        } catch {
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
                recoveryMode = true
                print("⚠️ Running in recovery mode (local only, no sync)")
            } catch {
                fatalError("Cannot initialize any ModelContainer: \(error.localizedDescription)")
            }
        }

        self.isRecoveryMode = recoveryMode
        self._isRecoveryBannerVisible = State(initialValue: recoveryMode)
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            VStack(spacing: 0) {
                ContentView(spotlightContactID: $spotlightContactID)
                    .environment(commandExecutor)
                    .environment(spotlightIndexer)
                    .environment(dataValidator)
                    .preferredColorScheme(appTheme.colorScheme)
                    .tint(appTint.color)
                    .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                        if let contactID = SpotlightIndexer.contactID(from: userActivity) {
                            spotlightContactID = contactID
                        }
                    }

                if isRecoveryMode && isRecoveryBannerVisible {
                    recoveryBanner
                }
            }
        }
        .modelContainer(container)
        .commands {
            OrbitCommands()
        }
        .windowStyle(.hiddenTitleBar)
        Settings {
            SettingsView()
                .modelContainer(container)
                .environment(dataValidator)
                .environment(spotlightIndexer)
                .preferredColorScheme(appTheme.colorScheme)
                .tint(appTint.color)
                .frame(minWidth: 520, minHeight: 420)
        }
        #else
        WindowGroup {
            VStack(spacing: 0) {
                ContentView(spotlightContactID: $spotlightContactID)
                    .environment(commandExecutor)
                    .environment(spotlightIndexer)
                    .environment(dataValidator)
                    .preferredColorScheme(appTheme.colorScheme)
                    .tint(appTint.color)
                    .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                        if let contactID = SpotlightIndexer.contactID(from: userActivity) {
                            spotlightContactID = contactID
                        }
                    }

                if isRecoveryMode && isRecoveryBannerVisible {
                    recoveryBanner
                }
            }
        }
        .modelContainer(container)
        .commands {
            OrbitCommands()
        }
        #endif
    }

    // FIX 1: Visual indicator when running in recovery mode
    private var recoveryBanner: some View {
        HStack(spacing: OrbitSpacing.sm) {
            Image(systemName: "exclamationmark.icloud")
                .font(.caption)
            Text("Running in recovery mode — iCloud sync is disabled")
                .font(OrbitTypography.footnote)
            Spacer()
            Button(action: { isRecoveryBannerVisible = false }) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm)
        .background(.orange.gradient)
    }
}
