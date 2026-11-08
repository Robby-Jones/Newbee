import NewbeeKit
import NewbeeShared
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// First-run onboarding (docs/UX_SPEC.md §3.1): three full-screen steps, all skippable.
///
/// 1. Welcome, with the privacy promise.
/// 2. Baby: photo, nickname and birth date (all optional) and the bottle unit.
/// 3. Stay in the loop: what the Live Activity shows, and an optional feeding reminder.
///    Notification permission is asked for only if the parent turns the reminder on here.
///
/// Whatever was entered is saved on both Skip and Finish. Everything can be changed later in
/// Settings.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Hashable {
        case welcome, baby, stayInTheLoop
    }

    /// Called after the profile is saved, on Skip or Finish.
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var draft = OnboardingProfile.Draft()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $step) {
                WelcomeStep()
                    .tag(Step.welcome)
                BabyStep(draft: $draft)
                    .tag(Step.baby)
                StayInTheLoopStep()
                    .tag(Step.stayInTheLoop)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: NBSpacing.l) {
                PageDots(count: Step.allCases.count, current: step.rawValue)
                Button(action: next) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: NBLayout.primaryControlHeight - 4)
                        .foregroundStyle(.white)
                        .background(NBColor.accent, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.next")
            }
            .padding(.horizontal, NBSpacing.xl)
            .padding(.bottom, NBSpacing.l)
        }
        .background(NBColor.canvas.ignoresSafeArea())
        .interactiveDismissDisabled()
        .animation(reduceMotion ? nil : .nbState, value: step)
    }

    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button {
                    go(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: NBLayout.minHitTarget, height: NBLayout.minHitTarget)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            if step != .stayInTheLoop {
                Button("Skip", action: finish)
                    .font(.body.weight(.medium))
                    .frame(minHeight: NBLayout.minHitTarget)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .foregroundStyle(NBColor.accent)
        .padding(.horizontal, NBSpacing.m)
        .frame(height: NBLayout.minHitTarget + NBSpacing.s)
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .welcome: "Get started"
        case .baby: "Continue"
        case .stayInTheLoop: "Start tracking"
        }
    }

    private func next() {
        if let following = Step(rawValue: step.rawValue + 1) {
            go(to: following)
        } else {
            finish()
        }
    }

    private func go(to target: Step) {
        hideKeyboard()
        step = target
    }

    private func finish() {
        hideKeyboard()
        try? OnboardingProfile.save(draft, in: context)
        onFinish()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Profile

/// Saves what onboarding collected about the baby. Kept apart from the view so it can be tested.
enum OnboardingProfile {
    struct Draft: Equatable {
        var name = ""
        var hasBirthDate = false
        var birthDate = Calendar.current.startOfDay(for: .now)

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var isEmpty: Bool { trimmedName.isEmpty && !hasBirthDate }
    }

    /// Writes the name and birth date into the first `Baby`. A `Baby` is created only when
    /// something was entered, the same as Settings, which creates it on the first edit.
    static func save(_ draft: Draft, in context: ModelContext) throws {
        guard !draft.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])).first
        let baby = existing ?? Baby()
        if existing == nil { context.insert(baby) }
        if !draft.trimmedName.isEmpty { baby.name = draft.trimmedName }
        if draft.hasBirthDate { baby.birthDate = draft.birthDate }
        try context.save()
    }

    /// True when the store already has a baby or any feed: someone updating from a build
    /// without onboarding, who shouldn't be walked through setup again.
    static func hasExistingData(in context: ModelContext) -> Bool {
        let babies = (try? context.fetchCount(FetchDescriptor<Baby>())) ?? 0
        let sessions = (try? context.fetchCount(FetchDescriptor<FeedingSession>())) ?? 0
        return babies + sessions > 0
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: NBSpacing.xl) {
                Spacer(minLength: NBSpacing.l)
                FeedButtonsIllustration()
                StepHeading(
                    title: "Track feeds in two taps",
                    subtitle: "Time each breast, log bottles and pumping, and see your baby's patterns at a glance."
                )
                VStack(alignment: .leading, spacing: NBSpacing.m) {
                    FeatureRow(symbol: "timer", tint: NBColor.leftInk, text: "A timer that keeps going when your iPhone is locked")
                    FeatureRow(symbol: "clock.arrow.circlepath", tint: NBColor.rightInk, text: "Time since the last feed, always one glance away")
                    FeatureRow(symbol: "lock.fill", tint: NBColor.accent, text: "Your data stays on this iPhone")
                }
                .padding(NBSpacing.l)
                .nbCardBackground()
            }
            .padding(.horizontal, NBSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The three round Home buttons (Left, Right, Bottle) in miniature.
private struct FeedButtonsIllustration: View {
    var body: some View {
        HStack(spacing: NBSpacing.m) {
            bubble(fill: NBColor.left) { Text("L").font(.title.weight(.bold)) }
            bubble(fill: NBColor.right, size: 96) { Text("R").font(.largeTitle.weight(.bold)) }
            bubble(fill: NBColor.bottleBreastMilk) { Image(systemName: "waterbottle.fill").font(.title) }
        }
        .foregroundStyle(NBColor.onSide)
        .accessibilityHidden(true)
    }

    private func bubble<Content: View>(fill: Color, size: CGFloat = 76, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .shadow(color: fill.opacity(0.4), radius: 10, y: 4)
    }
}

// MARK: - Step 2: Baby

private struct BabyStep: View {
    @Binding var draft: OnboardingProfile.Draft
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(BabyPhotoStore.self) private var photo: BabyPhotoStore?

    var body: some View {
        ScrollView {
            VStack(spacing: NBSpacing.xl) {
                if let photo {
                    PhotoPickerBubble(store: photo)
                }
                StepHeading(title: "About your baby", subtitle: "All optional. You can change these anytime in Settings.")

                VStack(spacing: 0) {
                    TextField("Name or nickname", text: $draft.name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .padding(.vertical, NBSpacing.m)
                        .accessibilityIdentifier("onboarding.babyName")
                    Divider()
                    Toggle("Birth date", isOn: $draft.hasBirthDate.animation())
                        .tint(NBColor.accent)
                        .padding(.vertical, NBSpacing.s)
                        .accessibilityIdentifier("onboarding.birthDateToggle")
                    if draft.hasBirthDate {
                        Divider()
                        DatePicker("Born", selection: $draft.birthDate, in: ...Date.now, displayedComponents: .date)
                            .padding(.vertical, NBSpacing.s)
                    }
                }
                .padding(.horizontal, NBSpacing.l)
                .nbCardBackground()

                if let preferences {
                    UnitPicker(preferences: preferences)
                }
            }
            .padding(.horizontal, NBSpacing.xl)
            .padding(.top, NBSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A large avatar that opens the photo picker, like the profile photo step in other baby apps.
private struct PhotoPickerBubble: View {
    let store: BabyPhotoStore
    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        // Read on the main actor here: the picker's label closure is Sendable.
        let image = store.image
        let badge = isLoading ? "hourglass" : "camera.fill"
        VStack(spacing: NBSpacing.s) {
            PhotosPicker(selection: $selection, matching: .images) {
                BabyAvatar(image: image, size: 112)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: badge)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(NBColor.accent, in: .circle)
                            .overlay(Circle().strokeBorder(NBColor.canvas, lineWidth: 3))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.image == nil ? "Add photo" : "Change photo")
            .accessibilityIdentifier("onboarding.photo")
            Text(store.image == nil ? "Add a photo" : "Looking good!")
                .font(.subheadline)
                .foregroundStyle(NBColor.secondaryText)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(NBColor.destructive)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                isLoading = true
                defer {
                    isLoading = false
                    selection = nil
                }
                do {
                    try await store.save(item)
                    errorMessage = nil
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? BabyPhotoStore.PhotoError.unreadable.errorDescription
                }
            }
        }
    }
}

private struct UnitPicker: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: NBSpacing.s) {
            Text("Bottle amounts in")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NBColor.secondaryText)
            Picker("Bottle amounts in", selection: $preferences.volumeUnit) {
                Text("mL").tag(VolumeUnit.milliliters)
                Text("oz").tag(VolumeUnit.fluidOunces)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.unit")
        }
    }
}

