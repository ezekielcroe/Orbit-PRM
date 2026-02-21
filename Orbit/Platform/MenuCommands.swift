import SwiftUI

// MARK: - OrbitCommands
// Simplified menu bar commands reflecting the merged navigation.
// ⌘1 goes to People (the single primary view).
// ⌘K opens the command palette.

struct OrbitCommands: Commands {

    var body: some Commands {
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

        CommandMenu("Navigate") {
            Button("People") {
                NotificationCenter.default.post(name: .showDashboardRequested, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newContactRequested = Notification.Name("orbit.newContact")
    static let commandPaletteRequested = Notification.Name("orbit.commandPalette")
    static let showDashboardRequested = Notification.Name("orbit.showDashboard")
    static let showContactsRequested = Notification.Name("orbit.showContacts")
}
