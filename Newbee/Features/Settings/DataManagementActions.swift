import Foundation
import SwiftUI
import UIKit

/// Export and delete-all, passed through the environment so Settings doesn't reach for
/// `AppDependencies.shared` (and previews can leave them out).
struct DataManagementActions: Sendable {
    var exportCSV: @MainActor @Sendable () throws -> URL
    var deleteAll: @MainActor @Sendable () async throws -> Void
}

extension DataManagementActions {
    @MainActor
    init(dependencies: AppDependencies) {
        exportCSV = { try dependencies.exportCSV() }
        deleteAll = { try await dependencies.deleteAllData() }
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