// MARK: - Step 3: Stay in the loop

private struct StayInTheLoopStep: View {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(ReminderScheduler.self) private var reminders: ReminderScheduler?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: NBSpacing.xl) {
                LockScreenIllustration()
                StepHeading(
                    title: "Stay in the loop",
                    subtitle: "While you feed, the timer and side buttons stay on the Lock Screen and in the Dynamic Island. No need to unlock to check the time."
                )
                if let preferences {
                    reminderCard(preferences)
                }
                Text("Newbee helps you keep track. It isn't medical advice, so talk to your pediatrician about your baby's feeding.")
                    .font(.footnote)
                    .foregroundStyle(NBColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, NBSpacing.xl)
            .padding(.top, NBSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func reminderCard(_ preferences: AppPreferences) -> some View {
        VStack(alignment: .leading, spacing: NBSpacing.s) {
            Toggle(isOn: Binding(
                get: { preferences.reminders.isEnabled },
                set: { on in
                    preferences.reminders.isEnabled = on
                    Task {
                        // Asks for notification permission only now, when the parent wants it.
                        if on, reminders?.permission == .notDetermined {
                            await reminders?.requestPermission()
                        } else {
                            await reminders?.reschedule()
                        }
                    }
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feeding reminders")
                            .font(.body.weight(.semibold))
                        Text("A nudge \(DurationText.short(preferences.reminders.interval)) after the last feed.")
                            .font(.subheadline)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(NBColor.accent)
                }
            }
            .tint(NBColor.accent)
            .accessibilityIdentifier("onboarding.reminders")

            if preferences.reminders.isEnabled, reminders?.permission == .denied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Text("Notifications are off for Newbee. Turn them on in iOS Settings.")
                        .font(.footnote)
                        .foregroundStyle(NBColor.destructive)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(NBSpacing.l)
        .nbCardBackground()
    }
}

/// A sketch of the feeding Live Activity on the Lock Screen. Example values only.
private struct LockScreenIllustration: View {
    var body: some View {
        VStack(spacing: NBSpacing.m) {
            Text(verbatim: "9:41")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
            HStack(spacing: NBSpacing.m) {
                Text("L")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(NBColor.onSide)
                    .frame(width: 40, height: 40)
                    .background(NBColor.left, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feeding · Left")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: "L 8:12 · R 3:52")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                Text(verbatim: "12:04")
                    .font(NBFont.timer(size: 28))
            }
            .foregroundStyle(.white)
            .padding(NBSpacing.m)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: NBRadius.control, style: .continuous))
        }
        .padding(NBSpacing.l)
        .padding(.top, NBSpacing.s)
        .frame(maxWidth: 320)
        .background(
            LinearGradient(colors: [Color(light: 0x3B3F9E, dark: 0x2A2D73), Color(light: 0x26706A, dark: 0x1D4F4B)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: NBRadius.card + 8, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: the feeding timer on the Lock Screen, showing the left side at 12 minutes")
    }
}

// MARK: - Shared pieces

private struct StepHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: NBSpacing.s) {
            Text(title)
                .font(.system(.title, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(NBColor.secondaryText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: NBSpacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: NBSpacing.s) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? NBColor.accent : NBColor.secondaryText.opacity(0.3))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Presentation

extension View {
    /// Shows onboarding once, on first launch, over the whole app.
    func onboardingPresentation() -> some View {
        modifier(OnboardingGate())
    }
}

/// Decides whether to show onboarding: not yet completed, and the store is empty (someone
/// updating from an earlier TestFlight build already has data and skips it). UI tests skip it
/// unless they pass `-showOnboarding`.
private struct OnboardingGate: ViewModifier {
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    @Environment(\.modelContext) private var context
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task { evaluate() }
            .fullScreenCover(isPresented: $isPresented) {
                OnboardingView {
                    preferences?.onboardingComplete = true
                    isPresented = false
                }
            }
    }

    private func evaluate() {
        guard let preferences, !preferences.onboardingComplete else { return }
        if AppConfiguration.isUITesting, !AppConfiguration.showsOnboardingUnderUITests { return }
        if OnboardingProfile.hasExistingData(in: context) {
            preferences.onboardingComplete = true
            return
        }
        isPresented = true
    }
}

#Preview("Onboarding") {
    OnboardingView {}
        .environment(AppPreferences(defaults: UserDefaults(suiteName: "OnboardingPreview") ?? .standard))
        .environment(BabyPhotoStore.temporary())
        .modelContainer(try! PersistenceController.makeContainer(.inMemory))
}
