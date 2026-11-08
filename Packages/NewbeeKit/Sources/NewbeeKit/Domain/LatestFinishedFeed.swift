import Foundation

/// The most recent finished feed: the last breastfeed or the last bottle, whichever started later.
/// A breastfeed wins a tie. One rule for everything that counts "since the last feed": reminders
/// (`LastFeed`) and the Live Activity's since-last-feed count.
public enum LatestFinishedFeed: Sendable, Hashable {
    case breast(SessionSnapshot)
    case bottle(BottleEntry)

    public static func of(breast: SessionSnapshot?, bottle: BottleEntry?) -> LatestFinishedFeed? {
        switch (breast, bottle) {
        case let (breast?, bottle?): breast.startedAt >= bottle.startedAt ? .breast(breast) : .bottle(bottle)
        case let (breast?, nil): .breast(breast)
        case let (nil, bottle?): .bottle(bottle)
        case (nil, nil): nil
        }
    }

    public var id: UUID {
        switch self {
        case .breast(let session): session.id
        case .bottle(let bottle): bottle.id
        }
    }
}
