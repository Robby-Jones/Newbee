import Foundation
import Testing
import UserNotifications
@testable import Newbee

/// The step from a planned reminder's moment to the trigger iOS keeps. A trigger built from
/// "floating" components (no time zone) fires at the same clock time in whatever zone the phone
/// is in by then, so a reminder would move after travel or misfire around a daylight saving change.
@Suite("Reminder triggers")
struct ReminderTriggerTests {
    /// A whole second two hours from now: `nextTriggerDate()` counts from the real clock.
    private var soon: Date {
        Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 2 * 3_600).rounded(.down))
    }

    @Test func componentsCarryTheirTimeZoneAndCalendar() {
        let components = SystemNotificationClient.triggerComponents(for: soon)
        #expect(components.timeZone == TimeZone(identifier: "UTC"))
        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.date == soon)
    }

    @Test func triggerFiresAtTheExactMoment() {
        let trigger = SystemNotificationClient.trigger(for: soon)
        #expect(trigger.nextTriggerDate() == soon)
        #expect(!trigger.repeats)
    }

    /// The simulator runs in one zone; spelling the same moment in zones far from it proves iOS
    /// reads the zone attached to the components, not the phone's own.
    @Test(arguments: ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati"])
    func triggerHonorsTheComponentsTimeZone(zone: String) throws {
        let fireDate = soon
        let components = SystemNotificationClient.triggerComponents(for: fireDate, in: try #require(TimeZone(identifier: zone)))
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        #expect(trigger.nextTriggerDate() == fireDate)
    }

    @Test func theRepeatedHourOnFallBackNightIsUnambiguous() throws {
        // 2026-11-01 01:30 EST, the second 01:30 that night in New York.
        let secondHalfPastOne = Date(timeIntervalSince1970: 1_793_514_600)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(newYork.dateComponents([.hour, .minute], from: secondHalfPastOne) == DateComponents(hour: 1, minute: 30))
        #expect(newYork.timeZone.isDaylightSavingTime(for: secondHalfPastOne) == false)

        // In UTC the moment has one spelling, so it maps back to itself.
        let components = SystemNotificationClient.triggerComponents(for: secondHalfPastOne)
        #expect(components.hour == 6 && components.minute == 30)
        #expect(components.date == secondHalfPastOne)
    }
}
