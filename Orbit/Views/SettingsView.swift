import SwiftUI
import SwiftData
#if canImport(Contacts)
import Contacts
#endif

// MARK: - SettingsView (Power User Edition)
// Central hub for data management, export, import, and app preferences.
// Features Data Integrity checks, Spotlight rebuilding, and cascading tag renames.

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataValidator.self) private var validator
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Query private var allContacts: [Contact]
    @Query private var allInteractions: [Interaction]
    @Query private var allArtifacts: [Artifact]
    @Query private var allTags: [Tag]
    @Query private var allConstellations: [Constellation]

    // General State
    @State private var showExportSheet = false
    @State private var showImportConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    
    // Import State
    @State private var showImportPreview = false
    @State private var importableContacts: [ImportableContact] = []
    @State private var isFetchingContacts = false
    @State private var isImporting = false
    @State private var showImportResults = false
    @State private var importResultMessage = ""
    @State private var contactsAccessStatus: String = "Not checked"
    @State private var showOpenSettingsAlert = false

    // Tag Management State
    @State private var showAddTag = false
    @State private var newTagName = ""
    @State private var tagToRename: Tag?
    @State private var renameTagText = ""

    // Maintenance State
    @State private var showIntegrityResults = false
    @State private var integrityResultMessage = ""
    @State private var isReindexing = false
    
    // Appearance State
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appTint") private var appTint: AppTint = .blue

    var body: some View {
        settingsContent
            // Alert: Generic Info
            .alert("Notice", isPresented: $showImportResults) {
                Button("OK") {}
            } message: {
                Text(importResultMessage)
            }
            // Alert: Integrity Results
            .alert("Database Doctor", isPresented: $showIntegrityResults) {
                Button("Done") {}
            } message: {
                Text(integrityResultMessage)
            }
            // Alert: Delete All
            .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all contacts, interactions, artifacts, tags, and constellations. This action cannot be undone.")
            }
            // Alert: Contacts Permission
            .alert("Contacts Access Required", isPresented: $showOpenSettingsAlert) {
                Button("Open Settings") {
                    #if os(iOS)
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    #else
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") { NSWorkspace.shared.open(url) }
                    #endif
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You previously declined Contacts access. To import contacts, open Settings and enable Contacts permission for Orbit.")
            }
            // Alert: Rename Tag
            .alert("Rename Tag", isPresented: Binding(
                get: { tagToRename != nil },
                set: { if !$0 { tagToRename = nil } }
            )) {
                TextField("New name", text: $renameTagText)
                Button("Rename") {
                    if let tag = tagToRename { renameTag(tag, to: renameTagText) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will update the tag on all existing interactions across your database.")
            }
            // Sheet: Import Contacts
            .sheet(isPresented: $showImportPreview) {
                ImportPreviewSheet(
                    importableContacts: $importableContacts,
                    onImport: { selectedContacts, defaultOrbit in importSelectedContacts(selectedContacts, defaultOrbit: defaultOrbit) }
                )
            }
    }

    // MARK: - Platform-Adaptive Layout

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        TabView {
            Form { appearanceSection; dataOverviewSection; aboutSection }
                .formStyle(.grouped)
                .tabItem { Label("General", systemImage: "gear") }.tag(0)

            Form { tagRegistrySection }
                .formStyle(.grouped)
                .tabItem { Label("Tags", systemImage: "tag") }.tag(1)

            Form { exportSection; importSection }
                .formStyle(.grouped)
                .tabItem { Label("Data", systemImage: "arrow.up.arrow.down") }.tag(2)

            Form { dataManagementSection }
                .formStyle(.grouped)
                .tabItem { Label("Maintenance", systemImage: "wrench.and.screwdriver") }.tag(3)
        }
        .frame(minWidth: 500, minHeight: 400)
        #else
        Form {
            appearanceSection
            dataOverviewSection
            tagRegistrySection
            exportSection
            importSection
            dataManagementSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Data Overview

    private var dataOverviewSection: some View {
        Section {
            StatRow(label: "Contacts", value: "\(allContacts.count)")
            StatRow(label: "Interactions", value: "\(allInteractions.filter { !$0.isDeleted }.count)")
            StatRow(label: "Artifacts", value: "\(allArtifacts.count)")
            StatRow(label: "Tags", value: "\(allTags.count)")
            StatRow(label: "Constellations", value: "\(allConstellations.count)")
        } header: {
            Text("Your Database")
        } footer: {
            Text("All data is stored locally on your device and synced via your personal iCloud account. Orbit never sends your data to external servers.")
        }
    }
    
    // MARK: - Appearance

        private var appearanceSection: some View {
            Section {
                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
                
                Picker("Accent Color", selection: $appTint) {
                    ForEach(AppTint.allCases) { tint in
                        HStack {
                            Text(tint.rawValue.capitalized)
                        }
                        .tag(tint)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("Appearance")
            } footer: {
                Text("Accent color applies to buttons, highlights, and primary UI elements across Orbit.")
            }
        }

    // MARK: - Tag Registry

    private var tagRegistrySection: some View {
        Section {
            if allTags.isEmpty {
                Text("No tags yet. Tags are created when you use #tag in the command palette.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allTags) { tag in
                    HStack {
                        Text("#\(tag.name)")
                            .font(OrbitTypography.bodyMedium)
                            .foregroundStyle(OrbitColors.syntaxTag)
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(tag)
                        }
                        Button("Rename") {
                            tagToRename = tag
                            renameTagText = tag.name
                        }
                        .tint(.orange)
                    }
                }
            }

            Button {
                showAddTag = true
            } label: {
                Label("Add Tag", systemImage: "plus")
            }
        } header: {
            Text("Tag Registry")
        } footer: {
            Text("Swipe left on a tag to rename or delete it. Renaming a tag automatically updates all historical interactions that used the old name.")
        }
        .alert("New Tag", isPresented: $showAddTag) {
            TextField("Tag name", text: $newTagName)
            Button("Create") {
                let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    modelContext.insert(Tag(name: trimmed))
                    newTagName = ""
                }
            }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Button { exportJSON() } label: { Label("Export as JSON", systemImage: "curlybraces") }
            .disabled(allContacts.isEmpty || isExporting)

            Button { exportCSV() } label: { Label("Export as CSV", systemImage: "tablecells") }
            .disabled(allContacts.isEmpty || isExporting)

            if isExporting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing export…").font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Export") } footer: {
            Text("JSON includes all metadata and relationships (perfect for backups). CSV provides a flat summary for spreadsheets.")
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Button { checkContactsAccess() } label: { Label("Import from Apple Contacts", systemImage: "person.crop.rectangle.stack") }
            .disabled(isFetchingContacts || isImporting)

            if isFetchingContacts {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading contacts…").font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }
            if isImporting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Importing…").font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Import") } footer: {
            Text("Orbit detects duplicates automatically. You will be able to review the list before any data is saved.")
        }
    }

    // MARK: - Data Management (Power Tools)

    private var dataManagementSection: some View {
        Section {
            Button {
                runIntegrityCheck()
            } label: {
                Label("Run Database Doctor", systemImage: "stethoscope")
            }

            Button {
                rebuildSpotlight()
            } label: {
                HStack {
                    Label("Rebuild Spotlight Index", systemImage: "magnifyingglass")
                    if isReindexing { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(isReindexing)

            Button {
                purgeDeletedInteractions()
            } label: {
                Label("Purge Deleted Logs", systemImage: "trash.slash")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Erase All Data", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Advanced Maintenance")
        } footer: {
            Text("Database Doctor safely repairs orphaned records and stale cache data. Use Spotlight Rebuild if contacts aren't appearing in Apple system search.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0").foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Logic: Tag Rename

    private func renameTag(_ tag: Tag, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != tag.searchableName else { return }

        let oldSearchName = tag.searchableName

        // 1. Update the tag registry object
        tag.name = trimmed
        tag.searchableName = trimmed.lowercased()

        // 2. Cascade update to all interactions
        for interaction in allInteractions {
            let tags = interaction.tagList
            if tags.contains(where: { $0.lowercased() == oldSearchName }) {
                // Replace old name with new name
                let updatedTags = tags.map { $0.lowercased() == oldSearchName ? trimmed : $0 }
                interaction.tagNames = updatedTags.joined(separator: ", ")
                // Mark contact as modified to trigger sync
                interaction.contact?.modifiedAt = Date()
            }
        }
        try? modelContext.save()
    }

    // MARK: - Logic: Maintenance Actions

    private func runIntegrityCheck() {
        let issues = validator.integrityCheck(in: modelContext)
        if issues.isEmpty {
            integrityResultMessage = "Your database is perfectly healthy. No orphaned artifacts or sync issues found."
        } else {
            integrityResultMessage = "Doctor repaired \(issues.count) issues (orphaned records removed, sync dates corrected)."
        }
        try? modelContext.save()
        showIntegrityResults = true
    }

    private func rebuildSpotlight() {
        isReindexing = true
        spotlightIndexer.reindexAll(from: modelContext)
        
        // Artificial delay for UI feedback since indexing runs asynchronously
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isReindexing = false
            importResultMessage = "Spotlight index rebuilt successfully."
            showImportResults = true
        }
    }

    private func purgeDeletedInteractions() {
        let deleted = allInteractions.filter { $0.isDeleted }
        let count = deleted.count
        for interaction in deleted {
            modelContext.delete(interaction)
        }
        try? modelContext.save()
        importResultMessage = "Purged \(count) deleted interaction\(count == 1 ? "" : "s") permanently."
        showImportResults = true
    }

    private func deleteAllData() {
        try? modelContext.delete(model: Interaction.self)
        try? modelContext.delete(model: Artifact.self)
        try? modelContext.delete(model: Contact.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.delete(model: Constellation.self)
        try? modelContext.save()
        spotlightIndexer.deleteAll()
        importResultMessage = "All data has been erased."
        showImportResults = true
    }

    // MARK: - Logic: Apple Contacts Import

    private func checkContactsAccess() {
            #if canImport(Contacts)
            let status = CNContactStore.authorizationStatus(for: .contacts)
            switch status {
            case .authorized, .limited: // Handle both full and limited access here
                fetchSystemContacts()
            case .notDetermined:
                let store = CNContactStore()
                store.requestAccess(for: .contacts) { granted, _ in
                    DispatchQueue.main.async {
                        if granted {
                            self.fetchSystemContacts()
                        } else {
                            self.showOpenSettingsAlert = true
                        }
                    }
                }
            case .denied, .restricted:
                showOpenSettingsAlert = true
            @unknown default:
                break
            }
            #else
            importResultMessage = "Contacts import is not supported on this platform."
            showImportResults = true
            #endif
        }

    private func fetchSystemContacts() {
        #if canImport(Contacts)
        isFetchingContacts = true
        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactBirthdayKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            
            var fetched: [ImportableContact] = []
            
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    if !name.isEmpty {
                        var details: [String] = []
                        if !contact.organizationName.isEmpty { details.append("Company: \(contact.organizationName)") }
                        if let bday = contact.birthday, let month = bday.month, let day = bday.day {
                            details.append("Birthday: \(month)/\(day)")
                        }
                        
                        // Extract emails and phones for artifacts
                        var artifactsToCreate: [(key: String, value: String)] = []
                        for email in contact.emailAddresses {
                            artifactsToCreate.append((key: "Email", value: String(email.value)))
                        }
                        for phone in contact.phoneNumbers {
                            artifactsToCreate.append((key: "Phone", value: phone.value.stringValue))
                        }
                        if !contact.organizationName.isEmpty {
                            artifactsToCreate.append((key: "Company", value: contact.organizationName))
                        }
                        if let bday = contact.birthday, let month = bday.month, let day = bday.day {
                            artifactsToCreate.append((key: "Birthday", value: "\(month)/\(day)"))
                        }

                        let importable = ImportableContact(
                            id: UUID(),
                            name: name,
                            details: details.joined(separator: " · "),
                            artifacts: artifactsToCreate,
                            isSelected: true
                        )
                        fetched.append(importable)
                    }
                }
                
                DispatchQueue.main.async {
                    // Filter out existing
                    let existingNames = Set(self.allContacts.map { $0.searchableName })
                    self.importableContacts = fetched.filter { !existingNames.contains($0.name.lowercased()) }
                    self.isFetchingContacts = false
                    
                    if self.importableContacts.isEmpty {
                        self.importResultMessage = "No new contacts found to import. Everyone is already in Orbit!"
                        self.showImportResults = true
                    } else {
                        self.showImportPreview = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isFetchingContacts = false
                    self.importResultMessage = "Failed to read contacts: \(error.localizedDescription)"
                    self.showImportResults = true
                }
            }
        }
        #endif
    }

    private func importSelectedContacts(_ contactsToImport: [ImportableContact], defaultOrbit: Int) {
        isImporting = true
        var importedCount = 0

        for item in contactsToImport {
            let newContact = Contact(name: item.name, targetOrbit: defaultOrbit)
            modelContext.insert(newContact)
            
            for artifactData in item.artifacts {
                let artifact = Artifact(key: artifactData.key, value: artifactData.value)
                artifact.contact = newContact
                modelContext.insert(artifact)
            }
            spotlightIndexer.index(contact: newContact)
            importedCount += 1
        }

        try? modelContext.save()
        isImporting = false
        importResultMessage = "Successfully imported \(importedCount) contacts."
        showImportResults = true
    }

    // MARK: - Logic: Data Export

        private func exportJSON() {
            isExporting = true
            DispatchQueue.global(qos: .userInitiated).async {
                // Manually map the SwiftData models into JSON-compatible dictionaries
                let exportData = self.allContacts.map { contact -> [String: Any] in
                    var dict: [String: Any] = [
                        "id": contact.id.uuidString,
                        "name": contact.name,
                        "targetOrbit": contact.targetOrbit,
                        "isArchived": contact.isArchived,
                        "notes": contact.notes,
                        "createdAt": contact.createdAt.timeIntervalSince1970,
                        "modifiedAt": contact.modifiedAt.timeIntervalSince1970
                    ]
                    
                    if let lastContact = contact.lastContactDate {
                        dict["lastContactDate"] = lastContact.timeIntervalSince1970
                    }
                    
                    // Map Artifacts
                    dict["artifacts"] = contact.artifacts.map { artifact -> [String: Any] in
                        return [
                            "key": artifact.key,
                            "value": artifact.value,
                            "category": artifact.category ?? ""
                        ]
                    }
                    
                    // Map Interactions
                    dict["interactions"] = contact.interactions.map { interaction -> [String: Any] in
                        return [
                            "date": interaction.date.timeIntervalSince1970,
                            "impulse": interaction.impulse,
                            "content": interaction.content,
                            "tagNames": interaction.tagNames,
                            "isDeleted": interaction.isDeleted
                        ]
                    }
                    
                    // Map Constellations
                    dict["constellations"] = contact.constellations.map { $0.name }
                    
                    return dict
                }
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
                    self.saveDataToDisk(jsonData, filename: "Orbit_Export_\(self.formattedDate()).json")
                } catch {
                    DispatchQueue.main.async {
                        self.importResultMessage = "Failed to generate JSON: \(error.localizedDescription)"
                        self.showImportResults = true
                        self.isExporting = false
                    }
                }
            }
        }

    private func exportCSV() {
        isExporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            var csvString = "Name,Orbit,Last Contact,Tags,Notes\n"
            
            for contact in self.allContacts {
                let name = contact.name.replacingOccurrences(of: ",", with: "")
                let orbit = contact.orbitZoneName
                let lastContact = contact.lastContactDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
                let tags = contact.aggregatedTags.map { $0.name }.joined(separator: "; ")
                let notes = contact.notes.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ",", with: "")
                
                csvString += "\(name),\(orbit),\(lastContact),\(tags),\(notes)\n"
            }
            
            if let data = csvString.data(using: .utf8) {
                self.saveDataToDisk(data, filename: "Orbit_Export_\(self.formattedDate()).csv")
            }
        }
    }

    private func saveDataToDisk(_ data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            DispatchQueue.main.async {
                self.exportURL = tempURL
                self.isExporting = false
                // Note: Implement standard Share/Save sheet logic here based on your platform (UIActivityViewController / NSWorkspace)
                self.importResultMessage = "Data prepared. You can find it at: \(tempURL.path)"
                self.showImportResults = true
            }
        } catch {
            DispatchQueue.main.async {
                self.importResultMessage = "Failed to write file: \(error.localizedDescription)"
                self.showImportResults = true
                self.isExporting = false
            }
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Support Views

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Import Preview Models & Views

struct ImportableContact: Identifiable {
    let id: UUID
    let name: String
    let details: String
    let artifacts: [(key: String, value: String)]
    var isSelected: Bool
}

struct ImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var importableContacts: [ImportableContact]
    let onImport: ([ImportableContact], Int) -> Void

    @State private var defaultOrbit: Int = 3 // Standard default
    @State private var selectAll = true

    var selectedCount: Int {
        importableContacts.filter { $0.isSelected }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        Toggle("Select All", isOn: $selectAll)
                            .onChange(of: selectAll) { _, newValue in
                                for i in importableContacts.indices {
                                    importableContacts[i].isSelected = newValue
                                }
                            }
                    }

                    Section(header: Text("Found \(importableContacts.count) New Contacts")) {
                        ForEach($importableContacts) { $contact in
                            ImportContactRow(contact: $contact)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                Divider()
                importControls
            }
            .navigationTitle("Review Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var importControls: some View {
        VStack(spacing: OrbitSpacing.sm) {
            HStack {
                Text("Default Orbit Zone")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Orbit", selection: $defaultOrbit) {
                    ForEach(OrbitZone.allZones, id: \.id) { zone in
                        Text(zone.name).tag(zone.id)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Button {
                let selected = importableContacts.filter(\.isSelected)
                onImport(selected, defaultOrbit)
                dismiss()
            } label: {
                Text("Import \(selectedCount) Contact\(selectedCount == 1 ? "" : "s")")
                    .font(OrbitTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
        }
        .padding(OrbitSpacing.md)
    }
}

struct ImportContactRow: View {
    @Binding var contact: ImportableContact

    var body: some View {
        HStack {
            Toggle("", isOn: $contact.isSelected)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.bodyMedium)
                if !contact.details.isEmpty {
                    Text(contact.details)
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !contact.artifacts.isEmpty {
                HStack(spacing: 2) {
                    Text("\(contact.artifacts.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "gift")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            contact.isSelected.toggle()
        }
    }
}


// MARK: - Appearance Preferences

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppTint: String, CaseIterable, Identifiable {
    case blue, purple, orange, green, red
    var id: Self { self }
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .green: return .green
        case .red: return .red
        }
    }
}
