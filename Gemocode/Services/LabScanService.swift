import Foundation
import UIKit
import Vision
import PDFKit

/// A lab value recognized in a scanned report attachment.
struct ScannedLabValue: Identifiable {
    let id = UUID()
    let reference: LabReference
    let value: Double
    let sourceLine: String
}

/// Recognizes text in report attachments (photos and PDFs) with the Vision
/// framework and extracts known lab values by matching lines against the
/// catalog via `LabSynonyms`.
enum LabScanService {

    static func scan(attachments: [(kind: AttachmentKind, data: Data)]) async -> [ScannedLabValue] {
        var lines: [String] = []
        for attachment in attachments {
            for image in images(from: attachment) {
                if let recognized = try? await recognizeLines(in: image) {
                    lines.append(contentsOf: recognized)
                }
            }
        }
        return parse(lines: lines)
    }

    // MARK: Rendering attachments to images

    private static func images(from attachment: (kind: AttachmentKind, data: Data)) -> [CGImage] {
        switch attachment.kind {
        case .image:
            if let cgImage = UIImage(data: attachment.data)?.cgImage {
                return [cgImage]
            }
            return []
        case .pdf:
            guard let document = PDFDocument(data: attachment.data) else { return [] }
            var result: [CGImage] = []
            for index in 0..<min(document.pageCount, 10) {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale = 1600 / max(bounds.width, 1)
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                if let cgImage = page.thumbnail(of: size, for: .mediaBox).cgImage {
                    result.append(cgImage)
                }
            }
            return result
        }
    }

    // MARK: OCR

    private static func recognizeLines(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                // When perform(_:) throws, the completion handler is never called.
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: Parsing

    /// Matches OCR'd lines against the lab catalog. When a matched line
    /// carries no number (label and value in separate columns), the next
    /// line is tried as the value.
    static func parse(lines: [String]) -> [ScannedLabValue] {
        var results: [ScannedLabValue] = []
        var seenIDs: Set<String> = []

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard lower.count >= 3 else { continue }
            guard let (reference, range) = LabSynonyms.match(in: lower),
                  !seenIDs.contains(reference.id) else { continue }

            var value = firstNumber(in: String(lower[range.upperBound...]))
            if value == nil, index + 1 < lines.count {
                let next = lines[index + 1].lowercased()
                if LabSynonyms.match(in: next) == nil {
                    value = firstNumber(in: next)
                }
            }
            guard let value, value > 0, value < 1_000_000 else { continue }

            // Discard values wildly outside the plausible range (dates, IDs…).
            if let plausible = reference.referenceRange(for: nil), value > plausible.upperBound * 50 {
                continue
            }

            seenIDs.insert(reference.id)
            results.append(ScannedLabValue(reference: reference, value: value, sourceLine: trimmed))
        }
        return results
    }

    private static func firstNumber(in text: String) -> Double? {
        var current = ""
        var found: String?
        for character in text {
            if character.isNumber || ((character == "." || character == ",") && !current.isEmpty) {
                current.append(character == "," ? "." : character)
            } else if !current.isEmpty {
                found = current
                break
            }
        }
        if found == nil && !current.isEmpty {
            found = current
        }
        guard var token = found else { return nil }
        if token.hasSuffix(".") {
            token.removeLast()
        }
        return Double(token)
    }
}
