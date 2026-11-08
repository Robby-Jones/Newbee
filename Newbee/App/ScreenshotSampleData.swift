import Foundation
import NewbeeKit
import SwiftData

/// Sample feeds for the App Store screenshots (`NewbeeUITests/AppStoreScreenshots.swift`).
///
/// Only runs under UI tests (`-uiTesting`, an in-memory store) with `-screenshotData`, so it can
/// never touch a real store. `-screenshotActiveFeed` also starts a breastfeed 12 minutes ago.
@MainActor
enum ScreenshotSampleData {
    static var isRequested: Bool {
        AppConfiguration.isUITesting && ProcessInfo.processInfo.arguments.contains("-screenshotData")
    }

    static var wantsActiveFeed: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotActiveFeed")
    }

    static func seed(into container: ModelContainer, clock: any AppClock) {
        let context = ModelContext(container)
        let now = clock.instant()
        let calendar = Calendar.current

        let baby = Baby(name: "Ella", birthDate: calendar.date(byAdding: .day, value: -24, to: now.wall))
        baby.createdAt = now.wall.addingTimeInterval(-24 * 86_400)
        context.insert(baby)

        // A steady, slightly irregular newborn day: a feed about every 2.5 to 3.5 hours, mostly
        // breast, a couple of bottles, and one pumping session. Deterministic, so screenshots
        // look the same on every run.
        var generator = SeededGenerator(seed: 7)
        let lastFeedEnd = now.wall.addingTimeInterval(wantsActiveFeed ? -2.3 * 3_600 : -1.4 * 3_600)
        var start = lastFeedEnd.addingTimeInterval(-24 * 60)
        var index = 0
        let earliest = now.wall.addingTimeInterval(-14 * 86_400)
        var nextSide: Side = .left
        while start > earliest {
            let hour = calendar.component(.hour, from: start)
            if index % 5 == 2 {
                let ounces = [3.0, 3.5, 4.0][Int.random(in: 0...2, using: &generator)]
                let contents: BottleContents = index % 2 == 0 ? .breastMilk : .formula
                insertBottle(at: start, ounces: ounces, contents: contents, baby: baby, in: context)
            } else {
                let first = Double(Int.random(in: 9...16, using: &generator)) * 60
                let second = Double(Int.random(in: 6...13, using: &generator)) * 60
                insertBreast(at: start, first: (nextSide, first), second: (nextSide.opposite, second), baby: baby, in: context)
                nextSide = nextSide.opposite
            }
            // Once a day, mid-morning, a pumping session.
            if (9...11).contains(hour) {
                insertPump(at: start.addingTimeInterval(-50 * 60), leftOunces: 2.0, rightOunces: 2.5, baby: baby, in: context)
            }
            let gapHours = Double(Int.random(in: 150...210, using: &generator)) / 60
            start = start.addingTimeInterval(-gapHours * 3_600)
            index += 1
        }

        if wantsActiveFeed {
            insertActiveBreast(startedSecondsAgo: 12 * 60 + 34, side: .left, now: now, baby: baby, in: context)
        }
        try? context.save()
    }

    private static func insertBreast(
        at start: Date, first: (Side, TimeInterval), second: (Side, TimeInterval), baby: Baby, in context: ModelContext
    ) {
        let session = FeedingSession(kind: .breast, status: .completed, startedAt: start)
        context.insert(session)
        session.baby = baby
        let firstEnd = start.addingTimeInterval(first.1)
        let secondEnd = firstEnd.addingTimeInterval(second.1)
        let segments = [
            FeedingSegment(side: first.0, startedAt: start, endedAt: firstEnd),
            FeedingSegment(side: second.0, startedAt: firstEnd, endedAt: secondEnd),
        ]
        for segment in segments {
            context.insert(segment)
            segment.session = session
        }
        session.endedAt = secondEnd
        session.createdAt = start
        session.modifiedAt = secondEnd
    }

    private static func insertActiveBreast(
        startedSecondsAgo: TimeInterval, side: Side, now: Instant, baby: Baby, in context: ModelContext
    ) {
        let start = now.wall.addingTimeInterval(-startedSecondsAgo)
        let session = FeedingSession(kind: .breast, status: .active, startedAt: start)
        context.insert(session)
        session.baby = baby
        let segment = FeedingSegment(
            side: side,
            startedAt: start,
            startMonotonic: now.monotonic.map { $0 - startedSecondsAgo },
            startBootID: now.bootID
        )
        context.insert(segment)
        segment.session = session
        session.createdAt = start
        session.modifiedAt = start
    }

    private static func insertBottle(
        at start: Date, ounces: Double, contents: BottleContents, baby: Baby, in context: ModelContext
    ) {
        let session = FeedingSession(kind: .bottle, status: .completed, startedAt: start, source: .manual)
        context.insert(session)
        session.baby = baby
        session.endedAt = start
        let details = BottleDetails(
            contents: contents,
            amountML: ounces * VolumeUnit.millilitersPerFluidOunce,
            enteredUnit: .fluidOunces
        )
        context.insert(details)
        session.bottle = details
        session.createdAt = start
        session.modifiedAt = start
    }

    private static func insertPump(
        at start: Date, leftOunces: Double, rightOunces: Double, baby: Baby, in context: ModelContext
    ) {
        let session = FeedingSession(kind: .pump, status: .completed, startedAt: start, source: .manual)
        context.insert(session)
        session.baby = baby
        session.endedAt = start.addingTimeInterval(15 * 60)
        let details = PumpDetails(
            leftML: leftOunces * VolumeUnit.millilitersPerFluidOunce,
            rightML: rightOunces * VolumeUnit.millilitersPerFluidOunce,
            enteredUnit: .fluidOunces,
            durationSeconds: 15 * 60
        )
        context.insert(details)
        session.pump = details
        session.createdAt = start
        session.modifiedAt = start
    }
}

/// A tiny deterministic random number generator (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
