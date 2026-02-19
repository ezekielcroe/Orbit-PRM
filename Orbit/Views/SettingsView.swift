import SwiftUI
import SwiftData
#if canImport(Contacts)
import Contacts
#endif

// MARK: - SettingsView
// Central hub for data management, export, import, and app preferences.
// Accessible from the sidebar. Emphasizes data ownership — export and
// import are first-class citizens, not buried in submenus.

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

    #if os(iOS)
    @State private var showShareSheet = false
    #endif

    var body: some View {
        Form {
            dataOverviewSection
            exportSection
            importSection
            dataManagementSection
            aboutSection
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
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
            .disabled(isImporting)

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
            Text("Imports names from your system Contacts. Orbit does not sync ongoing changes — it's a one-time import to seed your relationship map. Duplicates are skipped.")
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

    // MARK: - Import Actions

    private func checkContactsAccess() {
        #if canImport(Contacts)
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized, .limited:
            // Already have access — import directly
            importFromSystemContacts()

        case .notDetermined:
            // First time — show the system prompt
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        importFromSystemContacts()
                    } else {
                        importResultMessage = "Orbit needs Contacts access to import. You can grant this in Settings."
                        showImportResults = true
                    }
                }
            }

        case .denied, .restricted:
            // Previously denied — system won't re-prompt, so direct to Settings
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

    private func importFromSystemContacts() {
        #if canImport(Contacts)
        isImporting = true

        // Collect contacts on a background thread, then insert on main
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

            struct ImportedContact {
                let name: String
                let birthday: String?
                let company: String?
                let role: String?
                let email: String?
                let phone: String?
                let city: String?
            }

            var collected: [ImportedContact] = []
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
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

                    collected.append(ImportedContact(
                        name: fullName,
                        birthday: birthday,
                        company: cnContact.organizationName.isEmpty ? nil : cnContact.organizationName,
                        role: cnContact.jobTitle.isEmpty ? nil : cnContact.jobTitle,
                        email: cnContact.emailAddresses.first?.value as String?,
                        phone: cnContact.phoneNumbers.first?.value.stringValue,
                        city: {
                            guard let addr = cnContact.postalAddresses.first?.value else { return nil }
                            return addr.city.isEmpty ? nil : addr.city
                        }()
                    ))
                }

                // Insert into SwiftData on the main actor
                await MainActor.run { [collected] in
                    let existingDescriptor = FetchDescriptor<Contact>()
                    let existingContacts = (try? modelContext.fetch(existingDescriptor)) ?? []
                    let existingNames = Set(existingContacts.map(\.searchableName))

                    var imported = 0
                    var skipped = 0

                    for item in collected {
                        if existingNames.contains(item.name.lowercased()) {
                            skipped += 1
                            continue
                        }

                        let contact = Contact(name: item.name, targetOrbit: 3)
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

                    importResultMessage = "Imported \(imported) contact\(imported == 1 ? "" : "s"). \(skipped > 0 ? "Skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")." : "")"
                    showImportResults = true
                    isImporting = false
                }

            } catch {
                await MainActor.run {
                    importResultMessage = "Import failed: \(error.localizedDescription)"
                    showImportResults = true
                    isImporting = false
                }
            }
        }
        #endif
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
