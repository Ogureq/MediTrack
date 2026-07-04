import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct ReportDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [HealthProfile]

    let report: MedicalReport

    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("Category") {
                    Label(report.category.displayName, systemImage: report.category.systemImage)
                }
                LabeledContent("Date", value: report.date.formatted(date: .long, time: .omitted))
                if !report.provider.isEmpty {
                    LabeledContent("Provider", value: report.provider)
                }
                if !report.facility.isEmpty {
                    LabeledContent("Facility", value: report.facility)
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            if !report.labResults.isEmpty {
                Section("Lab Results") {
                    ForEach(report.labResults.sorted(by: { $0.displayName < $1.displayName })) { result in
                        LabResultRow(result: result, sex: profiles.first?.sex)
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !report.attachments.isEmpty {
                Section("Attachments") {
                    ForEach(report.attachments) { attachment in
                        NavigationLink {
                            AttachmentViewer(attachment: attachment)
                        } label: {
                            Label(
                                attachment.filename,
                                systemImage: attachment.kind == .pdf ? "doc.richtext" : "photo"
                            )
                        }
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            if !report.notes.isEmpty {
                Section("Notes") {
                    Text(report.notes)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }

            Section {
                Button("Delete Report", role: .destructive) {
                    confirmDelete = true
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
        .ambientScreen()
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this report and all its results?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(report)
                dismiss()
            }
        }
    }
}

struct LabResultRow: View {
    let result: LabResult
    let sex: BiologicalSex?

    var body: some View {
        let range = result.referenceRange(for: sex)
        let reference = result.catalogReference
        let status = AnalysisEngine.status(
            value: result.value,
            range: range,
            criticalLow: reference?.criticalLow,
            criticalHigh: reference?.criticalHigh
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(result.value.compactFormatted) \(result.unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.isOutOfRange ? status.color : .primary)
            }
            HStack {
                if let range {
                    Text("Typical: \(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(result.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: status.label, color: status.color)
            }
            if status.isOutOfRange, let reference {
                let meaning = (status == .low || status == .criticalLow)
                    ? reference.lowMeaning
                    : reference.highMeaning
                Text(meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AttachmentViewer: View {
    let attachment: ReportAttachment

    var body: some View {
        Group {
            if attachment.kind == .pdf {
                PDFKitView(data: attachment.data)
                    .ignoresSafeArea(edges: .bottom)
            } else if let image = UIImage(data: attachment.data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .containerRelativeFrame(.horizontal)
                }
            } else {
                ContentUnavailableView("Can't Preview File", systemImage: "eye.slash")
            }
        }
        .background(AmbientBackground())
        .navigationTitle(attachment.filename)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
