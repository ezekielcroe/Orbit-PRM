//
//  SettingsView.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 28/2/26.
//


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
    @State private var showJSONExporter = false
    @State private var showCSVExporter = false
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

    // Tag Management State
    @State private var showAddTag = false
    @State private var newTagName = ""

    // Theme
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appTint") private var appTint: AppTint = .blue

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
                statsSection
                tagSection
                exportSection
                importSection
                appearanceSection
                maintenanceSection
                aboutSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .onAppear {
            fetchStats()
        }
        .alert("Data Erased", isPresented: $showImportResults) {
            Button("OK") {}
        } message: {
            Text(importResultMessage)
        }
        .alert("Database Health", isPresented: $showIntegrityResults) {
            Button("OK") {}
        } message: {
            Text(integrityResultMessage)
        }
        .confirmationDialog("Erase All Data?", isPresented: $showDeleteConfirmation) {
            Button("Erase Everything", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all contacts, interactions, artifacts, tags, and constellations. This cannot be undone.")
        }
        .fileExporter(
            isPresented: $showJSONExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            handleExportResult(result)
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            handleExportResult(result)
        }
        .sheet(isPresented: $showImportPreview) {
            ImportPreviewSheet(
                importableContacts: $importableContacts,
                onImport: importSelectedContacts
            )
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
                Label("Export JSON", systemImage: "doc.text")
            }
            .disabled(isExporting)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }
            .disabled(isExporting)
        } header: {
            Text("Data Export")
        } footer: {
            Text("JSON includes all data. CSV provides a flat summary of contacts.")
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section {
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
            Text("Imports names and basic info. Duplicates are skipped automatically.")
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

    // MARK: - Logic: Data Export

    private func exportJSON() {
        isExporting = true
        // Fetch full data only at export time
        DispatchQueue.global(qos: .userInitiated).async {
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
                
                dict["artifacts"] = (contact.artifacts ?? []).map { artifact -> [String: Any] in
                    return [
                        "key": artifact.key,
                        "value": artifact.value,
                        "category": artifact.category ?? ""
                    ]
                }
                
                dict["interactions"] = (contact.interactions ?? []).map { interaction -> [String: Any] in
                    return [
                        "date": interaction.date.timeIntervalSince1970,
                        "impulse": interaction.impulse,
                        "content": interaction.content,
                        "tagNames": interaction.tagNames,
                        "isDeleted": interaction.isDeleted
                    ]
                }
                
                dict["constellations"] = (contact.constellations ?? []).map { $0.name }
                
                return dict
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
                DispatchQueue.main.async {
                    self.exportDocument = ExportDocument(data: jsonData)
                    self.exportFilename = "Orbit_Export_\(self.formattedDate()).json"
                    self.isExporting = false
                    self.showJSONExporter = true
                }
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
            var csv = "Name,Orbit Zone,Target Orbit,Last Contact,Days Since Contact,Interaction Count,Tags,Constellations,Archived,Notes\n"
            
            for contact in self.allContacts {
                let name = Self.csvEscape(contact.name)
                let orbit = contact.orbitZoneName
                let targetOrbit = String(contact.targetOrbit)
                let lastContact = contact.lastContactDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
                let daysSince = contact.daysSinceLastContact.map(String.init) ?? "N/A"
                let interactionCount = String(contact.cachedInteractionCount)
                let tags = Self.csvEscape(contact.cachedTagSummary.replacingOccurrences(of: ",", with: "; "))
                let constellations = Self.csvEscape((contact.constellations ?? []).map(\.name).joined(separator: "; "))
                let archived = contact.isArchived ? "Yes" : "No"
                let notes = Self.csvEscape(contact.notes)
                
                csv += "\(name),\(orbit),\(targetOrbit),\(lastContact),\(daysSince),\(interactionCount),\(tags),\(constellations),\(archived),\(notes)\n"
            }
            
            if let data = csv.data(using: .utf8) {
                DispatchQueue.main.async {
                    self.exportDocument = ExportDocument(data: data)
                    self.exportFilename = "Orbit_Export_\(self.formattedDate()).csv"
                    self.isExporting = false
                    self.showCSVExporter = true
                }
            }
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
                .listStyle(.insetGrouped)
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
