import NewbeeKit
import NewbeeShared
import SwiftUI

/// Opens after "Start on-call" on Home: the parent picks when their shift ends, then starts it.
/// The picker starts at the time picked last time (7:00 AM at first).
struct OnCallStartSheet: View {
    let model: NightShiftModel
    @Environment(\.dismiss) private var dismiss
    @State private var end: Date

    init(model: NightShiftModel, now: Date) {
        self.model = model
        _end = State(initialValue: model.schedule.morning(after: now))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: NBSpacing.l) {
                VStack(spacing: NBSpacing.s) {
                    Image(systemName: "moon.stars.fill")
                        .font(.largeTitle)
                        .foregroundStyle(NBColor.accent)
                        .accessibilityHidden(true)
                    Text("When does your shift end?")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(Self.caption(remindersOn: model.remindersAreOn))
                        .font(.subheadline)
                        .foregroundStyle(NBColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, NBSpacing.l)

                DatePicker("Ends at", selection: $end, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityIdentifier("nightShift.endPicker")

                Text(Self.endsText(endMinute: Self.minute(of: end), now: .now))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NBColor.secondaryText)

                Spacer(minLength: 0)

                Button {
                    let minute = Self.minute(of: end)
                    dismiss()
                    Task { await model.goOnDuty(endMinute: minute) }
                } label: {
                    Text("Start on-call")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
                .tint(NBColor.accent)
                .accessibilityIdentifier("nightShift.confirmStart")
            }
            .padding(.horizontal, NBSpacing.l)
            .padding(.bottom, NBSpacing.m)
            .background(NBColor.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Wording

    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func caption(remindersOn: Bool) -> String {
        remindersOn
            ? String(localized: "Until then, feed reminders ring only on your iPhone, so your partner can sleep.")
            : String(localized: "Until then, your partner's iPhone stays quiet, and they get a summary when it ends.")
    }

    /// "Ends today at 11:30 PM" or "Ends tomorrow at 7:00 AM": the next time the clock shows it.
    static func endsText(endMinute: Int, now: Date, calendar: Calendar = .current) -> String {
        let end = NightShiftSchedule(morningMinute: endMinute).morning(after: now, calendar: calendar)
        let time = end.formatted(date: .omitted, time: .shortened)
        return calendar.isDate(end, inSameDayAs: now)
            ? String(localized: "Ends today at \(time)")
            : String(localized: "Ends tomorrow at \(time)")
    }
}
