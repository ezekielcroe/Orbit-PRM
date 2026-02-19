import Foundation
import SwiftData

// MARK: - DataValidator
// Centralized validation for data integrity. Personal CRM data evolves
// over time — names get corrected, duplicates emerge from imports,
// and artifacts accumulate inconsistencies. This validator catches
// issues proactively.

@Observable
final class DataValidator {

    // MARK: - Contact Validation

    struct ValidationResult {
        let issues: [ValidationIssue]

        var isValid: Bool { issues.isEmpty }
        var hasWarnings: Bool { issues.contains(where: { $0.severity == .warning }) }
        var hasErrors: Bool { issues.contains(where: { $0.severity == .error }) }
    }

    struct ValidationIssue: Identifiable {
        let id = UUID()
        let message: String
        let severity: Severity
        let suggestion: String?

        enum Severity {
            case warning
            case error
        }
    }

    /// Validate a contact name before creation
    func validateContactName(_ name: String, excluding contactID: UUID? = nil, in context: ModelContext) -> ValidationResult {
        var issues: [ValidationIssue] = []
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // Empty name
        if trimmed.isEmpty {
            issues.append(ValidationIssue(
                message: "Name cannot be empty.",
                severity: .error,
                suggestion: nil
            ))
            return ValidationResult(issues: issues)
        }

        // Very short name
        if trimmed.count == 1 {
            issues.append(ValidationIssue(
                message: "Name is very short. Consider using a full name.",
                severity: .warning,
                suggestion: nil
            ))
        }

        // Check for duplicates
        let searchName = trimmed.lowercased()
        let predicate = #Predicate<Contact> { contact in
            contact.searchableName == searchName
        }
        var descriptor = FetchDescriptor<Contact>(predicate: predicate)
        descriptor.fetchLimit = 5

        if let matches = try? context.fetch(descriptor) {
            let nonSelfMatches = matches.filter { $0.id != contactID }
            if !nonSelfMatches.isEmpty {
                let existingNames = nonSelfMatches.map(\.name).joined(separator: ", ")
                issues.append(ValidationIssue(
                    message: "A contact named \"\(existingNames)\" already exists.",
                    severity: .warning,
                    suggestion: "Consider adding a last name or identifier to distinguish them."
                ))
            }
        }

        // Check for near-duplicates (prefix match)
        let prefixPredicate = #Predicate<Contact> { contact in
            contact.searchableName.starts(with: searchName) && contact.searchableName != searchName
        }
        var prefixDescriptor = FetchDescriptor<Contact>(predicate: prefixPredicate)
        prefixDescriptor.fetchLimit = 3

        if let nearMatches = try? context.fetch(prefixDescriptor), !nearMatches.isEmpty {
            let names = nearMatches.map(\.name).joined(separator: ", ")
            issues.append(ValidationIssue(
                message: "Similar contacts exist: \(names)",
                severity: .warning,
                suggestion: nil
            ))
        }

        return ValidationResult(issues: issues)
    }

    // MARK: - Artifact Validation

    /// Validate an artifact key-value pair
    func validateArtifact(key: String, value: String) -> ValidationResult {
        var issues: [ValidationIssue] = []

        if key.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(
                message: "Artifact key cannot be empty.",
                severity: .error,
                suggestion: nil
            ))
        }

        // Warn about date-like keys with unparseable values
        let dateKeys = ["birthday", "anniversary", "born", "dob"]
        if dateKeys.contains(key.lowercased()) && !isParseableDate(value) {
            issues.append(ValidationIssue(
                message: "This looks like a date field but the value couldn't be parsed.",
                severity: .warning,
                suggestion: "Use formats like MM/DD, YYYY-MM-DD, or Month Day (e.g., March 5)."
            ))
        }

        return ValidationResult(issues: issues)
    }

    /// Check if a string can be parsed as a recurring date
    private func isParseableDate(_ value: String) -> Bool {
        // MM/DD
        let slashParts = value.split(separator: "/")
        if slashParts.count >= 2,
           let month = Int(slashParts[0]),
           let day = Int(slashParts[1]),
           (1...12).contains(month),
           (1...31).contains(day) {
            return true
        }

        // YYYY-MM-DD
        let dashParts = value.split(separator: "-")
        if dashParts.count == 3,
           Int(dashParts[1]) != nil,
           Int(dashParts[2]) != nil {
            return true
        }

        // Month name formats
        let dateFormatter = DateFormatter()
        for format in ["MMMM d", "MMM d", "MMMM dd", "MMM dd", "d MMMM", "d MMM"] {
            dateFormatter.dateFormat = format
            if dateFormatter.date(from: value) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Data Integrity Check

    /// Run a comprehensive integrity check on all data.
    /// Returns a list of issues found (orphaned records, inconsistencies, etc.)
    func integrityCheck(in context: ModelContext) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check for contacts with stale lastContactDate
        let contactDescriptor = FetchDescriptor<Contact>()
        if let contacts = try? context.fetch(contactDescriptor) {
            for contact in contacts {
                // Verify lastContactDate matches actual interactions
                let actualLast = contact.interactions
                    .filter { !$0.isDeleted }
                    .map(\.date)
                    .max()

                if contact.lastContactDate != actualLast {
                    contact.refreshLastContactDate()
                    issues.append(ValidationIssue(
                        message: "\(contact.name): lastContactDate was stale — corrected.",
                        severity: .warning,
                        suggestion: nil
                    ))
                }

                // Check for contacts with mismatched searchableName
                if contact.searchableName != contact.name.lowercased() {
                    contact.updateSearchableName()
                    issues.append(ValidationIssue(
                        message: "\(contact.name): searchable name was out of sync — corrected.",
                        severity: .warning,
                        suggestion: nil
                    ))
                }
            }
        }

        // Check for orphaned artifacts (no contact)
        let artifactDescriptor = FetchDescriptor<Artifact>()
        if let artifacts = try? context.fetch(artifactDescriptor) {
            let orphaned = artifacts.filter { $0.contact == nil }
            if !orphaned.isEmpty {
                issues.append(ValidationIssue(
                    message: "\(orphaned.count) artifact(s) with no associated contact found.",
                    severity: .warning,
                    suggestion: "These may be remnants of deleted contacts."
                ))
                // Clean up orphans
                for artifact in orphaned {
                    context.delete(artifact)
                }
            }
        }

        // Check for orphaned interactions
        let interactionDescriptor = FetchDescriptor<Interaction>()
        if let interactions = try? context.fetch(interactionDescriptor) {
            let orphaned = interactions.filter { $0.contact == nil }
            if !orphaned.isEmpty {
                issues.append(ValidationIssue(
                    message: "\(orphaned.count) interaction(s) with no associated contact found.",
                    severity: .warning,
                    suggestion: nil
                ))
                for interaction in orphaned {
                    context.delete(interaction)
                }
            }
        }

        return issues
    }
}
