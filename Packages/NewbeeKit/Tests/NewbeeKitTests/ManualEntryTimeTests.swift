import Foundation
import Testing
@testable import NewbeeKit

@Suite("Manual entry time")
struct ManualEntryTimeTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// 2026-11-08 07:23 UTC.
    var now: Date { date(8, 7, 23) }

    @Test func noSelectionOrTodayIsNow() {
        #expect(ManualEntryTime.reference(onDay: nil, now: now, calendar: calendar) == now)
        #expect(ManualEntryTime.reference(onDay: date(8), now: now, calendar: calendar) == now)
    }

    @Test func pastDayKeepsTheTimeOfDay() {
        #expect(ManualEntryTime.reference(onDay: date(3), now: now, calendar: calendar) == date(3, 7, 23))
        #expect(ManualEntryTime.reference(onDay: date(3, 18), now: now, calendar: calendar) == date(3, 7, 23))
    }

    @Test func futureDayIsClampedToNow() {
        #expect(ManualEntryTime.reference(onDay: date(10), now: now, calendar: calendar) == now)
    }
}
