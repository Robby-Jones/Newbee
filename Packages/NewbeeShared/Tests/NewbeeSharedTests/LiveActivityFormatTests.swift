import Testing
@testable import NewbeeShared

@Suite("Live Activity duration text")
struct LiveActivityFormatTests {
    @Test(arguments: [
        (0.0, "0:00"), (7.9, "0:07"), (725, "12:05"), (3599, "59:59"), (3600, "1:00:00"),
        (3723, "1:02:03"), (-5, "0:00"), (.nan, "0:00"), (.infinity, "0:00"),
    ])
    func clock(seconds: Double, expected: String) {
        #expect(LiveActivityFormat.clock(seconds) == expected)
    }

    @Test(arguments: [(0.0, "0m"), (725, "12m"), (3900, "1h 05m")])
    func compact(seconds: Double, expected: String) {
        #expect(LiveActivityFormat.compact(seconds) == expected)
    }

    @Test(arguments: [
        (0.0, "0 seconds"), (1, "1 second"), (725, "12 minutes 5 seconds"), (60, "1 minute"),
        (3725, "1 hour 2 minutes"), (7200, "2 hours"),
    ])
    func spoken(seconds: Double, expected: String) {
        #expect(LiveActivityFormat.spoken(seconds) == expected)
    }
}
