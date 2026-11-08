import NewbeeKit
import NewbeeShared
import SwiftUI

/// Picks the date range for the PDF feeding report, creates it and opens the share sheet
/// (Settings → Your data). Presets first; Custom shows two day pickers.
struct ExportReportSheet: View {
    enum Choice: Hashable, CaseIterable, Identifiable {
        case week, twoWeeks, month, custom

        var id: Self { self }

        var title: String {
            switch self {
            case .week: String(localized: "7 days")
            case .twoWeeks: String(localized: "14 days")
            case .month: String(localized: "30 days")
            case .custom: String(localized: "Custom")
            }
        }
    }

    let export: @MainActor (FeedReportRange) throws -> URL
    var now: Date = .now

    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice = .twoWeeks
    @State private var from: Date = Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now
    @State private var through: Date = .now
    @State private var isCreating = false
    @State private var sharing: SharedFile?
    @State private var errorMessage: String?

    private var range: FeedReportRange {
        switch choice {
        case .week: .lastDays(7)
        case .twoWeeks: .lastDays(14)
        case .month: .lastDays(30)
        case .custom: .days(from: from, through: through)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Range", selection: $choice) {
                        ForEach(Choice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("exportReport.range")

                    if choice == .custom {
                        DatePicker("From", selection: $from, in: ...through, displayedComponents: .date)
                            .accessibilityIdentifier("exportReport.from")
                        DatePicker("Through", selection: $through, in: from...now, displayedComponents: .date)
                            .accessibilityIdentifier("exportReport.through")
                    }
                } footer: {
                    Text(ReportText.range(range.interval(now: now), dayCount: dayCount))
                }

                Section {
                    Label("A summary page with averages, a chart and breastfeeding, bottle and pumping totals", systemImage: "chart.bar.doc.horizontal")
                    Label("Every feed and pumping session, day by day, with notes", systemImage: "list.bullet.rectangle")
                } header: {
                    Text("What's included")
                } footer: {
                    Text("A US Letter PDF you can print, email or AirDrop to your pediatrician.")
                }
                .font(.subheadline)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(NBColor.destructive)
                    }
                }
            }
            .navigationTitle("Feeding report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    create()
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isCreating ? "Creating PDF…" : "Create PDF")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NBSpacing.m)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: NBRadius.control))
                .tint(NBColor.accent)
                .disabled(isCreating)
                .padding(.horizontal, NBSpacing.l)
                .padding(.bottom, NBSpacing.s)
                .accessibilityIdentifier("exportReport.create")
            }
            .sheet(item: $sharing) { file in
                ShareSheet(url: file.url)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var dayCount: Int {
        let interval = range.interval(now: now)
        return max(1, Int((interval.duration / 86_400).rounded()))
    }

    private func create() {
        isCreating = true
        errorMessage = nil
        let range = range
        Task { @MainActor in
            // Let the spinner draw before the (synchronous) rendering starts.
            try? await Task.sleep(for: .milliseconds(50))
            defer { isCreating = false }
            do {
                sharing = SharedFile(url: try export(range))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ExportReportSheet { _ in throw FeedReportPDF.RenderError.couldNotCreateFile }
}
