import Foundation
import NewbeeKit
import NewbeeShared
import SwiftUI

/// Display text for feeds, shared by History and Home.
enum FeedText {
    /// "90 mL" or "3 oz", in the unit the parent entered.
    static func volume(ml: Double, unit: VolumeUnit = .milliliters) -> String {
        let value = unit.fromMilliliters(ml)
        let digits = unit == .milliliters ? 0 : 1
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(unit.symbol)"
    }

    static func contents(_ contents: BottleContents) -> String {
        switch contents {
        case .breastMilk: String(localized: "breast milk")
        case .formula: String(localized: "formula")
        case .other: String(localized: "other")
        }
    }

    /// "Breast · 21 min" or "Bottle · 90 mL formula".
    static func title(_ entry: FeedEntry) -> String {
        switch entry.details {
        case .breast:
            String(localized: "Breast · \(DurationText.short(entry.breastDuration))")
        case .bottle(let bottle):
            String(localized: "Bottle · \(volume(ml: bottle.amountML, unit: bottle.enteredUnit)) \(contents(bottle.contents))")
        }
    }

    /// "L 12 min · R 9 min", for breastfeeds only.
    static func sides(_ entry: FeedEntry) -> String? {
        guard case let .breast(left, right, _, _) = entry.details else { return nil }
        return "L \(DurationText.short(left)) · R \(DurationText.short(right))"
    }

    /// "Today", "Yesterday" or "Tue 4 Nov".
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "2 h 14 min ago", or "Just now" under a minute.
    static func ago(_ interval: TimeInterval) -> String {
        interval < 60 ? String(localized: "Just now") : String(localized: "\(DurationText.short(interval)) ago")
    }
}

extension FeedEntry {
    /// Tint for the row rail and icon.
    var tint: Color {
        switch details {
        case .breast(_, _, _, let last): last.map(NBColor.side) ?? NBColor.left
        case .bottle(let bottle): bottle.contents == .formula ? NBColor.bottleFormula : NBColor.bottleBreastMilk
        }
    }

    var symbolName: String {
        switch details {
        case .breast: "heart.fill"
        case .bottle: "waterbottle.fill"
        }
    }
}

/// One feed in History: time, colored rail, title, L/R split, note, gap to the previous feed.
struct FeedRow: View {
    let row: TimelineRow

    private var entry: FeedEntry { row.entry }

    var body: some View {
        HStack(alignment: .top, spacing: NBSpacing.m) {
            Text(entry.start, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)

            Capsule()
                .fill(entry.tint)
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NBSpacing.xs) {
                HStack(spacing: NBSpacing.s) {
                    Image(systemName: entry.symbolName)
                        .foregroundStyle(entry.tint)
                        .accessibilityHidden(true)
                    Text(FeedText.title(entry))
                        .font(.body.weight(.semibold))
                    if entry.needsReview {
                        ReviewBadge()
                    }
                }
                if case let .breast(left, right, _, _) = entry.details {
                    SegmentBar(left: left, right: right, height: 6)
                    if let sides = FeedText.sides(entry) {
                        Text(sides)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if !entry.notes.isEmpty {
                    // Notes get their own soft block and room to read, not a 2-line preview.
                    Label {
                        Text(entry.notes)
                            .lineLimit(6)
                    } icon: {
                        Image(systemName: "note.text")
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, NBSpacing.s)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NBColor.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let gap = row.sincePrevious {
                    Label(String(localized: "\(DurationText.short(gap)) after the previous feed"), systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NBSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Small amber "Review" badge for feeds whose times were estimated.
struct ReviewBadge: View {
    var body: some View {
        Text("Review")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2), in: .capsule)
            .foregroundStyle(Color.orange)
            .accessibilityLabel("Needs review")
    }
}
