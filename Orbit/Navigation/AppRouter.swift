import Foundation
import SwiftUI

// MARK: - AppRouter
// App-wide navigation state. Replaces the single shared `selectedContact`
// (which made every iPhone tab push the same contact at once) with one
// selection per tab, and gives every screen one way to open the palette,
// the log composer or a contact.

struct ComposerRequest: Identifiable {
    let id = UUID()
    let mode: LogComposer.Mode
}

@Observable
final class AppRouter {
    enum Tab: Hashable, CaseIterable {
        case today, log, people, groups, settings
    }

    var tab: Tab = .today

    // One selection per tab.
    var todaySelection: Contact?
    var peopleSelection: Contact?
    var logSelection: Contact?
    var groupSelection: Constellation?
    var groupMemberSelection: Contact?

    // Sheets presented from ContentView.
    var showPalette = false
    var paletteSeed = ""
    var showNewContact = false
    var composer: ComposerRequest?
    var showOnboarding = false
    var showClosenessReview = false

    /// Open a contact's page (Spotlight, palette, links).
    func open(_ contact: Contact) {
        tab = .people
        peopleSelection = contact
    }

    func open(_ group: Constellation) {
        tab = .groups
        groupSelection = group
    }

    /// Clear any selection pointing at a contact that is about to be deleted.
    func forget(_ contact: Contact) {
        let id = contact.id
        if todaySelection?.id == id { todaySelection = nil }
        if peopleSelection?.id == id { peopleSelection = nil }
        if logSelection?.id == id { logSelection = nil }
        if groupMemberSelection?.id == id { groupMemberSelection = nil }
    }

    func openPalette(seed: String = "") {
        paletteSeed = seed
        showPalette = true
    }

    func log(_ contacts: [Contact], action: String? = nil) {
        composer = ComposerRequest(mode: .new(contacts: contacts, group: nil, action: action))
    }

    func log(group: Constellation) {
        composer = ComposerRequest(mode: .new(contacts: [], group: group, action: nil))
    }

    func edit(_ interaction: Interaction) {
        composer = ComposerRequest(mode: .edit(interaction))
    }
}
