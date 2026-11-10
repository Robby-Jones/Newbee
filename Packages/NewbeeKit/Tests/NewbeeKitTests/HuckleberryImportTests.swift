import Foundation
import Testing
@testable import NewbeeKit

private let oslo = TimeZone(identifier: "Europe/Oslo")!
private let utc = TimeZone(identifier: "UTC")!
/// Well after every row in the fixtures.
private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15

private func local(_ text: String, _ zone: TimeZone = utc) -> Date {
    HuckleberryCSV.date(text, in: zone)!
}

private let header = #""Type","Start","End","Duration","Start Condition","Start Location","End Condition","Notes""#

/// Every row shape seen in real Huckleberry exports, newest first like the app writes them.
private let sample = [
    header,
    #""Sleep","2026-09-01 19:32","2026-09-02 06:57","11:25",,,,"#,
    #""Feed","2026-09-01 22:00","2026-09-01 22:18","00:18",,"Breast","00:18L","#,
    #""Feed","2026-09-01 20:00","2026-09-01 20:29","00:29","00:29R","Breast",,"#,
    #""Feed","2026-09-01 17:00","2026-09-01 17:14","00:14","00:07R","Breast","00:06L","fussy, then ""settled""""#,
    #""Feed","2026-09-01 14:00",,,"Mixed","Bottle","90ml","#,
    #""Feed","2026-09-01 11:00",,,"Breast Milk","Bottle","4.0oz","#,
    #""Feed","2026-09-01 08:00",,,"Formula","Bottle","120ml","#,
    #""Diaper","2026-09-01 09:00",,"yellow",,,"Both, pee:large poo:small","#,
    #""Pump","2026-09-01 03:00",,"00:20","100ml",,"120ml","#,
    #""Growth","2026-08-09 15:28",,,"11.8lb","1.92ft.in",,"#,
    #""Tummy time","2026-09-01 16:02","2026-09-01 16:04","00:02",,,,"#,
].joined(separator: "\r\n") + "\r\n"

