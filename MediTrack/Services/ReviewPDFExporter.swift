import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Transferable wrapper

/// Lets a ShareLink lazily render the health review to a PDF file
/// only when the user actually shares it.
struct ReviewPDF: Transferable {
    let review: HealthReview

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            let url = try await MainActor.run { () throws -> URL in
                guard let url = ReviewPDFExporter.export(item.review) else {
                    throw PDFExportError.renderingFailed
                }
                return url
            }
            return SentTransferredFile(url)
        }
    }
}

enum PDFExportError: Error {
    case renderingFailed
}

// MARK: - Exporter

@MainActor
enum ReviewPDFExporter {

    /// Renders the review as a single-page PDF (US-Letter width, dynamic
    /// height) and returns the temporary file URL.
    static func export(_ review: HealthReview) -> URL? {
        let renderer = ImageRenderer(content: ReviewPDFPage(review: review))
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediTrack Health Review.pdf")

        var succeeded = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return
            }
            pdfContext.beginPDFPage(nil)
            renderInContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            succeeded = true
        }
        return succeeded ? url : nil
    }
}

// MARK: - Print-styled page

struct ReviewPDFPage: View {
    let review: HealthReview

    private let accent = Color(red: 0.04, green: 0.50, blue: 0.54)
    private let secondaryText = Color(white: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            Text(review.summary)
                .font(.system(size: 12))
            severitySection("Critical", findings: review.criticalFindings, color: .red)
            severitySection("Needs Attention", findings: review.attentionFindings, color: .orange)
            severitySection("Informational", findings: review.infoFindings, color: .blue)
            trendsSection
            labsSection
            Divider()
            Text(HealthReview.disclaimer)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.4))
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MediTrack")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accent)
                Text("Health Review")
                    .font(.system(size: 14))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(review.generatedAt.formatted(date: .long, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(secondaryText)
                Text("Score: \(review.score)/100 · \(review.scoreLabel)")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private func severitySection(_ title: String, findings: [Finding], color: Color) -> some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                ForEach(findings) { finding in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• \(finding.title)")
                            .font(.system(size: 11, weight: .semibold))
                        Text(finding.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryText)
                            .padding(.leading, 10)
                        if let recommendation = finding.recommendation {
                            Text("→ \(recommendation)")
                                .font(.system(size: 10).italic())
                                .foregroundStyle(secondaryText)
                                .padding(.leading, 10)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trendsSection: some View {
        if !review.trends.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("TRENDS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                ForEach(review.trends) { trend in
                    Text("• \(trend.detail)")
                        .font(.system(size: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var labsSection: some View {
        if !review.labSnapshots.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("LATEST LAB VALUES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                ForEach(review.labSnapshots) { snapshot in
                    HStack(spacing: 8) {
                        Text(snapshot.name)
                            .font(.system(size: 10))
                        if let range = snapshot.range {
                            Text("(\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted))")
                                .font(.system(size: 9))
                                .foregroundStyle(secondaryText)
                        }
                        Spacer()
                        Text("\(snapshot.value.compactFormatted) \(snapshot.unit)")
                            .font(.system(size: 10, weight: .semibold))
                        Text(snapshot.status.label)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(snapshot.status.color, in: Capsule())
                    }
                }
            }
        }
    }
}
