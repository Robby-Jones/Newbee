import Foundation
import NewbeeKit
import SwiftUI
import UIKit

/// Export, import and delete-all, passed through the environment so Settings doesn't reach for
/// `AppDependencies.shared` (and previews can leave them out).
struct DataManagementActions: Sendable {
    var exportCSV: @MainActor @Sendable () throws -> URL
    var exportPDF: @MainActor @Sendable (FeedReportRange) throws -> URL
    var deleteAll: @MainActor @Sendable () async throws -> Void
    /// Reads a Huckleberry export and returns what importing it would add, saving nothing.
    var prepareHuckleberryImport: @MainActor @Sendable (URL) throws -> ImportPlan
    /// Saves a prepared import; returns how many entries were added.
    var commitImport: @MainActor @Sendable (ImportPlan) async throws -> Int
    /// Deletes every imported entry; returns how many were removed.
    var removeImported: @MainActor @Sendable () async throws -> Int
}

extension DataManagementActions {
    @MainActor
    init(dependencies: AppDependencies) {
        exportCSV = { try dependencies.exportCSV() }
        exportPDF = { try dependencies.exportPDF(range: $0) }
        deleteAll = { try await dependencies.deleteAllData() }
        prepareHuckleberryImport = { try dependencies.prepareHuckleberryImport(from: $0) }
        commitImport = { try await dependencies.commitImport($0) }
        removeImported = { try await dependencies.removeImportedData() }
    }
}

private struct DataManagementKey: EnvironmentKey {
    static let defaultValue: DataManagementActions? = nil
}

extension EnvironmentValues {
    var dataManagement: DataManagementActions? {
        get { self[DataManagementKey.self] }
        set { self[DataManagementKey.self] = newValue }
    }
}

/// The system share sheet for a file (AirDrop, Mail, Files, Messages…).
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file ready to share, for `.sheet(item:)`.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
