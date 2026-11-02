import Foundation
import SwiftData
import SwiftUI

// MARK: - OrbitStore
// The one place that writes to the database. Every screen — palette, log
// composer, Today, People, contact and group pages, batch edit — calls these
// methods instead of inserting models and saving on its own.
//
// Each write:
//   1. mutates models
//   2. refreshes the affected contacts' cached fields + Spotlight entries
//   3. saves (errors surface as a toast instead of being swallowed)
//   4. registers an undo step and shows a toast with an Undo button
//
// Undo is an explicit stack of revert closures rather than SwiftData's
// UndoManager, so it covers soft deletes, cached fields and Spotlight, and
// behaves the same on every platform. Hard deletes (contacts, groups, facts)
// clear older history, because older steps may reference deleted objects.

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let canUndo: Bool
    let isError: Bool
}

enum ContactResolution: Equatable {
    case resolved(Contact)
    case ambiguous([Contact])
    case notFound(String)

    static func == (lhs: ContactResolution, rhs: ContactResolution) -> Bool {
        switch (lhs, rhs) {
        case let (.resolved(a), .resolved(b)): return a.id == b.id
        case let (.ambiguous(a), .ambiguous(b)): return a.map(\.id) == b.map(\.id)
        case let (.notFound(a), .notFound(b)): return a == b
        default: return false
        }
    }
}

enum GroupResolution: Equatable {
    case resolved(Constellation)
    case ambiguous([Constellation])
    case notFound(String)

    static func == (lhs: GroupResolution, rhs: GroupResolution) -> Bool {
        switch (lhs, rhs) {
        case let (.resolved(a), .resolved(b)): return a.id == b.id
        case let (.ambiguous(a), .ambiguous(b)): return a.map(\.id) == b.map(\.id)
        case let (.notFound(a), .notFound(b)): return a == b
        default: return false
        }
    }
}

@Observable
final class OrbitStore {

    let context: ModelContext
    let spotlight: SpotlightIndexer

    /// The toast currently on screen (ContentView renders it).
    private(set) var toast: ToastMessage?

    private struct UndoStep {
        let label: String
        let contacts: [Contact]
        let revert: () -> Void
    }

    private var undoStack: [UndoStep] = []
    private let undoLimit = 30
    private var groupDepth = 0
    private var toastTask: Task<Void, Never>?
    private var cachedActionSuggestions: [String]?

    var canUndo: Bool { !undoStack.isEmpty }
    var undoLabel: String? { undoStack.last?.label }

    init(context: ModelContext, spotlight: SpotlightIndexer) {
        self.context = context
        self.spotlight = spotlight
    }

    // MARK: - Undo

    /// Undo the most recent change. Returns false when there is nothing to undo.
    @discardableResult
    func undo() -> Bool {
        guard let step = undoStack.popLast() else {
            show("Nothing to undo", canUndo: false)
            return false
        }
        step.revert()
        refresh(step.contacts)
        save("undo")
        cachedActionSuggestions = nil
        show("Undid \(step.label.lowercased())", canUndo: false)
        return true
    }

    /// Run several store calls as one undo step and one toast.
    func grouped(_ label: String, message: String, _ body: () -> Void) {
        let before = undoStack.count
        groupDepth += 1
        body()
        groupDepth -= 1
        let added = Array(undoStack[min(before, undoStack.count)...])
        undoStack.removeLast(added.count)
        guard !added.isEmpty else { return }
        let contacts = added.flatMap(\.contacts)
        push(UndoStep(label: label, contacts: contacts) {
            for step in added.reversed() { step.revert() }
        })
        if groupDepth == 0 { show(message, canUndo: true) }
    }

