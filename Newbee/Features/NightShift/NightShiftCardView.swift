import NewbeeKit
import NewbeeShared
import SwiftUI

/// Night Shift on Home (docs/NIGHT_SHIFT.md, docs/UX_SPEC.md §3.2): one card, and only when there
/// is something to say. In the evening it offers "Start your night shift"; during a shift it shows
/// who is on duty on both phones; in the morning the parent who slept gets "While you slept".
struct NightShiftCardView: View {
    let model: NightShiftModel
    let now: Date
    /// Recent finished feeds, newest first, for the morning summary.
    let entries: [FeedEntry]
    let volumeUnit: VolumeUnit

    var body: some View {
        if let card = model.card(at: now) {
            content(card)
                .alert(
                    "Night Shift",
                    isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private func content(_ card: NightShiftCard) -> some View {
        switch card {
        case .offerStart:
            // The whole card is the button: one tap, as big as the card.
            Button {
                Task { await model.goOnDuty() }
            } label: {
                Card(padding: NBSpacing.m) {
                    row(
                        symbol: "moon.stars.fill",
                        title: String(localized: "Start your night shift"),
                        subtitle: Self.offerSubtitle(until: model.schedule.morning(after: now), remindersOn: model.remindersAreOn)
                    ) {
                        // Looks like the End and Take over buttons on the other cards, so the
                        // card reads as something to tap, not as a status.
                        if model.isWorking {
                            ProgressView()
                        } else {
                            Text("Start")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, NBSpacing.m)
                                .padding(.vertical, NBSpacing.s)
                                .background(NBColor.accent, in: Capsule())
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
            .accessibilityLabel("Start your night shift")
            .accessibilityIdentifier("nightShift.start")
        case .onDuty(let until):
            Card(padding: NBSpacing.m) {
                row(
                    symbol: "moon.stars.fill",
                    title: String(localized: "You're on duty"),
                    subtitle: Self.onDutySubtitle(until: until, remindersOn: model.remindersAreOn)
                ) {
                    Button("End") { model.endShift() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("End shift")
                        .accessibilityIdentifier("nightShift.end")
                }
            }
        case .partnerOnDuty(let until):
            Card(padding: NBSpacing.m) {
                row(
                    symbol: "moon.zzz.fill",
                    title: String(localized: "Your partner is on duty"),
                    subtitle: String(localized: "Until \(Self.time(until)). This iPhone stays quiet.")
                ) {
                    Button("Take over") {
                        Task { await model.goOnDuty() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("nightShift.takeOver")
                }
            }
        case .summary(let shift):
            let summary = NightSummary(shift: shift, feeds: entries)
            Card(padding: NBSpacing.m) {
                row(
                    symbol: "sun.max.fill",
                    title: String(localized: "While you slept"),
                    subtitle: Self.summaryHeadline(summary),
                    detail: Self.summaryDetail(summary, unit: volumeUnit)
                ) {
                    Button {
                        model.dismissSummary(of: shift)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(NBColor.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .accessibilityIdentifier("nightShift.dismiss")
                }
            }
        }
    }

    /// Symbol, two or three lines of text, and one control on the right.
    private func row<Trailing: View>(
        symbol: String,
        title: String,
        titleColor: Color = .primary,
        subtitle: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: NBSpacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(NBColor.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(titleColor)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(NBColor.secondaryText)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(NBColor.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing()
        }
    }

    // MARK: - Wording

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func offerSubtitle(until: Date, remindersOn: Bool) -> String {
        remindersOn
            ? String(localized: "You get the feed reminders until \(time(until)), so your partner can sleep.")
            : String(localized: "Until \(time(until)). Your partner gets a summary of the night in the morning.")
    }

    static func onDutySubtitle(until: Date, remindersOn: Bool) -> String {
        remindersOn
            ? String(localized: "Until \(time(until)). Feed reminders ring only on this iPhone.")
            : String(localized: "Until \(time(until)). Feed reminders are off.")
    }

    static func summaryHeadline(_ summary: NightSummary) -> String {
        guard let last = summary.lastFeedStart, summary.feeds > 0 else {
            return String(localized: "No feeds were logged.")
        }
        return summary.feeds == 1
            ? String(localized: "1 feed, at \(time(last))")
            : String(localized: "\(summary.feeds) feeds, the last at \(time(last))")
    }

    /// "32 min nursing · 4 oz by bottle", or `nil` on a night without feeds.
    static func summaryDetail(_ summary: NightSummary, unit: VolumeUnit) -> String? {
        var parts: [String] = []
        if summary.breastfeeds > 0 {
            parts.append(String(localized: "\(DurationText.short(summary.nursing)) nursing"))
        }
        if summary.bottles > 0 {
            parts.append(String(localized: "\(FeedText.volume(ml: summary.bottleML, unit: unit)) by bottle"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