@Suite("CSV reader")
struct CSVTableTests {
    @Test func readsQuotedFieldsCommasQuotesAndLineBreaks() {
        let rows = CSVTable.parse("\u{FEFF}a,\"b, c\",\"say \"\"hi\"\"\"\r\n\"line\nbreak\",,x\n\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["line\nbreak", "", "x"]])
    }

    @Test func keepsTrailingEmptyFieldsAndALastLineWithoutNewline() {
        #expect(CSVTable.parse("a,,\nb,c") == [["a", "", ""], ["b", "c"]])
    }
}

@Suite("Huckleberry import")
struct HuckleberryImportTests {
    @Test func readsFeedsAndPumpingAndCountsTheRest() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now)
        #expect(export.rowCount == 11)
        #expect(export.problems.isEmpty)
        #expect(export.records.count == 7)
        #expect(export.unsupported == ["Sleep": 1, "Diaper": 1, "Growth": 1, "Tummy time": 1])
    }

    @Test func nursingRowsBecomeBackToBackSegmentsTaggedImported() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now)
        let sessions = export.records.compactMap { record -> SessionSnapshot? in
            if case .breast(let session) = record { return session }
            return nil
        }
        #expect(sessions.count == 3)

        let both = try #require(sessions.first { $0.startedAt == local("2026-09-01 17:00") })
        #expect(both.segments.map(\.side) == [.left, .right]) // default order when both were used
        #expect(both.duration(on: .left, at: now) == 6 * 60)
        #expect(both.duration(on: .right, at: now) == 7 * 60)
        #expect(both.endedAt == local("2026-09-01 17:13"))
        #expect(both.status == .completed)
        #expect(both.source == .imported)
        #expect(both.notes == "fussy, then \"settled\"")
        #expect(SessionValidator.isValid(both, now: now))

        let rightOnly = try #require(sessions.first { $0.startedAt == local("2026-09-01 20:00") })
        #expect(rightOnly.segments.map(\.side) == [.right])
        #expect(rightOnly.feedingDuration(at: now) == 29 * 60)

        let leftOnly = try #require(sessions.first { $0.startedAt == local("2026-09-01 22:00") })
        #expect(leftOnly.segments.map(\.side) == [.left])
    }

    @Test func firstSideOptionOrdersFeedsThatUsedBoth() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now, options: .init(firstSideWhenBoth: .right))
        let both = export.records.compactMap { record -> SessionSnapshot? in
            if case .breast(let session) = record, session.segments.count == 2 { return session }
            return nil
        }
        #expect(both.first?.segments.map(\.side) == [.right, .left])
    }

    @Test func bottlesKeepContentsAndTheUnitTheyWereEnteredIn() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now)
        let bottles = export.records.compactMap { record -> BottleEntry? in
            if case .bottle(let entry) = record { return entry }
            return nil
        }
        #expect(bottles.count == 3)

        let formula = try #require(bottles.first { $0.contents == .formula })
        #expect(formula.amountML == 120)
        #expect(formula.enteredUnit == .milliliters)
        #expect(formula.startedAt == local("2026-09-01 08:00"))
        #expect(formula.durationSeconds == nil)

        let milk = try #require(bottles.first { $0.contents == .breastMilk })
        #expect(milk.enteredUnit == .fluidOunces)
        #expect(abs(milk.amountML - 4 * VolumeUnit.millilitersPerFluidOunce) < 0.001)

        let mixed = try #require(bottles.first { $0.contents == .other })
        #expect(mixed.amountML == 90)
        #expect(mixed.notes == "Mixed breast milk and formula")
    }

    @Test func pumpingReadsLeftThenRightAndItsDuration() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now)
        let pump = try #require(export.records.compactMap { record -> PumpEntry? in
            if case .pump(let entry) = record { return entry }
            return nil
        }.first)
        #expect(pump.leftML == 100)
        #expect(pump.rightML == 120)
        #expect(pump.durationSeconds.map { $0 - 20 * 60 } == 0, "\(String(describing: pump.durationSeconds?.bitPattern))")
        #expect(pump.startedAt == local("2026-09-01 03:00"))
    }

    @Test func oneSidedPumpingInOunces() throws {
        let csv = header + "\n" + #""Pump","2026-09-01 03:00",,,,,"3.5oz","#
        let export = try HuckleberryCSV.parse(csv, timeZone: utc, now: now)
        guard case .pump(let pump) = export.records.first else {
            Issue.record("expected a pumping session")
            return
        }
        #expect(pump.leftML == 0)
        #expect(pump.enteredUnit == .fluidOunces)
        #expect(abs(pump.rightML - 3.5 * VolumeUnit.millilitersPerFluidOunce) < 0.001)
    }

    @Test func timesAreReadInTheGivenTimeZone() throws {
        let csv = header + "\n" + #""Feed","2026-07-16 13:07",,,"Formula","Bottle","60ml","#
        let export = try HuckleberryCSV.parse(csv, timeZone: oslo, now: now)
        // Oslo is UTC+2 in July.
        #expect(export.records.first?.start == local("2026-07-16 11:07", utc))
        if case .bottle(let entry) = export.records.first {
            #expect(entry.timeZoneID == "Europe/Oslo")
        }
    }

    @Test func aLocalTimeSkippedBySpringingForwardStillImports() {
        // Clocks in Oslo jumped from 02:00 to 03:00 on 2026-03-29.
        let date = HuckleberryCSV.date("2026-03-29 02:30", in: oslo)
        #expect(date != nil)
        #expect(HuckleberryCSV.date("2026-02-30 10:00", in: oslo) == nil)
        #expect(HuckleberryCSV.date("2026-09-01", in: oslo) == nil)
        #expect(HuckleberryCSV.date("09/01/2026 10:00", in: oslo) == nil)
        #expect(HuckleberryCSV.date("2026-09-01 10:00:30", in: utc) == local("2026-09-01 10:00").addingTimeInterval(30))
    }

    @Test func badRowsAreReportedNotGuessed() throws {
        let csv = [
            header,
            #""Feed","yesterday",,,"Formula","Bottle","60ml","#,
            #""Feed","2026-09-01 08:00",,,"Formula","Bottle","a lot","#,
            #""Feed","2026-09-01 08:00",,,"Formula","Bottle","2cups","#,
            #""Feed","2026-09-01 08:00",,,"Formula","Bottle","900ml","#,
            #""Feed","2026-09-01 08:00",,,"Formula","Bottle","0ml","#,
            #""Feed","2026-09-01 09:00","2026-09-01 09:10","00:10",,"Breast",,"#,
            #""Feed","2026-09-01 09:00",,,"7 minutes","Breast",,"#,
            #""Feed","2026-09-01 09:00",,,"05:00R","Breast",,"#,
            #""Feed","2026-09-01 09:00",,,"Formula","Cup","60ml","#,
            #""Feed","2030-01-01 09:00",,,"Formula","Bottle","60ml","#,
            #""Pump","2026-09-01 03:00",,,,,,"#,
            #",,,,,,,"#,
        ].joined(separator: "\n")
        let export = try HuckleberryCSV.parse(csv, timeZone: utc, now: now)
        #expect(export.records.isEmpty)
        #expect(export.rowCount == 11)
        #expect(export.problems.map(\.reason) == [
            .unreadableTime,
            .unreadableAmount("a lot"),
            .unreadableAmount("2cups"),
            .bottle(.amountTooLarge(maximumML: 500)),
            .bottle(.amountNotPositive),
            .noSideTimes,
            .unreadableSideTime("7 minutes"),
            .breastfeedTooLong,
            .unknownFeedKind("Cup"),
            .bottle(.startInFuture),
            .pump(.amountNotPositive),
        ])
        #expect(export.problems.first?.line == 2)
        #expect(export.problems.first?.start == "yesterday")
    }

    @Test func rejectsFilesThatArentHuckleberryExports() {
        #expect(throws: HuckleberryCSV.ParseError.empty) { try HuckleberryCSV.parse("") }
        let newbee = FeedCSV.header.joined(separator: ",") + "\r\n"
        // Newbee's own export shares only "type" and "notes".
        let missing = ["Start", "End", "Duration", "Start Condition", "Start Location", "End Condition"]
        #expect(throws: HuckleberryCSV.ParseError.notHuckleberry(missingColumns: missing)) {
            try HuckleberryCSV.parse(newbee)
        }
    }

    @Test func headerMatchIgnoresCaseAndColumnOrder() throws {
        let csv = "notes,TYPE,start,end,duration,start condition,start location,end condition\n"
            + "hi,Feed,2026-09-01 08:00,,,Formula,Bottle,60ml\n"
        let export = try HuckleberryCSV.parse(csv, timeZone: utc, now: now)
        guard case .bottle(let entry) = export.records.first else {
            Issue.record("expected a bottle")
            return
        }
        #expect(entry.notes == "hi")
        #expect(entry.amountML == 60)
    }
}

