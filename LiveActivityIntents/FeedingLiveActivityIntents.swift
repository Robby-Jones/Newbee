// Compiled into BOTH the app and the widget extension (see project.yml):
// - the extension needs the types to build `Button(intent:)` in the Live Activity,
// - the app needs them because `LiveActivityIntent.perform()` runs in the app's process.
// `perform()` only forwards to `LiveActivityIntentRouter`, which the app wires to the single
// `FeedingSessionManager`. There is no timing logic here (docs/LIVE_ACTIVITIES.md §4).
//
// Every intent sets `authenticationPolicy = .alwaysAllowed` so the buttons work without unlocking
// the phone. The app process that performs them can then run while the phone is locked, so the
// store it reads is kept readable after first unlock (`PersistenceController.storeURL()`).

import AppIntents
import Foundation
import NewbeeKit
import NewbeeShared
import os

/// A breast side as an App Intents parameter.
enum IntentSide: String, AppEnum {
    case left
    case right

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Side" }
    static var caseDisplayRepresentations: [IntentSide: DisplayRepresentation] {
        [.left: "Left", .right: "Right"]
    }

    init(_ side: Side) {
        self = side == .left ? .left : .right
    }

    var side: Side { self == .left ? .left : .right }
}

/// "Switch to <side>" from the Lock Screen or Dynamic Island. From paused, it resumes on that side.
/// Carries a target side, not a toggle, so a double tap can't flip it back.
struct SwitchFeedingSideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Switch Feeding Side" }
    static var isDiscoverable: Bool { false }
    /// Runs from a locked Lock Screen without asking for Face ID or the passcode.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Side") var side: IntentSide

    init() {}

    init(sessionID: UUID, side: Side) {
        self.sessionID = sessionID.uuidString
        self.side = IntentSide(side)
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityIntentRunner.run(.switchTo(side.side), sessionID: sessionID)
        return .result()
    }
}

/// Pauses the running feed. A no-op if already paused.
struct PauseFeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause Feeding" }
    static var isDiscoverable: Bool { false }
    /// Runs from a locked Lock Screen without asking for Face ID or the passcode.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session") var sessionID: String

    init() {}

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityIntentRunner.run(.pause, sessionID: sessionID)
        return .result()
    }
}

/// Resumes on the last side. A no-op if already running.
struct ResumeFeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Resume Feeding" }
    static var isDiscoverable: Bool { false }
    /// Runs from a locked Lock Screen without asking for Face ID or the passcode.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session") var sessionID: String

    init() {}

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityIntentRunner.run(.resume, sessionID: sessionID)
        return .result()
    }
}

/// Ends the feed. The same activity then counts the time since this feed ended.
struct EndFeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "End Feeding" }
    static var isDiscoverable: Bool { false }
    /// Runs from a locked Lock Screen without asking for Face ID or the passcode.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session") var sessionID: String

    init() {}

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityIntentRunner.run(.end, sessionID: sessionID)
        return .result()
    }
}

/// "Start" on the since-last-feed state: begins a new feed on `side`. A no-op if a feed is
/// already running, or if `sessionID` (the finished feed the activity was showing) is no longer the
/// latest feed, so an out-of-date activity can't start one.
struct StartFeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Start Feeding" }
    static var isDiscoverable: Bool { false }
    /// Runs from a locked Lock Screen without asking for Face ID or the passcode.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Side") var side: IntentSide

    init() {}

    init(sessionID: UUID, side: Side) {
        self.sessionID = sessionID.uuidString
        self.side = IntentSide(side)
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityIntentRunner.run(.start(side.side), sessionID: sessionID)
        return .result()
    }
}

enum LiveActivityIntentRunner {
    private static let logger = Logger(subsystem: "Newbee", category: "LiveActivityIntent")

    /// Never throws: a failed button press should leave the activity as it was, not show an error
    /// on the Lock Screen. The session manager re-syncs the activity in every case.
    @MainActor
    static func run(_ command: LiveActivityCommand, sessionID: String) async {
        guard let id = UUID(uuidString: sessionID) else {
            logger.error("Ignoring \(String(describing: command)) with malformed session id")
            return
        }
        let handled = await LiveActivityIntentRouter.route(command, sessionID: id)
        if !handled {
            logger.fault("No LiveActivityCommandHandling registered; \(String(describing: command)) dropped")
        }
    }
}
