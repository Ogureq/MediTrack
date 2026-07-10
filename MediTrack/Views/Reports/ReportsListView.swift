import SwiftUI
import SwiftData

struct ReportsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

    @State private var searchText = ""
    @State private var showingAdd = false

    private var filteredReports: [MedicalReport] {
        guard !searchText.isEmpty else { return reports }
        return reports.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.provider.localizedCaseInsensitiveContains(searchText)
                || $0.facility.localizedCaseInsensitiveContains(searchText)
                || $0.category.displayName.localizedCaseInsensitiveContains(searchText)
        }
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
                        ForEach(filteredReports) { report in
                            NavigationLink {
                                ReportDetailView(report: report)
                            } label: {
                                ReportRow(report: report)
                            }
                        }
                        .onDelete(perform: deleteReports)
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
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
            .sheet(isPresented: $showingAdd) { AddReportView() }
        }
    }

    private func deleteReports(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredReports[index])
        }
    }
}

struct ReportRow: View {
    let report: MedicalReport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.category.systemImage)
                .foregroundStyle(Glass.accentGradient)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(report.category.displayName)
                    if !report.provider.isEmpty {
                        Text("·")
                        Text(report.provider)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                HStack(spacing: 8) {
                    Text(report.date.formatted(date: .abbreviated, time: .omitted))
                    if !report.labResults.isEmpty {
                        Label("\(report.labResults.count)", systemImage: "testtube.2")
                            .accessibilityLabel("\(report.labResults.count) lab results")
                    }
                    if !report.attachments.isEmpty {
                        Label("\(report.attachments.count)", systemImage: "paperclip")
                            .accessibilityLabel("\(report.attachments.count) attachments")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
