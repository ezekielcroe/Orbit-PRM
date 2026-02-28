//
//  PersistenceHelper.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 28/2/26.
//


import Foundation
import SwiftData

// MARK: - PersistenceHelper

@Observable
final class PersistenceHelper {

    // MARK: - Error State (Observable for UI binding)

    /// The most recent save error, if any. Views can observe this to show banners.
    private(set) var lastError: SaveError?

    /// Whether an error is currently being displayed
    var showingError: Bool = false

    /// Dismiss the current error
    func clearError() {
        lastError = nil
        showingError = false
    }

    // MARK: - Save

    /// Save the context with error capture. Returns true on success.
    @discardableResult
    func save(_ context: ModelContext, operation: String = "save") -> Bool {
        do {
            try context.save()
            return true
        } catch {
            let saveError = SaveError(
                operation: operation,
                underlyingError: error,
                timestamp: Date()
            )
            lastError = saveError
            showingError = true

            // Always log for diagnostics
            print("⚠️ Save failed [\(operation)]: \(error.localizedDescription)")

            return false
        }
    }

    // MARK: - Static convenience for fire-and-forget saves (e.g., in CommandExecutor)
    // These log errors but don't surface them to the UI.

    /// Save with logging only (no UI error state). Use when you don't have access to
    /// the PersistenceHelper instance (e.g., inside CommandExecutor).
    @discardableResult
    static func saveWithLogging(_ context: ModelContext, operation: String = "save") -> Bool {
        do {
            try context.save()
            return true
        } catch {
            print("⚠️ Save failed [\(operation)]: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - SaveError

struct SaveError: Identifiable {
    let id = UUID()
    let operation: String
    let underlyingError: Error
    let timestamp: Date

    var userMessage: String {
        "Failed to \(operation). Your changes may not have been saved."
    }

    var technicalDetail: String {
        underlyingError.localizedDescription
    }
}
