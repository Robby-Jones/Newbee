import Foundation
import NewbeeKit
@testable import NewbeeShared
import Testing

struct LiveActivityColorTests {
    @Test func everyChoiceRoundTripsThroughItsRawValue() {
        let all: [LiveActivityColor] = [.matchTheme, .black] + LiveActivityColor.lightCards + LiveActivityColor.darkCards
        #expect(all.count == 2 + 2 * NBTheme.allCases.count)
        for color in all {
            #expect(LiveActivityColor(rawValue: color.rawValue) == color)
        }
        #expect(LiveActivityColor.light(.pink).rawValue == "light.pink")
        #expect(LiveActivityColor.dark(.standard).rawValue == "dark.standard")
        #expect(LiveActivityColor(rawValue: "light.mauve") == nil)
        #expect(LiveActivityColor(rawValue: "medium.pink") == nil)
        #expect(LiveActivityColor(rawValue: "pink") == nil)
    }

    @Test func matchFollowsTheThemeAsBeforeAndAPickedCardDoesNot() {
        // Black for Indigo, as it always was; the theme's light card otherwise.
        #expect(LiveActivityColor.matchTheme.card(for: .standard) == .black)
        #expect(LiveActivityColor.matchTheme.card(for: .pink) == .light(.pink))
        #expect(LiveActivityColor.matchTheme.card(for: .peach) == .light(.peach))
        #expect(LiveActivityColor.dark(.sage).card(for: .pink) == .dark(.sage))
        #expect(LiveActivityColor.black.card(for: .ocean) == .black)
    }

    @Test func contentCodesTheColorAsAStringAndAnUnknownOneReadsAsMatch() throws {
        var state = FeedingActivityAttributes.ContentState(
            status: .ended, currentSide: .left, sessionStart: Date(timeIntervalSince1970: 0),
            currentSegmentStart: nil, leftAccumulated: 60, rightAccumulated: 0,
            pausedAt: Date(timeIntervalSince1970: 60), revision: 1
        )
        state.cardColor = .dark(.ocean)
        let data = try JSONEncoder().encode(state)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"cardColor\":\"dark.ocean\""))
        #expect(try JSONDecoder().decode(FeedingActivityAttributes.ContentState.self, from: data) == state)

        let newer = json.replacingOccurrences(of: "dark.ocean", with: "glow.ocean")
        let decoded = try JSONDecoder().decode(FeedingActivityAttributes.ContentState.self, from: Data(newer.utf8))
        #expect(decoded.cardColor == .matchTheme)

        // Content from older builds has no color: "Match app theme".
        state.cardColor = nil
        let older = try JSONDecoder().decode(
            FeedingActivityAttributes.ContentState.self, from: JSONEncoder().encode(state)
        )
        #expect(older.cardColor == nil)
    }
}
