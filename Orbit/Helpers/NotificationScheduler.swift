import Foundation
import UserNotifications

// MARK: - NotificationScheduler
// Local reminders so Orbit doesn't depend on being opened:
//   • a weekly digest (Sunday 18:00) naming who could use a hello
//   • a morning heads-up on birthdays / anniversaries from date facts
// Everything is rescheduled on launch and whenever the app becomes active,
// so the digest text stays current. Only identifiers with our prefix are
// touched. Nothing leaves the device.

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "orbit."
    /// iOS keeps at most 64 pending local notifications per app.
    private let maxBirthdayReminders = 40

    /// Ask for permission. Returns whether alerts are allowed.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func disable() {
        Task {
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    func reschedule(using store: OrbitStore) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let contacts = store.activeContacts()
        let now = Date()

        // Weekly digest
        let ranked = AttentionEngine.ranked(contacts.map(\.attentionInput), now: now)
        if !ranked.isEmpty {
            let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let names = ranked.prefix(3).compactMap { byID[$0.id]?.name.split(separator: " ").first.map(String.init) }
            let others = ranked.count - names.count
            let content = UNMutableNotificationContent()
            content.title = "Who to reach out to this week"
            content.body = Self.sentence(names: names, others: others)
            content.sound = .default
            var when = DateComponents()
            when.weekday = 1   // Sunday
            when.hour = 18
            when.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: prefix + "digest", content: content, trigger: trigger))
        }

        // Birthdays and anniversaries in the next 60 days, at 9:00 on the day.
        var upcoming: [(Contact, Artifact, Date)] = []
        for contact in contacts {
            for fact in contact.artifacts ?? [] {
                guard let date = fact.dateValue,
                      let next = Birthdays.nextOccurrence(of: date, after: now),
                      let days = Birthdays.daysUntil(date, from: now), days <= 60 else { continue }
                upcoming.append((contact, fact, next))
            }
        }
        upcoming.sort { $0.2 < $1.2 }
        for (contact, fact, day) in upcoming.prefix(maxBirthdayReminders) {
            guard let fireDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day), fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(contact.name)'s \(fact.key.lowercased()) is today"
            content.body = "A good moment to say hello."
            content.sound = .default
            content.userInfo = ["contactID": contact.id.uuidString]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + "date." + fact.id.uuidString, content: content, trigger: trigger))
        }
    }

    static func sentence(names: [String], others: Int) -> String {
        let list: String
        switch names.count {
        case 0: return "A few people could use a hello."
        case 1: list = names[0]
        case 2: list = "\(names[0]) and \(names[1])"
        default: list = "\(names[0]), \(names[1]) and \(names[2])"
        }
        if others > 0 {
            return "\(list) and \(others) other\(others == 1 ? "" : "s") could use a hello."
        }
        return "\(list) could use a hello."
    }
}