@Suite("Import plan")
struct ImportPlanTests {
    @Test func leavesOutWhatNewbeeAlreadyHasAndRepeatsWithinTheFile() throws {
        let export = try HuckleberryCSV.parse(sample + #""Feed","2026-09-01 08:00",,,"Formula","Bottle","120ml","# + "\r\n", timeZone: utc, now: now)
        // Newbee already has the 11:00 bottle, logged a few seconds into the minute.
        let existing = [ImportKey(kind: .bottle, start: local("2026-09-01 11:00").addingTimeInterval(42))]
        let plan = ImportPlan(export: export, existing: existing)
        #expect(plan.duplicates == 2)
        #expect(plan.bottleCount == 2)
        #expect(plan.breastCount == 3)
        #expect(plan.pumpCount == 1)
        #expect(plan.records.map(\.start) == plan.records.map(\.start).sorted())
        #expect(plan.dateRange == local("2026-09-01 03:00")...local("2026-09-01 22:00"))
        #expect(plan.unsupportedCount == 4)
    }

    @Test func sameMinuteButDifferentKindIsNotADuplicate() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now)
        let existing = [ImportKey(kind: .breast, start: local("2026-09-01 08:00"))]
        #expect(ImportPlan(export: export, existing: existing).duplicates == 0)
    }

    @Test func reimportingTheSameFileAddsNothing() throws {
        let export = try HuckleberryCSV.parse(sample, timeZone: utc, now: now)
        let first = ImportPlan(export: export, existing: [])
        let again = ImportPlan(export: export, existing: first.records.map(ImportKey.init))
        #expect(again.isEmpty)
        #expect(again.duplicates == 7)
    }

    @Test func unsupportedTypesAreListedLargestFirst() throws {
        var export = HuckleberryExport()
        export.unsupported = ["Sleep": 3, "Diaper": 5, "Bath": 3]
        let plan = ImportPlan(export: export, existing: [])
        #expect(plan.unsupported.map(\.type) == ["Diaper", "Bath", "Sleep"])
    }
}
