import Foundation

/// Values injected at build time through Info.plist (see Config/Base.xcconfig).
enum AppConfiguration {
    /// App Group shared by the app and widget extension.
    static let appGroupID: String = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "NewbeeAppGroup") as? String, !id.isEmpty else {
            preconditionFailure("NewbeeAppGroup missing from Info.plist")
        }
        return id
    }()

    /// The iCloud container feeds sync with (`iCloud.<bundle ID>`), or `nil` when this run
    /// mustn't use iCloud: unit and UI tests, or a build without the container.
    ///
    /// Tests run unsigned, without the iCloud entitlement, and CloudKit stops the app when it is
    /// used without one, so they never get a container.
    static var cloudKitContainerID: String? {
        if isUITesting || isRunningUnitTests { return nil }
        guard let id = Bundle.main.object(forInfoDictionaryKey: "NewbeeCloudKitContainer") as? String,
              id.hasPrefix("iCloud.") else { return nil }
        return id
    }

    /// True inside the unit test host.
    static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains { environment[$0] != nil }
    }

    /// Launch arguments used by UI tests: in-memory store, no onboarding.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// UI tests skip onboarding unless they pass `-showOnboarding` to test it.
    static var showsOnboardingUnderUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-showOnboarding")
    }
}