    /// Forget all undo steps. Call after bulk operations that delete or
    /// replace data outside the store (erase all, JSON replace, purge).
    func clearUndoHistory() {
        undoStack.removeAll()
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    // MARK: - Resolution

    func activeContacts(includeArchived: Bool = false) -> [Contact] {
        let descriptor: FetchDescriptor<Contact>
        if includeArchived {
            descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\.name)])
        } else {
            descriptor = FetchDescriptor<Contact>(predicate: #Predicate<Contact> { !$0.isArchived }, sortBy: [SortDescriptor(\.name)])
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func allGroups() -> [Constellation] {
        (try? context.fetch(FetchDescriptor<Constellation>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func resolveContact(_ name: String, includeArchived: Bool = false) -> ContactResolution {
        let contacts = activeContacts(includeArchived: includeArchived)
        let candidates = contacts.map { NameCandidate(id: $0.id, name: $0.name) }
        switch NameMatcher.match(name, in: candidates) {
        case .unique(let id):
            return contacts.first(where: { $0.id == id }).map(ContactResolution.resolved) ?? .notFound(name)
        case .ambiguous(let ids):
            return .ambiguous(contacts.filter { ids.contains($0.id) })
        case .none:
            return .notFound(name)
        }
    }

    func resolveGroup(_ name: String) -> GroupResolution {
        let groups = allGroups()
        let candidates = groups.map { NameCandidate(id: $0.id, name: $0.name) }
        switch NameMatcher.match(name, in: candidates) {
        case .unique(let id):
            return groups.first(where: { $0.id == id }).map(GroupResolution.resolved) ?? .notFound(name)
        case .ambiguous(let ids):
            return .ambiguous(groups.filter { ids.contains($0.id) })
        case .none:
            return .notFound(name)
        }
    }

    // MARK: - Vocabulary

    /// Actions for pickers: the user's own most-used first, then defaults.
    func actionSuggestions(limit: Int = 8) -> [String] {
        if let cached = cachedActionSuggestions { return Array(cached.prefix(limit)) }
        var descriptor = FetchDescriptor<Interaction>(
            predicate: #Predicate<Interaction> { !$0.isDeleted },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        let history = ((try? context.fetch(descriptor)) ?? []).map(\.impulse)
        let suggestions = ActionVocabulary.suggestions(history: history, limit: 16)
        cachedActionSuggestions = suggestions
        return Array(suggestions.prefix(limit))
    }

    func knownActions() -> [String] { actionSuggestions(limit: 16) }

    func tagNames() -> [String] {
        ((try? context.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)]))) ?? []).map(\.name)
    }

    // MARK: - Interactions

    /// Log one real-world event with one or more people.
    @discardableResult
    func log(contacts: [Contact], action rawAction: String, note: String = "", tags: [String] = [], date: Date = Date(), groupName: String? = nil) -> [Interaction] {
        let action = ActionVocabulary.canonical(rawAction, known: knownActions())
        let people = uniqued(contacts)
        guard !action.isEmpty, !people.isEmpty else { return [] }

        let batchID = people.count > 1 ? UUID() : nil
        var created: [Interaction] = []
        for contact in people {
            let interaction = Interaction(impulse: action, content: note.trimmingCharacters(in: .whitespacesAndNewlines), date: min(date, Date()), batchID: batchID)
            interaction.setTags(tags)
            interaction.contact = contact
            context.insert(interaction)
            created.append(interaction)
        }
        TagRegistry.ensureTagsExist(named: created.first?.tagList ?? [], in: context)
        cachedActionSuggestions = nil

        let who = groupName.map { "✦ \($0)" } ?? names(people)
        let when = Calendar.current.isDateInToday(date) ? "" : " · \(date.formatted(date: .abbreviated, time: .omitted))"
        commit("Log \(action)", message: "Logged \(action) with \(who)\(when)", contacts: people) {
            for i in created { i.isDeleted = true }
        }
        return created
    }

    func update(_ interaction: Interaction, action rawAction: String, note: String, tags: [String], date: Date, applyToBatch: Bool) {
        let targets = applyToBatch ? batchSiblings(of: interaction) : [interaction]
        let snapshots = targets.map { ($0, $0.impulse, $0.content, $0.tagNames, $0.date) }
        let action = ActionVocabulary.canonical(rawAction, known: knownActions())

        for i in targets {
            i.impulse = action
            i.content = note.trimmingCharacters(in: .whitespacesAndNewlines)
            i.setTags(tags)
            i.date = date
        }
        TagRegistry.ensureTagsExist(named: interaction.tagList, in: context)
        cachedActionSuggestions = nil

        commit("Edit", message: "Saved", contacts: targets.compactMap(\.contact)) {
            for (i, impulse, content, tagNames, date) in snapshots {
                i.impulse = impulse; i.content = content; i.tagNames = tagNames; i.date = date
            }
        }
    }

    func delete(_ interaction: Interaction, includeBatch: Bool) {
        let targets = includeBatch ? batchSiblings(of: interaction) : [interaction]
        for i in targets { i.isDeleted = true }
        let label = targets.count > 1 ? "Delete \(targets.count) logs" : "Delete log"
        commit(label, message: targets.count > 1 ? "Deleted \(targets.count) logs" : "Deleted \(interaction.impulse)", contacts: targets.compactMap(\.contact)) {
            for i in targets { i.isDeleted = false }
        }
    }

    func delete(_ interactions: [Interaction]) {
        guard !interactions.isEmpty else { return }
        for i in interactions { i.isDeleted = true }
        commit("Delete \(interactions.count) logs", message: "Deleted \(interactions.count) log\(interactions.count == 1 ? "" : "s")", contacts: interactions.compactMap(\.contact)) {
            for i in interactions { i.isDeleted = false }
        }
    }

    /// Replace tags on many interactions at once (Activity batch edit).
    func setTags(_ tags: [String], on interactions: [Interaction], mode: TagEditMode) {
        let snapshots = interactions.map { ($0, $0.tagNames) }
        for i in interactions {
            switch mode {
            case .add: i.setTags(i.tagList + tags)
            case .remove:
                let remove = Set(tags.map { $0.lowercased() })
                i.setTags(i.tagList.filter { !remove.contains($0.lowercased()) })
            case .replace: i.setTags(tags)
            }
        }
        TagRegistry.ensureTagsExist(named: tags.map { $0.lowercased() }, in: context)
        commit("Edit tags", message: "Updated tags on \(interactions.count) log\(interactions.count == 1 ? "" : "s")", contacts: interactions.compactMap(\.contact)) {
            for (i, tags) in snapshots { i.tagNames = tags }
        }
    }

    enum TagEditMode { case add, remove, replace }

    func batchSiblings(of interaction: Interaction) -> [Interaction] {
        guard let batchID = interaction.batchID else { return [interaction] }
        let descriptor = FetchDescriptor<Interaction>(predicate: #Predicate<Interaction> { $0.batchID == batchID })
        let siblings = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
        return siblings.isEmpty ? [interaction] : siblings
    }

    // MARK: - Contacts

    @discardableResult
    func createContact(name: String, orbit: Int = 2, notes: String = "", closenessConfirmed: Bool) -> Contact {
        let contact = Contact(name: name.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, targetOrbit: orbit, closenessConfirmed: closenessConfirmed)
        context.insert(contact)
        commit("Add \(contact.name)", message: "Added \(contact.name)", contacts: [contact]) { [weak self] in
            self?.spotlight.deindex(contact: contact)
            self?.context.delete(contact)
        }
        return contact
    }

    func updateContact(_ contact: Contact, name: String, notes: String, orbit: Int) {
        let old = (contact.name, contact.notes, contact.targetOrbit, contact.closenessConfirmed)
        contact.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.updateSearchableName()
        contact.notes = notes
        contact.targetOrbit = orbit
        contact.closenessConfirmed = true
        commit("Edit \(contact.name)", message: "Saved \(contact.name)", contacts: [contact]) {
            contact.name = old.0
            contact.updateSearchableName()
            contact.notes = old.1
            contact.targetOrbit = old.2
            contact.closenessConfirmed = old.3
        }
    }

    /// Set closeness for one or more people and mark it as confirmed.
    func setCloseness(_ orbit: Int, for contacts: [Contact]) {
        let people = uniqued(contacts)
        guard !people.isEmpty else { return }
        let old = people.map { ($0, $0.targetOrbit, $0.closenessConfirmed) }
        for c in people {
            c.targetOrbit = orbit
            c.closenessConfirmed = true
        }
        commit("Change closeness", message: "\(names(people)) → \(OrbitZone.name(for: orbit))", contacts: people) {
            for (c, orbit, confirmed) in old { c.targetOrbit = orbit; c.closenessConfirmed = confirmed }
        }
    }

    func setArchived(_ archived: Bool, for contacts: [Contact]) {
        let people = uniqued(contacts)
        guard !people.isEmpty else { return }
        let old = people.map { ($0, $0.isArchived) }
        for c in people { c.isArchived = archived }
        commit(archived ? "Archive" : "Restore", message: "\(names(people)) \(archived ? "archived" : "restored")", contacts: people) {
            for (c, value) in old { c.isArchived = value }
        }
    }

    /// Hide from Today until `until` (nil clears the snooze).
    func snooze(_ contacts: [Contact], until: Date?) {
        let people = uniqued(contacts)
        guard !people.isEmpty else { return }
        let old = people.map { ($0, $0.snoozedUntil) }
        for c in people { c.snoozedUntil = until }
        let message: String
        if let until {
            message = "Snoozed \(names(people)) until \(until.formatted(.dateTime.day().month(.abbreviated)))"
        } else {
            message = "Unsnoozed \(names(people))"
        }
        commit("Snooze", message: message, contacts: people) {
            for (c, value) in old { c.snoozedUntil = value }
        }
    }

    /// Permanent. Clears undo history because older steps may reference these contacts.
    func deleteContacts(_ contacts: [Contact]) {
        let people = uniqued(contacts)
        guard !people.isEmpty else { return }
        let label = names(people)
        for c in people {
            spotlight.deindex(contact: c)
            context.delete(c)
        }
        undoStack.removeAll()
        save("delete contacts")
        show("Deleted \(label)", canUndo: false)
    }

    // MARK: - Facts

    struct FactSnapshot {
        let key: String
        let value: String
        let isArray: Bool
        let category: String?

        init(_ a: Artifact) { key = a.key; value = a.value; isArray = a.isArray; category = a.category }

        func apply(to a: Artifact) {
            a.key = key
            a.searchableKey = key.lowercased()
            a.value = value
            a.isArray = isArray
            a.category = category
            a.modifiedAt = Date()
        }
    }

    enum FactChange {
        case set(String)
        case append(String)
        case remove(String)
    }

    /// Outcome for the palette: `.needsListConversion` means the fact holds a
    /// single value and the user should confirm turning it into a list.
    enum FactResult { case done, needsListConversion }

    @discardableResult
    func changeFact(_ rawKey: String, _ change: FactChange, for contacts: [Contact], convertToList: Bool = false) -> FactResult {
        let people = uniqued(contacts)
        let (category, key) = Self.parseCategoryAndKey(rawKey)
        guard !key.isEmpty, !people.isEmpty else { return .done }

        if case .append = change, !convertToList {
            let needsConversion = people.contains { c in
                guard let existing = fact(key, on: c) else { return false }
                return !existing.isArray && !existing.value.isEmpty
            }
            if needsConversion { return .needsListConversion }
        }

        var restores: [(Artifact, FactSnapshot)] = []
        var created: [Artifact] = []

        for c in people {
            let existing = fact(key, on: c)
            if let existing { restores.append((existing, FactSnapshot(existing))) }

            switch change {
            case .set(let value):
                if let existing {
                    existing.setValue(value)
                    if let category { existing.category = category }
                } else {
                    let a = Artifact(key: key, value: value, category: category)
                    a.contact = c
                    context.insert(a)
                    created.append(a)
                }
            case .append(let value):
                if let existing {
                    existing.appendValue(value)
                    if let category { existing.category = category }
                } else {
                    let a = Artifact(key: key, value: "", isArray: true, category: category)
                    a.contact = c
                    context.insert(a)
                    a.appendValue(value)
                    created.append(a)
                }
            case .remove(let value):
                existing?.removeValue(value)
            }
        }

        let message: String
        switch change {
        case .set(let v): message = "\(key): \(v) for \(names(people))"
        case .append(let v): message = "Added \(v) to \(key) for \(names(people))"
        case .remove(let v): message = "Removed \(v) from \(key) for \(names(people))"
        }
        commit("Edit \(key)", message: message, contacts: people) { [weak self] in
            for (a, snap) in restores { snap.apply(to: a) }
            for a in created { self?.context.delete(a) }
        }
        return .done
    }

    /// Save a fact from the edit sheet. `existing == nil` creates one.
    func saveFact(on contact: Contact, existing: Artifact?, key rawKey: String, category: String?, values: [String], asList: Bool) {
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let cleanValues = values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let existing {
            let snap = FactSnapshot(existing)
            existing.key = key
            existing.searchableKey = key.lowercased()
            existing.category = category
            if asList {
                existing.isArray = true
                existing.value = Self.encodeList(cleanValues)
            } else {
                existing.setValue(cleanValues.first ?? "")
            }
            existing.modifiedAt = Date()
            commit("Edit \(key)", message: "Saved \(key)", contacts: [contact]) { snap.apply(to: existing) }
        } else {
            let a = Artifact(key: key, value: asList ? Self.encodeList(cleanValues) : (cleanValues.first ?? ""), isArray: asList, category: category)
            a.contact = contact
            context.insert(a)
            commit("Add \(key)", message: "Added \(key) for \(contact.name)", contacts: [contact]) { [weak self] in
                self?.context.delete(a)
            }
        }
    }

    /// Delete facts. Undo re-creates them.
    func deleteFacts(_ facts: [Artifact]) {
        guard !facts.isEmpty else { return }
        let snapshots = facts.map { ($0.contact, FactSnapshot($0)) }
        let contacts = uniqued(facts.compactMap(\.contact))
        for a in facts { context.delete(a) }
        undoStack.removeAll()
        commit(facts.count == 1 ? "Delete \(facts[0].key)" : "Delete facts", message: facts.count == 1 ? "Deleted \(snapshots[0].1.key)" : "Deleted \(facts.count) facts", contacts: contacts) { [weak self] in
            guard let self else { return }
            for (contact, snap) in snapshots {
                guard let contact else { continue }
                let a = Artifact(key: snap.key, value: snap.value, isArray: snap.isArray, category: snap.category)
                a.contact = contact
                self.context.insert(a)
            }
        }
    }

    func deleteFact(_ rawKey: String, for contacts: [Contact]) {
        let (_, key) = Self.parseCategoryAndKey(rawKey)
        deleteFacts(uniqued(contacts).compactMap { fact(key, on: $0) })
    }

    func fact(_ key: String, on contact: Contact) -> Artifact? {
        let k = key.lowercased()
        return contact.artifacts?.first(where: { $0.searchableKey == k })
    }

    static func parseCategoryAndKey(_ rawKey: String) -> (category: String?, key: String) {
        let components = rawKey.split(separator: "/", maxSplits: 1)
        if components.count == 2 {
            return (String(components[0]).trimmingCharacters(in: .whitespaces),
                    String(components[1]).trimmingCharacters(in: .whitespaces))
        }
        return (nil, rawKey.trimmingCharacters(in: .whitespaces))
    }

    private static func encodeList(_ values: [String]) -> String {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // MARK: - Groups

    @discardableResult
    func addToGroup(_ contacts: [Contact], groupName: String) -> Constellation {
        var createdGroup: Constellation?
        let group: Constellation
        switch resolveGroup(groupName) {
        case .resolved(let g): group = g
        default:
            let exact = allGroups().first { $0.searchableName == groupName.lowercased() }
            if let exact { group = exact } else {
                let g = Constellation(name: groupName.trimmingCharacters(in: .whitespaces))
                context.insert(g)
                createdGroup = g
                group = g
            }
        }
        return addToGroup(contacts, group: group, created: createdGroup)
    }

    @discardableResult
    func addToGroup(_ contacts: [Contact], group: Constellation, created: Constellation? = nil) -> Constellation {
        let people = uniqued(contacts)
        var added: [Contact] = []
        for c in people where !(c.constellations ?? []).contains(where: { $0.id == group.id }) {
            if c.constellations == nil { c.constellations = [] }
            c.constellations?.append(group)
            added.append(c)
        }
        commit("Add to \(group.name)", message: "Added \(names(people)) to ✦ \(group.name)", contacts: people) { [weak self] in
            for c in added { c.constellations?.removeAll { $0.id == group.id } }
            if let created { self?.context.delete(created) }
        }
        return group
    }

    func removeFromGroup(_ contacts: [Contact], group: Constellation) {
        let people = uniqued(contacts)
        var removed: [Contact] = []
        for c in people where (c.constellations ?? []).contains(where: { $0.id == group.id }) {
            c.constellations?.removeAll { $0.id == group.id }
            removed.append(c)
        }
        commit("Remove from \(group.name)", message: "Removed \(names(people)) from ✦ \(group.name)", contacts: people) {
            for c in removed {
                if c.constellations == nil { c.constellations = [] }
                c.constellations?.append(group)
            }
        }
    }

    /// Permanent. Members are kept; only the group goes. Clears undo history.
    func deleteGroup(_ group: Constellation) {
        let name = group.name
        let members = group.contacts ?? []
        context.delete(group)
        undoStack.removeAll()
        refresh(members)
        save("delete group")
        show("Deleted ✦ \(name)", canUndo: false)
    }

    /// Log for every active member of a group.
    @discardableResult
    func log(group: Constellation, action: String, note: String = "", tags: [String] = [], date: Date = Date()) -> [Interaction] {
        let members = (group.contacts ?? []).filter { !$0.isArchived }
        guard !members.isEmpty else {
            show("✦ \(group.name) has no active members", canUndo: false, isError: true)
            return []
        }
        return log(contacts: members, action: action, note: note, tags: tags, date: date, groupName: group.name)
    }

    // MARK: - Commit

    private func commit(_ label: String, message: String, contacts: [Contact], revert: @escaping () -> Void) {
        let people = uniqued(contacts)
        refresh(people)
        let saved = save(label)
        push(UndoStep(label: label, contacts: people, revert: revert))
        if groupDepth == 0 && saved { show(message, canUndo: true) }
    }

    private func push(_ step: UndoStep) {
        undoStack.append(step)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
    }

    /// Recompute cached fields and Spotlight entries for these contacts.
    func refresh(_ contacts: [Contact]) {
        for c in contacts where c.modelContext != nil && !c.isDeleted {
            c.refreshCachedFields()
            c.refreshArtifactCache()
            if c.isArchived { spotlight.deindex(contact: c) } else { spotlight.index(contact: c) }
        }
    }

    @discardableResult
    func save(_ operation: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            print("⚠️ Save failed [\(operation)]: \(error.localizedDescription)")
            show("Couldn't save — \(error.localizedDescription)", canUndo: false, isError: true)
            return false
        }
    }

    func show(_ text: String, canUndo: Bool, isError: Bool = false) {
        toastTask?.cancel()
        let message = ToastMessage(text: text, canUndo: canUndo, isError: isError)
        toast = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(canUndo ? 6 : 3))
            guard !Task.isCancelled, self?.toast?.id == message.id else { return }
            self?.toast = nil
        }
    }

    // MARK: - Helpers

    private func uniqued(_ contacts: [Contact]) -> [Contact] {
        var seen = Set<UUID>()
        return contacts.filter { seen.insert($0.id).inserted }
    }

    func names(_ contacts: [Contact]) -> String {
        switch contacts.count {
        case 0: return "nobody"
        case 1: return contacts[0].name
        case 2: return "\(contacts[0].name) and \(contacts[1].name)"
        default: return "\(contacts.count) people"
        }
    }
}
