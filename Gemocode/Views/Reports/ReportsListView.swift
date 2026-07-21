import SwiftUI
import SwiftData

struct ReportsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var profiles: [HealthProfile]

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var selectedCategory: ReportCategory?

    private var availableCategories: [ReportCategory] {
        ReportCategory.allCases.filter { category in reports.contains { $0.category == category } }
    }

    private var filteredReports: [MedicalReport] {
        reports.filter { report in
            if let selectedCategory, report.category != selectedCategory { return false }
            guard !searchText.isEmpty else { return true }
            return report.title.localizedCaseInsensitiveContains(searchText)
                || report.provider.localizedCaseInsensitiveContains(searchText)
                || report.facility.localizedCaseInsensitiveContains(searchText)
                || report.category.displayName.localizedCaseInsensitiveContains(searchText)
                || bloodworkCategoryName(report.category).localizedCaseInsensitiveContains(searchText)
        }
    }

    /// `filteredReports` bucketed by calendar year (newest year first);
    /// reports within a year keep the incoming newest-first order from the
    /// `@Query` sort, so each bucket reads newest-first too. Matches the
    /// year-grouped ledger in the reports-library mockups.
    private var yearGroups: [(year: Int, reports: [MedicalReport])] {
        var byYear: [Int: [MedicalReport]] = [:]
        var order: [Int] = []
        for report in filteredReports {
            let year = Calendar.current.component(.year, from: report.date)
            if byYear[year] == nil { order.append(year) }
            byYear[year, default: []].append(report)
        }
        return order.sorted(by: >).map { (year: $0, reports: byYear[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    ContentUnavailableView {
                        Label("No Reports", systemImage: "doc.text")
                    } description: {
                        Text("Add your first medical report — lab results, imaging, prescriptions and more.")
                    } actions: {
                        Button("Add Report") { showingAdd = true }
                            .buttonStyle(GlassProminentButtonStyle())
                            .frame(maxWidth: 220)
                    }
                } else {
                    List {
                        if availableCategories.count > 1 {
                            Section {
                                categoryChips
                            }
                            .listRowBackground(GlassRowBackground())
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                        ForEach(yearGroups, id: \.year) { group in
                            Section {
                                ForEach(group.reports) { report in
                                    NavigationLink {
                                        ReportDetailView(report: report)
                                    } label: {
                                        ReportRow(report: report, sex: profiles.first?.sex)
                                    }
                                }
                                .onDelete { offsets in
                                    deleteReports(group.reports, at: offsets)
                                }
                            } header: {
                                MicroLabel(verbatim: String(group.year))
                            }
                            .listRowBackground(GlassRowBackground())
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search reports")
                }
            }
            .ambientScreen()
            .navigationTitle("Reports")
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add report")
            }
            .sheet(isPresented: $showingAdd) { ScanReportView() }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ReportCategoryChip(title: Text("All"), isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(availableCategories) { category in
                    ReportCategoryChip(title: Text(bloodworkCategoryName(category)), isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func deleteReports(_ groupReports: [MedicalReport], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(groupReports[index])
        }
    }
}

/// Selected = solid ink fill / canvas text; unselected = hairline
/// `controlBorder` outline / muted text — the same pill language used for
/// category filters throughout the editorial system (mirrors the one in
/// `DocumentsView`, kept as its own small type since the two screens don't
/// share a view file).
private struct ReportCategoryChip: View {
    let title: Text
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            title
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Editorial.canvas(colorScheme) : Editorial.muted(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Editorial.ink(colorScheme) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Editorial.controlBorder(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct ReportRow: View {
    let report: MedicalReport
    let sex: BiologicalSex?

    @Environment(\.colorScheme) private var colorScheme

    /// Each lab result evaluated against its reference range, reused for
    /// both the "N values · M out of range" subtitle and the trailing
    /// status dots.
    private var labStatuses: [LabStatus] {
        report.labResults.map { result in
            AnalysisEngine.status(
                value: result.value,
                range: result.referenceRange(for: sex),
                criticalLow: result.catalogReference?.criticalLow,
                criticalHigh: result.catalogReference?.criticalHigh
            )
        }
    }

    private var outOfRangeCount: Int {
        labStatuses.filter { $0.isOutOfRange }.count
    }

    private var hasCriticalOutOfRange: Bool {
        labStatuses.contains { $0.isCritical }
    }

    private var hasNonCriticalOutOfRange: Bool {
        labStatuses.contains { $0.isOutOfRange && !$0.isCritical }
    }

    /// The `LabCatalog` display name a prescription report's monitored lab
    /// resolves to — e.g. "Prescription — Metformin" resolves to "HbA1c",
    /// rendered as "HbA1c ↗" in `body`. There's no medication/report
    /// association in the data model to draw on (and this pass adds none),
    /// so the drug name is matched straight out of the report's own text via
    /// `MedicationLabLinks.link(for:)`, the same matcher
    /// `MedicationLabLinks`/`RxNameMatcher` use elsewhere. `nil` whenever the
    /// report isn't a prescription, its text doesn't mention a monitored
    /// drug, or that drug's link has no lab (a vital-only link like
    /// amlodipine).
    private var linkedLabName: String? {
        guard report.category == .prescription else { return nil }
        let combinedText = "\(report.title) \(report.notes)"
        guard let labID = MedicationLabLinks.link(for: combinedText)?.primaryLabID else { return nil }
        return LabCatalog.reference(for: labID)?.name
    }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                MicroLabel(verbatim: report.date.formatted(.dateTime.month(.abbreviated).day()))
                Text(bloodworkDisplayTitle(report.title))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .lineLimit(1)
                subtitle
                    .font(.system(size: 12))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !report.labResults.isEmpty {
                statusDots
            } else if let linkedLabName {
                Text(verbatim: "\(linkedLabName) ↗")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Editorial.accent(colorScheme))
                    .lineLimit(1)
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Localized "N values · M out of range" (or "· all in range") summary —
    /// a plain `String` (rather than only a `Text`) so the exact same
    /// wording backs both the visible subtitle and the accessibility label
    /// below, instead of two near-duplicate localized strings.
    private var labSummaryText: String {
        outOfRangeCount > 0
            ? String(localized: "\(report.labResults.count) values · \(outOfRangeCount) out of range")
            : String(localized: "\(report.labResults.count) values · all in range")
    }

    @ViewBuilder
    private var subtitle: some View {
        if !report.labResults.isEmpty {
            Text(labSummaryText)
        } else {
            HStack(spacing: 4) {
                Text(bloodworkCategoryName(report.category))
                if !report.provider.isEmpty {
                    Text("·")
                    Text(report.provider)
                }
            }
        }
    }

    private var statusDots: some View {
        HStack(spacing: 4) {
            if hasNonCriticalOutOfRange {
                Circle().fill(Editorial.tagWarn(colorScheme)).frame(width: 8, height: 8)
            }
            if hasCriticalOutOfRange {
                Circle().fill(Editorial.tagBad(colorScheme)).frame(width: 8, height: 8)
            }
            if outOfRangeCount == 0 {
                Circle().fill(Editorial.tagGood(colorScheme)).frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Editorial.insetCard(colorScheme))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1)
            Image(systemName: report.category.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(Editorial.ink(colorScheme))
        }
        .frame(width: 44, height: 58)
        .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        var parts = [bloodworkDisplayTitle(report.title), report.date.formatted(date: .abbreviated, time: .omitted)]
        parts.append(report.labResults.isEmpty ? bloodworkCategoryName(report.category) : labSummaryText)
        if let linkedLabName {
            parts.append(String(localized: "linked to \(linkedLabName)"))
        }
        if !report.attachments.isEmpty {
            parts.append(String(localized: "\(report.attachments.count) attachments"))
        }
        return parts.joined(separator: ", ")
    }
}

/// Display-only rename of the `.labReport` category's user-facing name,
/// from "Lab Report" to "Bloodwork" — used wherever this file shows just
/// the category name on its own (the category filter chips, `ReportRow`'s
/// no-lab-results subtitle/accessibility summary). `ReportCategory
/// .displayName` itself lives in `Models/Models.swift` (owned by a
/// different pass, so its localized "Lab Report" string is left exactly as
/// it is) — this is a cosmetic substitute, independently duplicated in
/// `ScanReportView.swift`/`ReportDetailView.swift` per this pass's
/// file-ownership split.
private func bloodworkCategoryName(_ category: ReportCategory) -> String {
    category == .labReport
        ? String(localized: "Bloodwork")
        : category.displayName
}

/// Display-only rename of an already-STORED report `title` (e.g. "Lab
/// Report — Jul 21, 2026", built once at save time from `category
/// .displayName` and persisted verbatim — see `ScanReportView.save()`,
/// which keeps generating that exact stored string unchanged). Substitutes
/// the CURRENT localized "Lab Report" label for "Bloodwork" wherever it
/// appears in the title, so a scan-generated title reads as "Bloodwork —
/// Jul 21, 2026" without ever touching the stored `MedicalReport.title`
/// field itself. Falls through unchanged for a title the user has since
/// renamed by hand (one that no longer contains the old label at all).
private func bloodworkDisplayTitle(_ title: String) -> String {
    let oldLabel = ReportCategory.labReport.displayName
    guard title.contains(oldLabel) else { return title }
    return title.replacingOccurrences(of: oldLabel, with: String(localized: "Bloodwork"))
}
