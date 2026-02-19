import SwiftUI
import SwiftData

// MARK: - TagListView
// Displays all tags and the contacts associated with each.
// Tags are created automatically when used in the command palette (#tag),
// but can also be managed here.

struct TagListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Tag.name)
    private var tags: [Tag]

    @State private var showAddTag = false
    @State private var newTagName = ""
    @State private var selectedTag: Tag?

    var body: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Tags are created when you use #tag in the command palette, or you can create them here.")
                )
            } else {
                List(selection: $selectedTag) {
                    ForEach(tags) { tag in
                        HStack {
                            Text("#\(tag.name)")
                                .font(OrbitTypography.bodyMedium)
                                .foregroundStyle(OrbitColors.syntaxTag)

                            Spacer()

                            Text("\(tag.contacts.count)")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
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
            TagDetailSheet(tag: tag)
        }
    }
}

// MARK: - Tag Detail Sheet

struct TagDetailSheet: View {
    @Bindable var tag: Tag

    var body: some View {
        NavigationStack {
            List {
                Section("Contacts tagged #\(tag.name)") {
                    if tag.contacts.isEmpty {
                        Text("No contacts with this tag yet.")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tag.contacts.sorted(by: { $0.name < $1.name })) { contact in
                            HStack {
                                Text(contact.name)
                                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))
                                Spacer()
                                Text(contact.orbitZoneName)
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
