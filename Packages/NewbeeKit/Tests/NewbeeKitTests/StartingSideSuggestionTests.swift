import Foundation
import Testing
@testable import NewbeeKit

struct StartingSideSuggestionTests {
    @Test func defaultAlternatesFromTheSideTheLastFeedEndedOn() {
        let rule = StartingSideSuggestion()
        #expect(rule.mode == .alternate)
        #expect(rule.switchFrom == .ended)
        #expect(rule.suggestedSide(firstSide: .left, lastSide: .right) == .left)
        #expect(rule.suggestedSide(firstSide: .right, lastSide: .right) == .left)
    }

    @Test func alternatingFromTheStartingSide() {
        let rule = StartingSideSuggestion(mode: .alternate, switchFrom: .started)
        #expect(rule.suggestedSide(firstSide: .left, lastSide: .right) == .right)
        #expect(rule.suggestedSide(firstSide: .right, lastSide: .left) == .left)
        // One-sided feed: both readings agree.
        #expect(rule.suggestedSide(firstSide: .left, lastSide: .left) == .right)
    }

    @Test func alternatingOffersLeftBeforeTheFirstBreastfeed() {
        #expect(StartingSideSuggestion().suggestedSide(after: nil) == .left)
        #expect(StartingSideSuggestion(mode: .alternate, switchFrom: .started).suggestedSide(after: nil) == .left)
    }

    @Test func fixedSidesIgnoreHistory() {
        #expect(StartingSideSuggestion(mode: .alwaysLeft).suggestedSide(firstSide: .right, lastSide: .left) == .left)
        #expect(StartingSideSuggestion(mode: .alwaysRight).suggestedSide(firstSide: .left, lastSide: .right) == .right)
        #expect(StartingSideSuggestion(mode: .alwaysRight).suggestedSide(after: nil) == .right)
        // Switch from is kept for when the parent goes back to Alternate.
        #expect(StartingSideSuggestion(mode: .alwaysLeft, switchFrom: .started).switchFrom == .started)
    }
}
