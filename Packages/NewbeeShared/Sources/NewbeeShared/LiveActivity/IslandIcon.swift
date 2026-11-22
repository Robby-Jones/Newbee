import Foundation

/// Settings → Appearance → Live Activity → "Island icon": what the minimized Dynamic Island shows
/// beside the count once a feed has ended. `bee` is the default. Kept on this phone only, like the
/// Live Activity color.
public enum IslandIcon: String, CaseIterable, Hashable, Sendable {
    /// The tiny bee from the Lock Screen avatar.
    case bee
    /// The baby's photo, cropped round; the bee when no photo is saved.
    case babyPhoto = "photo"
    /// The last feed's duotone icon: breastfeed in the side's color, or the bottle.
    case lastFeed
    /// The clock earlier builds showed.
    case clock
}

extension IslandIcon: Codable {
    /// An unknown value (from a newer build) reads as the bee rather than failing the whole content.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = IslandIcon(rawValue: value) ?? .bee
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
