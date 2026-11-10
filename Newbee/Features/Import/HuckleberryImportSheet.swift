import NewbeeKit
import NewbeeShared
import SwiftUI
import UniformTypeIdentifiers

/// Imports a Huckleberry CSV export (Settings → Your data, and the onboarding welcome step).
///
/// Three steps: how to get the file and a Choose File button, a preview of what will be added and
/// what will be skipped, then the result. Nothing is saved until the parent taps Import.
struct HuckleberryImportSheet: View {
    enum Phase {
        case intro
        case reading
        case preview(ImportPlan)
        case importing(ImportPlan)
        case done(Int)
    }

    let prepare: @MainActor (URL) throws -> ImportPlan
    let commit: @MainActor (ImportPlan) async throws -> Int
    /// Called after a successful import, so open screens can refresh.
    var onImported: @MainActor () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .intro
    @State private var isChoosingFile = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Huckleberry")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !isDone {
                            Button("Cancel") { dismiss() }
                                .disabled(isImporting)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isDone {
                            Button("Done") { dismiss() }
                                .accessibilityIdentifier("import.done")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { primaryButton }
                .fileImporter(
                    isPresented: $isChoosingFile,
                    allowedContentTypes: [.commaSeparatedText, .plainText, .text]
                ) { result in
                    switch result {
                    case .success(let url): read(url)
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                }
        }
        .interactiveDismissDisabled(isImporting)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro, .reading:
            IntroView(errorMessage: errorMessage)
        case .preview(let plan), .importing(let plan):
            PreviewView(plan: plan, errorMessage: errorMessage)
        case .done(let count):
            DoneView(count: count)
        }
    }

    // MARK: - Primary button

    @ViewBuilder
    private var primaryButton: some View {
        switch phase {
        case .intro, .reading:
            bottomButton(
                title: isReading ? String(localized: "Reading file…") : String(localized: "Choose File"),
                busy: isReading,
                identifier: "import.chooseFile"
            ) {
                errorMessage = nil
                isChoosingFile = true
            }
        case .preview(let plan):
            if plan.isEmpty {
                bottomButton(title: String(localized: "Choose Another File"), busy: false, identifier: "import.chooseFile") {
                    errorMessage = nil
                    isChoosingFile = true
                }
            } else {
                bottomButton(title: ImportText.importButton(plan.records.count), busy: false, identifier: "import.confirm") {
                    run(plan)
                }
            }
        case .importing:
            bottomButton(title: String(localized: "Importing…"), busy: true, identifier: "import.confirm") {}
        case .done:
            EmptyView()
        }
    }

    private func bottomButton(title: String, busy: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if busy {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NBSpacing.m)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
        .tint(NBColor.accent)
        .disabled(busy)
        .padding(.horizontal, NBSpacing.l)
        .padding(.bottom, NBSpacing.s)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Actions

    private var isReading: Bool {
        if case .reading = phase { return true }
        return false
    }

    private var isImporting: Bool {
        if case .importing = phase { return true }
        return false
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    private func read(_ url: URL) {
        let previous = phase
        phase = .reading
        Task { @MainActor in
            // Let the spinner draw before the (synchronous) parse of a large file.
            try? await Task.sleep(for: .milliseconds(50))
            do {
                phase = .preview(try prepare(url))
                errorMessage = nil
            } catch {
                phase = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    private func run(_ plan: ImportPlan) {
        phase = .importing(plan)
        errorMessage = nil
        Task { @MainActor in
            do {
                let count = try await commit(plan)
                phase = .done(count)
                onImported()
            } catch {
                phase = .preview(plan)
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Steps

private struct IntroView: View {
    let errorMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: NBSpacing.s) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.largeTitle)
                        .foregroundStyle(NBColor.accent)
                        .accessibilityHidden(true)
                    Text("Bring your feeding history")
                        .font(.title3.weight(.semibold))
                    Text("Newbee adds your breastfeeds, bottles and pumping sessions from Huckleberry, so your patterns and averages start from day one.")
                        .font(.subheadline)
                        .foregroundStyle(NBColor.secondaryText)
                }
                .padding(.vertical, NBSpacing.s)
            }

            Section {
                StepRow(number: 1, text: "In Huckleberry, tap your child's profile.")
                StepRow(number: 2, text: "Tap \u{201C}Export tracking data as CSV\u{201D}, then \u{201C}Got it! Email it\u{201D}.")
                StepRow(number: 3, text: "Open the email on this iPhone, tap the link and save the file to Files. The link works for 24 hours.")
                StepRow(number: 4, text: "Come back here and tap Choose File.")
            } header: {
                Text("Get your file")
            }

            Section {
                Label("Feeds already in Newbee are skipped, so importing again is safe.", systemImage: "checkmark.circle")
                Label("Sleep, diapers, growth and other activities aren't imported.", systemImage: "minus.circle")
                Label("Imported entries can be removed any time in Settings.", systemImage: "arrow.uturn.backward.circle")
            } header: {
                Text("Good to know")
            }
            .font(.subheadline)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(NBColor.destructive)
                        .accessibilityIdentifier("import.error")
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NBSpacing.m) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(NBColor.accent, in: .circle)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewView: View {
    let plan: ImportPlan
    let errorMessage: String?

    var body: some View {
        Form {
            Section {
                if plan.isEmpty {
                    Text("Nothing new to import. Everything in this file is already in Newbee or isn't something Newbee tracks.")
                        .accessibilityIdentifier("import.nothingNew")
                } else {
                    CountRow(title: "Breastfeeds", symbol: "heart.fill", tint: NBColor.leftInk, count: plan.breastCount)
                    CountRow(title: "Bottles", symbol: "waterbottle.fill", tint: NBColor.bottleFormulaInk, count: plan.bottleCount)
                    CountRow(title: "Pumping sessions", symbol: "drop.fill", tint: NBColor.pumpInk, count: plan.pumpCount)
                }
            } header: {
                Text("Ready to import")
            } footer: {
                if let range = plan.dateRange {
                    Text(ImportText.range(range))
                }
            }

            if plan.duplicates > 0 || plan.unsupportedCount > 0 {
                Section {
                    if plan.duplicates > 0 {
                        LabeledContent("Already in Newbee", value: plan.duplicates.formatted())
                            .accessibilityIdentifier("import.duplicates")
                    }
                    ForEach(plan.unsupported) { item in
                        LabeledContent(item.type, value: item.count.formatted())
                    }
                } header: {
                    Text("Skipped")
                } footer: {
                    if plan.unsupportedCount > 0 {
                        Text("Newbee tracks feeding and pumping only, so other Huckleberry activities stay out.")
                    }
                }
            }

            if !plan.problems.isEmpty {
                Section {
                    ForEach(Array(plan.problems.prefix(50).enumerated()), id: \.offset) { _, problem in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ImportText.problemTitle(problem))
                                .font(.subheadline.weight(.medium))
                            Text(ImportText.reason(problem.reason))
                                .font(.footnote)
                                .foregroundStyle(NBColor.secondaryText)
                        }
                    }
                    if plan.problems.count > 50 {
                        Text("And \(plan.problems.count - 50) more")
                            .font(.footnote)
                            .foregroundStyle(NBColor.secondaryText)
                    }
                } header: {
                    Text("Couldn't import (\(plan.problems.count))")
                } footer: {
                    Text("These rows have values Newbee can't read or wouldn't accept. You can add them by hand later.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(NBColor.destructive)
                        .accessibilityIdentifier("import.error")
                }
            }
        }
    }
}

private struct CountRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let count: Int

    var body: some View {
        LabeledContent {
            Text(count.formatted())
                .monospacedDigit()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
        }
    }
}

private struct DoneView: View {
    let count: Int

    var body: some View {
        VStack(spacing: NBSpacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(NBColor.accent)
                .accessibilityHidden(true)
            Text(ImportText.done(count))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("import.result")
            Text("You'll find them in History, Calendar and Insights.")
                .font(.subheadline)
                .foregroundStyle(NBColor.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(NBSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(NBColor.canvas.ignoresSafeArea())
    }
}

// MARK: - Text

enum ImportText {
    static func importButton(_ count: Int) -> String {
        count == 1 ? String(localized: "Import 1 Entry") : String(localized: "Import \(count) Entries")
    }

    /// "Remove 12 imported entries?"
    static func removeTitle(_ count: Int) -> String {
        count == 1 ? String(localized: "Remove 1 imported entry?") : String(localized: "Remove \(count) imported entries?")
    }

    static func done(_ count: Int) -> String {
        count == 1 ? String(localized: "Imported 1 entry") : String(localized: "Imported \(count) entries")
    }

    /// "Apr 19, 2024 – Sep 9, 2025".
    static func range(_ range: ClosedRange<Date>) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        let first = range.lowerBound.formatted(style)
        let last = range.upperBound.formatted(style)
        return first == last ? String(localized: "From \(first)") : String(localized: "From \(first) to \(last)")
    }

    static func problemTitle(_ problem: ImportProblem) -> String {
        let type = problem.type.isEmpty ? String(localized: "Row") : problem.type
        return problem.start.isEmpty ? "\(type) · line \(problem.line)" : "\(type) · \(problem.start)"
    }

    static func reason(_ reason: ImportProblem.Reason) -> String {
        switch reason {
        case .missingType:
            String(localized: "The row has no type.")
        case .unreadableTime:
            String(localized: "The start time can't be read.")
        case .unknownFeedKind(let text):
            text.isEmpty ? String(localized: "It doesn't say whether it was a bottle or nursing.") : String(localized: "\u{201C}\(text)\u{201D} feeds aren't something Newbee tracks.")
        case .unreadableAmount(let text):
            String(localized: "The amount \u{201C}\(text)\u{201D} can't be read.")
        case .unreadableSideTime(let text):
            String(localized: "The side time \u{201C}\(text)\u{201D} can't be read.")
        case .noSideTimes:
            String(localized: "No time on either side.")
        case .breastfeedTooLong:
            String(localized: "Longer than 4 hours, so probably a timer left running.")
        case .inFuture:
            String(localized: "It's in the future.")
        case .bottle(let problem):
            bottle(problem)
        case .pump(let problem):
            pump(problem)
        }
    }

    private static func bottle(_ problem: BottleValidationError) -> String {
        switch problem {
        case .amountNotPositive: String(localized: "The amount is zero.")
        case .amountTooLarge(let maximum): String(localized: "More than \(FeedText.volume(ml: maximum)), Newbee's limit for one bottle.")
        case .startInFuture, .endInFuture: String(localized: "It's in the future.")
        case .durationNotPositive: String(localized: "The duration is zero.")
        case .durationTooLong: String(localized: "Longer than 2 hours.")
        }
    }

    private static func pump(_ problem: PumpValidationError) -> String {
        switch problem {
        case .amountNotPositive: String(localized: "No amount on either side.")
        case .sideTooLarge(let side, let maximum):
            side == .left
                ? String(localized: "Left side is more than \(FeedText.volume(ml: maximum)), Newbee's limit.")
                : String(localized: "Right side is more than \(FeedText.volume(ml: maximum)), Newbee's limit.")
        case .startInFuture, .endInFuture: String(localized: "It's in the future.")
        case .durationNotPositive: String(localized: "The duration is zero.")
        case .durationTooLong: String(localized: "Longer than 2 hours.")
        }
    }
}

#Preview("Intro") {
    HuckleberryImportSheet(prepare: { _ in throw AppDependencies.ImportError.notHuckleberry }, commit: { $0.records.count })
}
