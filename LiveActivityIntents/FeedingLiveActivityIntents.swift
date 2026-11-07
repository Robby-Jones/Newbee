// Compiled into BOTH the app and the widget extension (see project.yml):
// - the extension needs the types to build `Button(intent:)` in the Live Activity,
// - the app needs them because `LiveActivityIntent.perform()` runs in the app's process.
// `perform()` only forwards to `LiveActivityIntentRouter`, which the app wires to the single
// `FeedingSessionManager`. There is no timing logic here (docs/LIVE_ACTIVITIES.md §4).

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

/// Ends the feed. Undo is offered in the app.
struct EndFeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "End Feeding" }
    static var isDiscoverable: Bool { false }

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
