import SwiftUI
import SwiftData

// MARK: - TagListView
// Shows all known tags from the tag registry, with usage stats aggregated
// from interactions. Tags are NOT linked to contacts — they live on
// interactions. This view answers "what tag names exist?" and
// "which contacts have interactions with this tag?".

struct TagListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Tag.name)
    private var tags: [Tag]

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    @State private var showAddTag = false
    @State private var newTagName = ""
    @State private var selectedTag: Tag?

    /// For each tag, find contacts whose interactions use that tag name
    private func contactsUsing(tag: Tag) -> [(contact: Contact, count: Int)] {
        contacts.compactMap { contact in
            let match = contact.aggregatedTags.first(where: { $0.name == tag.searchableName })
            guard let match else { return nil }
            return (contact: contact, count: match.count)
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Tags are created when you use #tag in the command palette.")
                )
            } else {
                List(selection: $selectedTag) {
                    ForEach(tags) { tag in
                        let usage = contactsUsing(tag: tag)
                        let totalUses = usage.reduce(0) { $0 + $1.count }

                        HStack {
                            Text("#\(tag.name)")
                                .font(OrbitTypography.bodyMedium)
                                .foregroundStyle(OrbitColors.syntaxTag)

                            Spacer()

                            if !usage.isEmpty {
                                Text("\(usage.count) contact\(usage.count == 1 ? "" : "s") · \(totalUses) use\(totalUses == 1 ? "" : "s")")
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Unused")
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tag(tag)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                modelContext.delete(tag)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAddTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Tag", isPresented: $showAddTag) {
            TextField("Tag name", text: $newTagName)
            Button("Create") {
                let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let tag = Tag(name: trimmed)
                    modelContext.insert(tag)
                    newTagName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newTagName = ""
            }
        }
        .sheet(item: $selectedTag) { tag in
            TagDetailSheet(tag: tag, contacts: contacts)
        }
    }
}

// MARK: - Tag Detail Sheet
// Shows which contacts have interactions tagged with this tag,
// sorted by frequency.

struct TagDetailSheet: View {
    let tag: Tag
    let contacts: [Contact]

    private var taggedContacts: [(contact: Contact, count: Int)] {
        contacts.compactMap { contact in
            let match = contact.aggregatedTags.first(where: { $0.name == tag.searchableName })
            guard let match else { return nil }
            return (contact: contact, count: match.count)
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Contacts with #\(tag.name) interactions") {
                    if taggedContacts.isEmpty {
                        Text("No contacts have interactions tagged #\(tag.name).")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(taggedContacts, id: \.contact.id) { item in
                            HStack {
                                Text(item.contact.name)
                                    .font(OrbitTypography.contactName(orbit: item.contact.targetOrbit))
                                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: item.contact.daysSinceLastContact))

                                Spacer()

                                Text("×\(item.count)")
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(OrbitColors.syntaxTag)

                                Text(item.contact.orbitZoneName)
                                    .font(OrbitTypography.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("#\(tag.name)")
        }
    }
}
