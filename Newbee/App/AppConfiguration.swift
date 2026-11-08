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

    /// Launch arguments used by UI tests: in-memory store, no onboarding.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// UI tests skip onboarding unless they pass `-showOnboarding` to test it.
    static var showsOnboardingUnderUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-showOnboarding")
    }
}
