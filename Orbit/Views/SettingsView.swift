import SwiftUI
import SwiftData
#if canImport(Contacts)
import Contacts
#endif

// MARK: - SettingsView
// Central hub for data management, export, import, and app preferences.
// Accessible from the sidebar. Emphasizes data ownership — export and
// import are first-class citizens, not buried in submenus.
//
// FIX 2: macOS uses a TabView for native Settings-window appearance.
// FIX 3: Import uses a two-step preview flow with contact selection.

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var allContacts: [Contact]
    @Query private var allInteractions: [Interaction]
    @Query private var allArtifacts: [Artifact]
    @Query private var allTags: [Tag]
    @Query private var allConstellations: [Constellation]

    @State private var showExportSheet = false
    @State private var showImportConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showImportResults = false
    @State private var importResultMessage = ""
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var contactsAccessStatus: String = "Not checked"
    @State private var showOpenSettingsAlert = false

    // FIX 3: Import preview state
    @State private var showImportPreview = false
    @State private var importableContacts: [ImportableContact] = []
    @State private var isFetchingContacts = false

    #if os(iOS)
    @State private var showShareSheet = false
    #endif

    var body: some View {
        settingsContent
            .alert("Import Complete", isPresented: $showImportResults) {
                Button("OK") {}
            } message: {
                Text(importResultMessage)
            }
            .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all contacts, interactions, artifacts, tags, and constellations. This action cannot be undone.")
            }
            .alert("Contacts Access Required", isPresented: $showOpenSettingsAlert) {
                Button("Open Settings") {
                    #if os(iOS)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #else
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                        NSWorkspace.shared.open(url)
                    }
                    #endif
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You previously declined Contacts access. To import contacts, open Settings and enable Contacts permission for Orbit.")
            }
            .sheet(isPresented: $showImportPreview) {
                ImportPreviewSheet(
                    importableContacts: $importableContacts,
                    onImport: { selectedContacts, defaultOrbit in
                        importSelectedContacts(selectedContacts, defaultOrbit: defaultOrbit)
                    }
                )
            }
    }

    // MARK: - Platform-Adaptive Layout

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        TabView {
            Form {
                dataOverviewSection
                aboutSection
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }
            .tag(0)

            Form {
                exportSection
                importSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Data", systemImage: "externaldrive") }
            .tag(1)

            Form {
                dataManagementSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Maintenance", systemImage: "wrench.and.screwdriver") }
            .tag(2)
        }
        .frame(minWidth: 480)
        #else
        Form {
            dataOverviewSection
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
            Text("Your Data")
        } footer: {
            Text("All data is stored locally on your device and synced via your personal iCloud account. Orbit never sends your data to external servers.")
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Button {
                exportJSON()
            } label: {
                Label("Export as JSON", systemImage: "doc.text")
            }
            .disabled(allContacts.isEmpty || isExporting)

            Button {
                exportCSV()
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }
            .disabled(allContacts.isEmpty || isExporting)

            if isExporting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing export…")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("JSON includes all data: contacts, artifacts, interactions, tags, and constellations. CSV includes a summary suitable for spreadsheets.")
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Button {
                checkContactsAccess()
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.rectangle.stack")
            }
            .disabled(isFetchingContacts || isImporting)

            if isFetchingContacts {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading contacts…")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isImporting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Importing…")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Imports names from your system Contacts. You'll be able to review and select which contacts to import before committing. Duplicates are detected automatically.")
        }
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        Section {
            Button {
                purgeDeletedInteractions()
            } label: {
                Label("Purge Deleted Interactions", systemImage: "trash.slash")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete All Data", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("\"Purge Deleted\" permanently removes soft-deleted interaction logs. \"Delete All\" removes everything — use with extreme caution.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About Orbit") {
            StatRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            StatRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")

            HStack {
                Text("Philosophy")
                    .font(OrbitTypography.body)
                Spacer()
                Text("Accounting, not automation")
                    .font(OrbitTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Export Actions

    private func exportJSON() {
        isExporting = true

        Task {
            guard let data = OrbitExporter.exportJSON(from: modelContext) else {
                isExporting = false
                return
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("orbit-export-\(formattedDate()).json")

            do {
                try data.write(to: tempURL)
                exportURL = tempURL
                shareFile(at: tempURL)
            } catch {
                print("Export failed: \(error)")
            }

            isExporting = false
        }
    }

    private func exportCSV() {
        isExporting = true

        Task {
            let csv = OrbitExporter.exportCSV(from: modelContext)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("orbit-export-\(formattedDate()).csv")

            do {
                try csv.write(to: tempURL, atomically: true, encoding: .utf8)
                shareFile(at: tempURL)
            } catch {
                print("Export failed: \(error)")
            }

            isExporting = false
        }
    }

    private func shareFile(at url: URL) {
        #if os(iOS)
        // Use UIActivityViewController via a UIKit bridge
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // iPad requires a popover source
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootVC.present(activityVC, animated: true)
        #else
        // macOS: Use NSSharingServicePicker or NSWorkspace
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    // MARK: - Import Actions (FIX 3: Two-step flow)

    private func checkContactsAccess() {
        #if canImport(Contacts)
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized, .limited:
            fetchSystemContacts()

        case .notDetermined:
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        fetchSystemContacts()
                    } else {
                        importResultMessage = "Orbit needs Contacts access to import. You can grant this in Settings."
                        showImportResults = true
                    }
                }
            }

        case .denied, .restricted:
            showOpenSettingsAlert = true

        @unknown default:
            importResultMessage = "Unable to determine Contacts access status."
            showImportResults = true
        }
        #else
        importResultMessage = "Contact import is not available on this platform."
        showImportResults = true
        #endif
    }

    /// Step 1: Fetch system contacts and present the preview sheet
    private func fetchSystemContacts() {
        #if canImport(Contacts)
        isFetchingContacts = true

        Task.detached {
            let store = CNContactStore()
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactBirthdayKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor,
            ]

            var collected: [ImportableContact] = []
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
                // Get existing names for duplicate detection
                let existingNames: Set<String> = await MainActor.run {
                    let descriptor = FetchDescriptor<Contact>()
                    let existing = (try? modelContext.fetch(descriptor)) ?? []
                    return Set(existing.map(\.searchableName))
                }

                try store.enumerateContacts(with: request) { cnContact, _ in
                    let fullName = [cnContact.givenName, cnContact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard !fullName.isEmpty else { return }

                    let birthday: String? = {
                        guard let bday = cnContact.birthday,
                              let month = bday.month,
                              let day = bday.day else { return nil }
                        return String(format: "%02d/%02d", month, day)
                    }()

                    let isDuplicate = existingNames.contains(fullName.lowercased())

                    collected.append(ImportableContact(
                        name: fullName,
                        birthday: birthday,
                        company: cnContact.organizationName.isEmpty ? nil : cnContact.organizationName,
                        role: cnContact.jobTitle.isEmpty ? nil : cnContact.jobTitle,
                        email: cnContact.emailAddresses.first?.value as String?,
                        phone: cnContact.phoneNumbers.first?.value.stringValue,
                        city: {
                            guard let addr = cnContact.postalAddresses.first?.value else { return nil }
                            return addr.city.isEmpty ? nil : addr.city
                        }(),
                        isSelected: !isDuplicate,
                        isDuplicate: isDuplicate
                    ))
                }

                // Sort: non-duplicates first, then alphabetically
                collected.sort { a, b in
                    if a.isDuplicate != b.isDuplicate {
                        return !a.isDuplicate
                    }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }

                let result = collected
                await MainActor.run {
                    importableContacts = result
                    isFetchingContacts = false
                    showImportPreview = true
                }

            } catch {
                await MainActor.run {
                    importResultMessage = "Failed to read contacts: \(error.localizedDescription)"
                    showImportResults = true
                    isFetchingContacts = false
                }
            }
        }
        #endif
    }

    /// Step 2: Import only the selected contacts with the chosen orbit zone
    private func importSelectedContacts(_ selected: [ImportableContact], defaultOrbit: Int) {
        isImporting = true

        var imported = 0
        for item in selected {
            let contact = Contact(name: item.name, targetOrbit: defaultOrbit)
            modelContext.insert(contact)

            if let birthday = item.birthday {
                let a = Artifact(key: "birthday", value: birthday)
                a.contact = contact
                modelContext.insert(a)
            }
            if let company = item.company {
                let a = Artifact(key: "company", value: company)
                a.contact = contact
                modelContext.insert(a)
            }
            if let role = item.role {
                let a = Artifact(key: "role", value: role)
                a.contact = contact
                modelContext.insert(a)
            }
            if let email = item.email {
                let a = Artifact(key: "email", value: email)
                a.contact = contact
                modelContext.insert(a)
            }
            if let phone = item.phone {
                let a = Artifact(key: "phone", value: phone)
                a.contact = contact
                modelContext.insert(a)
            }
            if let city = item.city {
                let a = Artifact(key: "city", value: city)
                a.contact = contact
                modelContext.insert(a)
            }

            imported += 1
        }

        importResultMessage = "Imported \(imported) contact\(imported == 1 ? "" : "s")."
        showImportResults = true
        isImporting = false
    }

    // MARK: - Data Management Actions

    private func purgeDeletedInteractions() {
        let descriptor = FetchDescriptor<Interaction>(
            predicate: #Predicate<Interaction> { $0.isDeleted == true }
        )
        guard let deleted = try? modelContext.fetch(descriptor) else { return }

        for interaction in deleted {
            modelContext.delete(interaction)
        }
    }

    private func deleteAllData() {
        do {
            try modelContext.delete(model: Interaction.self)
            try modelContext.delete(model: Artifact.self)
            try modelContext.delete(model: Tag.self)
            try modelContext.delete(model: Constellation.self)
            try modelContext.delete(model: Contact.self)
        } catch {
            print("Failed to delete all data: \(error)")
        }
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(OrbitTypography.body)
            Spacer()
            Text(value)
                .font(OrbitTypography.bodyMedium)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Importable Contact Model

struct ImportableContact: Identifiable {
    let id = UUID()
    let name: String
    let birthday: String?
    let company: String?
    let role: String?
    let email: String?
    let phone: String?
    let city: String?
    var isSelected: Bool
    let isDuplicate: Bool

    /// Short summary of available data for the preview row
    var subtitle: String {
        [company, role, city].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Import Preview Sheet

struct ImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var importableContacts: [ImportableContact]
    let onImport: ([ImportableContact], Int) -> Void

    @State private var defaultOrbit: Int = 3
    @State private var searchText = ""

    private var filteredContacts: [ImportableContact] {
        if searchText.isEmpty { return importableContacts }
        let query = searchText.lowercased()
        return importableContacts.filter {
            $0.name.lowercased().contains(query)
            || ($0.company?.lowercased().contains(query) ?? false)
            || ($0.city?.lowercased().contains(query) ?? false)
        }
    }

    private var selectedCount: Int {
        importableContacts.filter(\.isSelected).count
    }

    private var duplicateCount: Int {
        importableContacts.filter(\.isDuplicate).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary bar
                summaryBar
                Divider()

                // Contact list
                List {
                    if duplicateCount > 0 {
                        Section {
                            HStack(spacing: OrbitSpacing.sm) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("\(duplicateCount) contact\(duplicateCount == 1 ? "" : "s") already exist in Orbit and have been deselected.")
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    ForEach(filteredContacts) { contact in
                        importContactRow(contact)
                    }
                }
                .listStyle(.plain)

                Divider()

                // Orbit zone picker + import button
                importControls
            }
            .navigationTitle("Import Contacts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: OrbitSpacing.md) {
            Text("\(importableContacts.count) found")
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("\(selectedCount) selected")
                .font(OrbitTypography.captionMedium)
                .foregroundStyle(selectedCount > 0 ? .primary : .secondary)

            Spacer()

            Button("Select All") {
                for i in importableContacts.indices {
                    importableContacts[i].isSelected = true
                }
            }
            .controlSize(.small)

            Button("Select None") {
                for i in importableContacts.indices {
                    importableContacts[i].isSelected = false
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.vertical, OrbitSpacing.sm)
    }

    // MARK: - Contact Row

    private func importContactRow(_ contact: ImportableContact) -> some View {
        // Find the actual index in the source array for binding
        let sourceIndex = importableContacts.firstIndex(where: { $0.id == contact.id })

        return HStack(spacing: OrbitSpacing.md) {
            // Checkbox
            Button {
                if let idx = sourceIndex {
                    importableContacts[idx].isSelected.toggle()
                }
            } label: {
                Image(systemName: contact.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(contact.isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OrbitSpacing.sm) {
                    Text(contact.name)
                        .font(OrbitTypography.bodyMedium)
                        .opacity(contact.isDuplicate ? 0.5 : 1.0)

                    if contact.isDuplicate {
                        Text("Duplicate")
                            .font(OrbitTypography.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.1), in: Capsule())
                    }
                }

                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle)
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Data indicators
            HStack(spacing: OrbitSpacing.xs) {
                if contact.email != nil {
                    Image(systemName: "envelope")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if contact.phone != nil {
                    Image(systemName: "phone")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if contact.birthday != nil {
                    Image(systemName: "gift")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let idx = sourceIndex {
                importableContacts[idx].isSelected.toggle()
            }
        }
    }

    // MARK: - Import Controls

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
