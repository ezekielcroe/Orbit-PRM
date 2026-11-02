import SwiftUI

// MARK: - OrbitCommands
// Every item here is handled by ContentView (previously ⌘N and ⌘1 posted
// notifications nothing listened for).

struct OrbitCommands: Commands {

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Contact") {
                NotificationCenter.default.post(name: .newContactRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Log or Find…") {
                NotificationCenter.default.post(name: .commandPaletteRequested, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandGroup(after: .undoRedo) {
            Button("Undo Last Change") {
                NotificationCenter.default.post(name: .undoRequested, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
        }

        CommandMenu("Navigate") {
            navButton("Today", .today, "1")
            navButton("Log", .log, "2")
            navButton("People", .people, "3")
            navButton("Groups", .groups, "4")
        }
    }

    private func navButton(_ title: String, _ tab: AppRouter.Tab, _ key: KeyEquivalent) -> some View {
        Button(title) {
            NotificationCenter.default.post(name: .navigateRequested, object: tab)
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newContactRequested = Notification.Name("orbit.newContact")
    static let commandPaletteRequested = Notification.Name("orbit.commandPalette")
    static let undoRequested = Notification.Name("orbit.undo")
    static let navigateRequested = Notification.Name("orbit.navigate")
}
