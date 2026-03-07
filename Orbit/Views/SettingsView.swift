import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(Contacts)
import Contacts
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataValidator.self) private var validator
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    // Only keep @Query for data that's needed reactively
    @Query private var allContacts: [Contact]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    // Lazy stats — computed once on appear, not live-updated
    @State private var stats = DataStats()

    // General State
    @State private var showImportConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false

    // File Exporter State
    @State private var showExporter = false
    @State private var exportContentType: UTType = .json
    @State private var exportDocument: ExportDocument?
    @State private var exportFilename: String = ""
    
    // Import State
    @State private var showImportPreview = false
    @State private var importableContacts: [ImportableContact] = []
    @State private var isFetchingContacts = false
    @State private var isImporting = false
    @State private var showImportResults = false
    @State private var importResultMessage = ""
    @State private var contactsAccessStatus: String = "Not checked"
    @State private var showOpenSettingsAlert = false

    // JSON Backup Import State
    @State private var showJSONImporter = false
    @State private var showJSONImportConfirmation = false
    @State private var pendingJSONImportURL: URL?
    @State private var jsonImportPreviewMessage = ""
    @State private var isImportingJSON = false

    // Tag Management State
    @State private var showAddTag = false
    @State private var newTagName = ""

    // Theme
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appTint") private var appTint: AppTint = .blue

    // Tutorial & Sample Data
    @State private var showTutorial = false
    @State private var showSampleDataConfirmation = false
    @State private var showClearSampleDataConfirmation = false
    @AppStorage("hasSampleData") private var hasSampleData = false
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    // Maintenance
    @State private var showIntegrityResults = false
    @State private var integrityResultMessage = ""
    @State private var isReindexing = false

    struct DataStats {
        var contactCount: Int = 0
        var interactionCount: Int = 0
        var artifactCount: Int = 0
        var tagCount: Int = 0
        var constellationCount: Int = 0
        var archivedCount: Int = 0
        var deletedInteractionCount: Int = 0
    }

    var body: some View {
        NavigationStack {
            Form {
                gettingStartedSection
                statsSection
                tagSection
                exportSection
                importSection
                appearanceSection
                maintenanceSection
                dangerZoneSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(maxWidth: 700)
            #endif
        }
        .onAppear {
            fetchStats()
        }
        .alert("Done", isPresented: $showImportResults) {
            Button("OK") {}
        } message: {
            Text(importResultMessage)
        }
        .alert("Database Health", isPresented: $showIntegrityResults) {
            Button("OK") {}
        } message: {
            Text(integrityResultMessage)
        }
        // Erase all data confirmation
        .confirmationDialog("Erase All Data?", isPresented: $showDeleteConfirmation) {
            Button("Erase Everything", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all contacts, interactions, artifacts, tags, and constellations. This cannot be undone.")
        }
        // Sample data confirmation
        .confirmationDialog("Load Sample Data?", isPresented: $showSampleDataConfirmation) {
            Button("Load Sample Data") {
                loadSampleData()
            }
        } message: {
            Text("This will add 8 sample contacts with interactions, artifacts, and constellations so you can explore every feature. You can clear it later from Settings.")
        }
        // Clear sample data confirmation
        .confirmationDialog("Clear Sample Data?", isPresented: $showClearSampleDataConfirmation) {
            Button("Erase All Data", role: .destructive) {
                deleteAllData()
                hasSampleData = false
            }
        } message: {
            Text("This will erase all data (including any contacts you've added). You can reload sample data afterwards if needed.")
        }
        // JSON backup import confirmation
        .confirmationDialog("Import JSON Backup?", isPresented: $showJSONImportConfirmation) {
            Button("Merge Into Existing Data") {
                if let url = pendingJSONImportURL {
                    performJSONImport(from: url, clearFirst: false)
                }
            }
            Button("Replace All Data", role: .destructive) {
                if let url = pendingJSONImportURL {
                    performJSONImport(from: url, clearFirst: true)
                }
            }
        } message: {
            Text(jsonImportPreviewMessage)
        }
        .fileExporter(
            isPresented: $showExporter, // Using the new unified boolean
            document: exportDocument,
            contentType: exportContentType, // Dynamically swaps between .json and .commaSeparatedText
            defaultFilename: exportFilename
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $showJSONImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleJSONImportSelection(result)
        }
        .sheet(isPresented: $showImportPreview) {
            ImportPreviewSheet(
                importableContacts: $importableContacts,
                onImport: importSelectedContacts
            )
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView()
        }
    }

    // MARK: - Fetch Stats (On-Demand)

    /// Fetch lightweight counts instead of loading entire tables.
    private func fetchStats() {
        // Contact count (use the @Query we already have)
        stats.contactCount = allContacts.count
        stats.archivedCount = allContacts.filter { $0.isArchived }.count

        // Interaction count — fetch count only, not full objects
        let interactionDescriptor = FetchDescriptor<Interaction>()
        stats.interactionCount = (try? modelContext.fetchCount(interactionDescriptor)) ?? 0

        let deletedPredicate = #Predicate<Interaction> { $0.isDeleted }
        let deletedDescriptor = FetchDescriptor<Interaction>(predicate: deletedPredicate)
        stats.deletedInteractionCount = (try? modelContext.fetchCount(deletedDescriptor)) ?? 0

        // Artifact count
        let artifactDescriptor = FetchDescriptor<Artifact>()
        stats.artifactCount = (try? modelContext.fetchCount(artifactDescriptor)) ?? 0

        // Tag and constellation counts
        stats.tagCount = allTags.count

        let constellationDescriptor = FetchDescriptor<Constellation>()
        stats.constellationCount = (try? modelContext.fetchCount(constellationDescriptor)) ?? 0
    }

    // MARK: - Getting Started Section

    private var gettingStartedSection: some View {
        Section {
            Button {
                showTutorial = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How to Use Orbit")
                        Text("Learn the command palette syntax and features")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "book")
                }
            }

            if !hasSampleData && stats.contactCount == 0 {
                Button {
                    showSampleDataConfirmation = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Load Sample Data")
                            Text("Explore with 8 contacts, interactions, and groups")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }
            }

            if hasSampleData {
                Button(role: .destructive) {
                    showClearSampleDataConfirmation = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Sample Data")
                            Text("Remove all sample contacts to start fresh")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "xmark.bin")
                    }
                }
            }
        } header: {
            Text("Getting Started")
        } footer: {
            if !hasSeenTutorial {
                Text("New to Orbit? Start with the tutorial to learn how the command palette works.")
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        Section {
            StatRow(label: "Contacts", value: "\(stats.contactCount)")
            StatRow(label: "Interactions", value: "\(stats.interactionCount)")
            StatRow(label: "Artifacts", value: "\(stats.artifactCount)")
            StatRow(label: "Tags", value: "\(stats.tagCount)")
            StatRow(label: "Constellations", value: "\(stats.constellationCount)")
            if stats.archivedCount > 0 {
                StatRow(label: "Archived", value: "\(stats.archivedCount)")
            }
            if stats.deletedInteractionCount > 0 {
                StatRow(label: "Soft-Deleted Logs", value: "\(stats.deletedInteractionCount)")
            }
        } header: {
            Text("Database")
        }
    }

    // MARK: - Tag Section
    // Uses @Query allTags which is still needed for the interactive list

    private var tagSection: some View {
        Section {
            ForEach(allTags) { tag in
                HStack {
                    Text("#\(tag.name)")
                        .font(OrbitTypography.body)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        modelContext.delete(tag)
                        PersistenceHelper.saveWithLogging(modelContext, operation: "delete tag")
                    }
                }
            }

            if allTags.isEmpty {
                Text("No tags yet. Tags are created when you use #tag in the command palette.")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text("Tag Registry (\(allTags.count))")
        } footer: {
            Text("Tags live on interactions. This registry is for autocomplete suggestions. Swipe to delete unused tags.")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                exportJSON()
            } label: {
                Label("Export JSON Backup", systemImage: "arrow.up.doc")
            }
            .disabled(isExporting || stats.contactCount == 0)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV Summary", systemImage: "tablecells")
            }
            .disabled(isExporting || stats.contactCount == 0)
        } header: {
            Text("Backup & Export")
        } footer: {
            Text("JSON backup includes all data and can be imported back. CSV provides a flat summary of contacts for spreadsheets.")
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section {
            Button {
                showJSONImporter = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import JSON Backup")
                        if isImportingJSON {
                            Text("Importing...")
                                .font(OrbitTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    if isImportingJSON {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.doc")
                    }
                }
            }
            .disabled(isImportingJSON)

            Button {
                checkContactsAccess()
            } label: {
                Label("Import from Apple Contacts", systemImage: "person.crop.rectangle.stack")
            }
            .disabled(isFetchingContacts || isImporting)

            if isFetchingContacts {
                HStack {
                    ProgressView()
                    Text("Reading contacts...").font(OrbitTypography.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Import")
        } footer: {
            Text("JSON import restores a previous backup. Apple Contacts import brings in names and basic info — duplicates are skipped.")
        }
        .alert("Contacts Access Required", isPresented: $showOpenSettingsAlert) {
            Button("Open Settings") {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Orbit needs access to your contacts to import them. Please enable access in Settings.")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }

            Picker("Accent Color", selection: $appTint) {
                ForEach(AppTint.allCases, id: \.self) { tint in
                    Text(tint.rawValue).tag(tint)
                }
            }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Maintenance Section

    private var maintenanceSection: some View {
        Section {
            Button {
                runIntegrityCheck()
            } label: {
                Label("Database Doctor", systemImage: "stethoscope")
            }

            Button {
                rebuildSpotlight()
            } label: {
                HStack {
                    Label("Rebuild Spotlight Index", systemImage: "magnifyingglass")
                    if isReindexing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isReindexing)

            Button {
                purgeDeletedInteractions()
            } label: {
                Label("Purge Deleted Logs", systemImage: "trash.slash")
            }
            .disabled(stats.deletedInteractionCount == 0)
        } header: {
            Text("Maintenance")
        } footer: {
            Text("Database Doctor repairs orphaned records and stale caches. Spotlight Rebuild fixes system search. Purge permanently removes soft-deleted interactions.")
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Erase All Data", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Permanently deletes everything. Consider exporting a JSON backup first.")
        }
    }

    // MARK: - About Section

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

    // MARK: - Logic: Sample Data

    private func loadSampleData() {
        let result = SampleDataGenerator.generate(in: modelContext)
        hasSampleData = true
        hasSeenTutorial = true
        importResultMessage = "Loaded \(result.summary)"
        showImportResults = true
        fetchStats()
    }

    // MARK: - Logic: Tag Rename

    private func renameTag(_ tag: Tag, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != tag.searchableName else { return }

        let oldSearchName = tag.searchableName

        // 1. Update the tag registry object
        tag.name = trimmed
        tag.searchableName = trimmed.lowercased()

        // 2. Cascade update to all interactions that use this tag
        let descriptor = FetchDescriptor<Interaction>()
        if let interactions = try? modelContext.fetch(descriptor) {
            for interaction in interactions {
                let tags = interaction.tagList
                if tags.contains(where: { $0.lowercased() == oldSearchName }) {
                    let updatedTags = tags.map { $0.lowercased() == oldSearchName ? trimmed : $0 }
                    interaction.tagNames = updatedTags.joined(separator: ", ")
                    // Refresh the contact's cached tag summary
                    interaction.contact?.refreshCachedFields()
                }
            }
        }
        PersistenceHelper.saveWithLogging(modelContext, operation: "rename tag")
    }

    // MARK: - Logic: Maintenance Actions

    private func runIntegrityCheck() {
        let issues = validator.integrityCheck(in: modelContext)
        if issues.isEmpty {
            integrityResultMessage = "Your database is perfectly healthy. No orphaned artifacts or sync issues found."
        } else {
            integrityResultMessage = "Doctor repaired \(issues.count) issues (orphaned records removed, sync dates corrected)."
        }
        PersistenceHelper.saveWithLogging(modelContext, operation: "integrity check")
        showIntegrityResults = true
        // Refresh stats after repair
        fetchStats()
    }

    private func rebuildSpotlight() {
        isReindexing = true
        spotlightIndexer.reindexAll(from: modelContext)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isReindexing = false
            importResultMessage = "Spotlight index rebuilt successfully."
            showImportResults = true
        }
    }

    private func purgeDeletedInteractions() {
        let predicate = #Predicate<Interaction> { $0.isDeleted }
        let descriptor = FetchDescriptor<Interaction>(predicate: predicate)
        guard let deleted = try? modelContext.fetch(descriptor) else { return }

        let count = deleted.count
        for interaction in deleted {
            // Refresh parent contact's cache before removing
            interaction.contact?.refreshCachedFields()
            modelContext.delete(interaction)
        }
        PersistenceHelper.saveWithLogging(modelContext, operation: "purge deleted interactions")
        importResultMessage = "Purged \(count) deleted interaction\(count == 1 ? "" : "s") permanently."
        showImportResults = true
        fetchStats()
    }

    private func deleteAllData() {
        try? modelContext.delete(model: Interaction.self)
        try? modelContext.delete(model: Artifact.self)
        try? modelContext.delete(model: Contact.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.delete(model: Constellation.self)
        PersistenceHelper.saveWithLogging(modelContext, operation: "erase all data")
        spotlightIndexer.deleteAll()
        importResultMessage = "All data has been erased."
        showImportResults = true
        fetchStats()
    }

    // MARK: - Logic: Apple Contacts Import

    private func checkContactsAccess() {
            #if canImport(Contacts)
            let status = CNContactStore.authorizationStatus(for: .contacts)
            switch status {
            case .authorized, .limited:
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

            // FIX P0-1.1: Initialize cached fields for new contacts
            newContact.refreshCachedFields()

            importedCount += 1
        }

        PersistenceHelper.saveWithLogging(modelContext, operation: "import contacts")

        // FIX: Batch Spotlight index after all imports instead of per-contact
        spotlightIndexer.reindexAll(from: modelContext)

        isImporting = false
        importResultMessage = "Successfully imported \(importedCount) contacts."
        showImportResults = true
        fetchStats()
    }

    // MARK: - Logic: JSON Backup Import

    private func handleJSONImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Read and preview the file
            guard url.startAccessingSecurityScopedResource() else {
                importResultMessage = "Couldn't access the selected file."
                showImportResults = true
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    importResultMessage = "Invalid backup file. Expected a JSON array of contacts."
                    showImportResults = true
                    return
                }

                let contactCount = jsonArray.count
                let interactionCount = jsonArray.reduce(0) { sum, dict in
                    sum + ((dict["interactions"] as? [[String: Any]])?.count ?? 0)
                }
                let artifactCount = jsonArray.reduce(0) { sum, dict in
                    sum + ((dict["artifacts"] as? [[String: Any]])?.count ?? 0)
                }

                jsonImportPreviewMessage = "This backup contains \(contactCount) contacts, \(interactionCount) interactions, and \(artifactCount) artifacts.\n\nYou can merge into your existing data or replace everything."

                // Save the URL for the actual import (need to re-read because security scope)
                // Store the data instead since the URL scope will expire
                pendingImportData = data
                showJSONImportConfirmation = true

            } catch {
                importResultMessage = "Failed to read backup: \(error.localizedDescription)"
                showImportResults = true
            }

        case .failure(let error):
            if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError {
                return
            }
            importResultMessage = "Failed to select file: \(error.localizedDescription)"
            showImportResults = true
        }
    }

    // Temporary storage for the imported JSON data between preview and execution
    @State private var pendingImportData: Data?

    private func performJSONImport(from url: URL, clearFirst: Bool) {
        isImportingJSON = true

        guard let data = pendingImportData else {
            importResultMessage = "Import data was lost. Please try again."
            showImportResults = true
            isImportingJSON = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    DispatchQueue.main.async {
                        self.importResultMessage = "Invalid JSON format."
                        self.showImportResults = true
                        self.isImportingJSON = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    if clearFirst {
                        self.deleteAllDataSilently()
                    }

                    var importedContacts = 0
                    var importedInteractions = 0
                    var importedArtifacts = 0
                    var constellationMap: [String: Constellation] = [:]

                    // Pre-fetch existing constellation names
                    let constellationDescriptor = FetchDescriptor<Constellation>()
                    if let existing = try? self.modelContext.fetch(constellationDescriptor) {
                        for c in existing {
                            constellationMap[c.name.lowercased()] = c
                        }
                    }

                    // Pre-fetch existing contact names (for merge dedup)
                    let existingNames: Set<String>
                    if !clearFirst {
                        existingNames = Set(self.allContacts.map { $0.searchableName })
                    } else {
                        existingNames = []
                    }

                    for contactDict in jsonArray {
                        guard let name = contactDict["name"] as? String, !name.isEmpty else { continue }

                        // Skip duplicates when merging
                        if !clearFirst && existingNames.contains(name.lowercased()) {
                            continue
                        }

                        let targetOrbit = contactDict["targetOrbit"] as? Int ?? 2
                        let notes = contactDict["notes"] as? String ?? ""
                        let isArchived = contactDict["isArchived"] as? Bool ?? false

                        let contact = Contact(name: name, notes: notes, targetOrbit: targetOrbit)
                        contact.isArchived = isArchived

                        // Restore dates if available
                        if let createdTs = contactDict["createdAt"] as? TimeInterval {
                            contact.createdAt = Date(timeIntervalSince1970: createdTs)
                        }
                        if let modifiedTs = contactDict["modifiedAt"] as? TimeInterval {
                            contact.modifiedAt = Date(timeIntervalSince1970: modifiedTs)
                        }
                        if let lastContactTs = contactDict["lastContactDate"] as? TimeInterval {
                            contact.lastContactDate = Date(timeIntervalSince1970: lastContactTs)
                        }

                        self.modelContext.insert(contact)

                        // Import interactions
                        if let interactions = contactDict["interactions"] as? [[String: Any]] {
                            for interDict in interactions {
                                let impulse = interDict["impulse"] as? String ?? ""
                                let content = interDict["content"] as? String ?? ""
                                let isDeleted = interDict["isDeleted"] as? Bool ?? false
                                let date: Date
                                if let ts = interDict["date"] as? TimeInterval {
                                    date = Date(timeIntervalSince1970: ts)
                                } else {
                                    date = Date()
                                }

                                let interaction = Interaction(impulse: impulse, content: content, date: date)
                                interaction.isDeleted = isDeleted
                                interaction.tagNames = interDict["tagNames"] as? String ?? ""
                                interaction.contact = contact
                                self.modelContext.insert(interaction)
                                importedInteractions += 1
                            }
                        }

                        // Import artifacts
                        if let artifacts = contactDict["artifacts"] as? [[String: Any]] {
                            for artDict in artifacts {
                                let key = artDict["key"] as? String ?? ""
                                let value = artDict["value"] as? String ?? ""
                                let category = artDict["category"] as? String

                                guard !key.isEmpty else { continue }

                                let artifact = Artifact(key: key, value: value, category: category?.isEmpty == true ? nil : category)
                                artifact.contact = contact
                                self.modelContext.insert(artifact)
                                importedArtifacts += 1
                            }
                        }

                        // Restore constellation memberships
                        if let constellationNames = contactDict["constellations"] as? [String] {
                            for cName in constellationNames {
                                guard !cName.isEmpty else { continue }
                                let key = cName.lowercased()

                                let constellation: Constellation
                                if let existing = constellationMap[key] {
                                    constellation = existing
                                } else {
                                    constellation = Constellation(name: cName)
                                    self.modelContext.insert(constellation)
                                    constellationMap[key] = constellation
                                }

                                var members = constellation.contacts ?? []
                                members.append(contact)
                                constellation.contacts = members
                            }
                        }

                        // Refresh cached fields
                        contact.refreshCachedFields()
                        importedContacts += 1
                    }

                    // Register tags from imported interactions
                    self.registerTagsFromInteractions()

                    PersistenceHelper.saveWithLogging(self.modelContext, operation: "import JSON backup")
                    self.spotlightIndexer.reindexAll(from: self.modelContext)

                    self.isImportingJSON = false
                    self.pendingImportData = nil
                    self.importResultMessage = "Imported \(importedContacts) contacts, \(importedInteractions) interactions, and \(importedArtifacts) artifacts."
                    self.showImportResults = true
                    self.fetchStats()
                }

            } catch {
                DispatchQueue.main.async {
                    self.importResultMessage = "Failed to parse backup: \(error.localizedDescription)"
                    self.showImportResults = true
                    self.isImportingJSON = false
                }
            }
        }
    }

    /// Erase all data without showing alerts (used as a step before replace-import)
    private func deleteAllDataSilently() {
        try? modelContext.delete(model: Interaction.self)
        try? modelContext.delete(model: Artifact.self)
        try? modelContext.delete(model: Contact.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.delete(model: Constellation.self)
        PersistenceHelper.saveWithLogging(modelContext, operation: "clear before import")
        spotlightIndexer.deleteAll()
    }

    /// Scan all interactions and register any tag names that aren't in the registry yet.
    private func registerTagsFromInteractions() {
        let existingTagNames: Set<String>
        let tagDescriptor = FetchDescriptor<Tag>()
        if let tags = try? modelContext.fetch(tagDescriptor) {
            existingTagNames = Set(tags.map { $0.searchableName })
        } else {
            existingTagNames = []
        }

        let interactionDescriptor = FetchDescriptor<Interaction>()
        guard let interactions = try? modelContext.fetch(interactionDescriptor) else { return }

        var newTags: Set<String> = []
        for interaction in interactions {
            for tagName in interaction.tagList {
                let key = tagName.lowercased().trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !existingTagNames.contains(key) && !newTags.contains(key) {
                    newTags.insert(key)
                    let tag = Tag(name: tagName.trimmingCharacters(in: .whitespaces))
                    modelContext.insert(tag)
                }
            }
        }
    }

    // MARK: - Logic: Data Export
    private func exportJSON() {
        isExporting = true
        
        if let jsonData = OrbitExporter.exportJSON(from: modelContext) {
            self.exportDocument = ExportDocument(data: jsonData)
            self.exportFilename = "Orbit_Backup_\(self.formattedDate()).json"
            self.exportContentType = .json // Set to JSON
            self.isExporting = false
            self.showExporter = true // Trigger unified exporter
        } else {
            self.importResultMessage = "Failed to generate JSON backup."
            self.showImportResults = true
            self.isExporting = false
        }
    }

    private func exportCSV() {
        isExporting = true
        
        let csvString = OrbitExporter.exportCSV(from: modelContext)
        if let csvData = csvString.data(using: .utf8) {
            self.exportDocument = ExportDocument(data: csvData)
            self.exportFilename = "Orbit_Export_\(self.formattedDate()).csv"
            self.exportContentType = .commaSeparatedText // Set to CSV
            self.isExporting = false
            self.showExporter = true // Trigger unified exporter
        } else {
            self.importResultMessage = "Failed to generate CSV export."
            self.showImportResults = true
            self.isExporting = false
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            importResultMessage = "Export saved successfully."
            showImportResults = true
        case .failure(let error):
            if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError {
                return
            }
            importResultMessage = "Export failed: \(error.localizedDescription)"
            showImportResults = true
        }
        exportDocument = nil
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
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

// MARK: - Support Types

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
    @State private var searchText = ""

    // 1. Filter the contacts based on the search bar
    var filteredContacts: [ImportableContact] {
        if searchText.isEmpty { return importableContacts }
        let query = searchText.lowercased()
        return importableContacts.filter { $0.name.lowercased().contains(query) }
    }

    var selectedCount: Int {
        importableContacts.filter { $0.isSelected }.count
    }
    
    // Helper to check if all *currently visible* contacts are selected
    var allFilteredAreSelected: Bool {
        guard !filteredContacts.isEmpty else { return false }
        return filteredContacts.allSatisfy { $0.isSelected }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        Button {
                            let newState = !allFilteredAreSelected
                            // Only toggle the ones currently shown in the search results
                            for contact in filteredContacts {
                                if let idx = importableContacts.firstIndex(where: { $0.id == contact.id }) {
                                    importableContacts[idx].isSelected = newState
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: allFilteredAreSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(allFilteredAreSelected ? .blue : .secondary)
                                    .font(.title3)
                                
                                Text(allFilteredAreSelected ? "Deselect All" : "Select All")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    Section(header: Text(searchText.isEmpty ? "Found \(importableContacts.count) New Contacts" : "Found \(filteredContacts.count) Contacts")) {
                        ForEach(filteredContacts) { contact in
                            // Map the filtered contact back to the original array to safely update the Binding
                            if let idx = importableContacts.firstIndex(where: { $0.id == contact.id }) {
                                ImportContactRow(contact: $importableContacts[idx])
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .searchable(text: $searchText, prompt: "Search contacts...") // 2. Add Search Bar

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

// MARK: - Updated Checkmark Row
struct ImportContactRow: View {
    @Binding var contact: ImportableContact

    var body: some View {
        HStack(spacing: OrbitSpacing.md) {
            // 3. Replaced Toggle with Circular Checkmark
            Image(systemName: contact.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(contact.isSelected ? .blue : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.bodyMedium)
                    .foregroundStyle(.primary)
                
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
            withAnimation(.snappy(duration: 0.2)) {
                contact.isSelected.toggle()
            }
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

// MARK: - Export Document

/// A lightweight FileDocument wrapper that carries pre-built export data
/// for use with SwiftUI's `.fileExporter()` modifier.
struct ExportDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
