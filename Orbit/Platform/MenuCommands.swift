import SwiftUI

// MARK: - OrbitCommands (Phase 2)
// Expanded macOS menu bar commands with additional keyboard shortcuts.
// These are now actively wired into the app via NotificationCenter.

struct OrbitCommands: Commands {

    var body: some Commands {
        // Replace the default "New" command
        CommandGroup(replacing: .newItem) {
            Button("New Contact") {
                NotificationCenter.default.post(name: .newContactRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Command Palette") {
                NotificationCenter.default.post(name: .commandPaletteRequested, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Quick Log") {
                NotificationCenter.default.post(name: .commandPaletteRequested, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        // Navigation menu
        CommandMenu("Navigate") {
            Button("Dashboard") {
                NotificationCenter.default.post(name: .showDashboardRequested, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Contacts") {
                NotificationCenter.default.post(name: .showContactsRequested, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Review") {
                NotificationCenter.default.post(name: .showReviewRequested, object: nil)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Table View") {
                NotificationCenter.default.post(name: .showTableRequested, object: nil)
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Constellations") {
                NotificationCenter.default.post(name: .showConstellationsRequested, object: nil)
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("Tags") {
                NotificationCenter.default.post(name: .showTagsRequested, object: nil)
            }
            .keyboardShortcut("6", modifiers: .command)
        }
    }
}

// MARK: - Notification Names (Phase 2)
// Expanded to cover all navigable sections.

extension Notification.Name {
    static let newContactRequested = Notification.Name("orbit.newContact")
    static let commandPaletteRequested = Notification.Name("orbit.commandPalette")
    static let showDashboardRequested = Notification.Name("orbit.showDashboard")
    static let showContactsRequested = Notification.Name("orbit.showContacts")
    static let showReviewRequested = Notification.Name("orbit.showReview")
    static let showTableRequested = Notification.Name("orbit.showTable")
    static let showConstellationsRequested = Notification.Name("orbit.showConstellations")
    static let showTagsRequested = Notification.Name("orbit.showTags")
}
