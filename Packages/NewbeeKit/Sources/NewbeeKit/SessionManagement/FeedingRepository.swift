import Foundation

/// Storage for breastfeeding sessions, in terms of value snapshots.
///
/// The app implements it with SwiftData (`SwiftDataFeedingRepository`); `InMemoryFeedingRepository`
/// serves tests and previews. Every call reads the store afresh: callers never rely on cached state.
@MainActor
public protocol FeedingRepository: AnyObject {
    /// Breastfeeding sessions whose status is active or paused, newest `startedAt` first.
    /// Normally zero or one; more means the store needs recovery.
    func openSessions() throws -> [SessionSnapshot]

    /// One session by ID, whatever its status.
    func session(id: UUID) throws -> SessionSnapshot?

    /// Completed breastfeeding sessions, newest `startedAt` first.
    func recentCompletedSessions(limit: Int) throws -> [SessionSnapshot]

    /// Inserts or replaces each snapshot (segments included) and commits, all or nothing.
    /// `modifiedAt` is stamped on every saved session.
    func save(_ snapshots: [SessionSnapshot], modifiedAt: Date) throws

    /// Deletes a session and its segments. Deleting a missing session is not an error.
    func delete(sessionID: UUID) throws
}

extension FeedingRepository {
    /// The session the timer is showing: the newest active or paused one.
    public func activeSession() throws -> SessionSnapshot? {
        try openSessions().first
    }

    public func save(_ snapshot: SessionSnapshot, modifiedAt: Date) throws {
        try save([snapshot], modifiedAt: modifiedAt)
    }
}

/// A dictionary-backed repository for tests and SwiftUI previews.
@MainActor
public final class InMemoryFeedingRepository: FeedingRepository {
    public private(set) var sessions: [UUID: SessionSnapshot]
    /// When set, every save and delete throws this error and changes nothing (tests a failing disk).
    public var simulatedFailure: (any Error)?

    public init(sessions: [SessionSnapshot] = []) {
        self.sessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }

    public func openSessions() throws -> [SessionSnapshot] {
        sessions.values.filter { $0.status != .completed }.sorted { $0.startedAt > $1.startedAt }
    }

    public func session(id: UUID) throws -> SessionSnapshot? {
        sessions[id]
    }

    public func recentCompletedSessions(limit: Int) throws -> [SessionSnapshot] {
        Array(sessions.values.filter { $0.status == .completed }.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func save(_ snapshots: [SessionSnapshot], modifiedAt: Date) throws {
        if let simulatedFailure { throw simulatedFailure }
        for snapshot in snapshots { sessions[snapshot.id] = snapshot }
    }

    public func delete(sessionID: UUID) throws {
        if let simulatedFailure { throw simulatedFailure }
        sessions[sessionID] = nil
    }
}
