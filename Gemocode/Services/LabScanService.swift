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
            // Russian is Cyrillic-script and needs an explicit language hint;
            // Turkish is Latin-script and reads acceptably under English
            // recognition, so it is intentionally not added here — Vision's
            // supported-language list for .accurate on iOS 17 has not been
            // verified for "tr-TR", and an unsupported language code makes
            // perform(_:) throw.
            request.recognitionLanguages = ["en-US", "ru-RU"]
            request.automaticallyDetectsLanguage = true
            // Left off: language correction would try to "fix" Cyrillic
            // tokens (and numbers) against an English dictionary, which is
            // more likely to corrupt a lab value/label than help it.
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

            // Text to scan for a unit token: the matched line, plus the
            // fallback value line when the value came from there instead.
            var unitSearchText = lower
            var value = firstNumber(in: String(lower[range.upperBound...]))
            if value == nil, index + 1 < lines.count {
                let next = lines[index + 1].lowercased()
                if LabSynonyms.match(in: next) == nil {
                    value = firstNumber(in: next)
                    unitSearchText += " " + next
                }
            }
            guard var resolvedValue = value, resolvedValue > 0, resolvedValue < 1_000_000 else { continue }

            // Convert non-canonical (mostly Russian/European) units to the
            // catalog's canonical unit before the plausibility check below.
            resolvedValue = LabUnitConversion.convert(resolvedValue, id: reference.id, searchText: unitSearchText)

            // Discard values wildly outside the plausible range (dates, IDs…).
            // Checked AFTER unit conversion so e.g. a glucose of 5.4 mmol/L
            // (→ ~97 mg/dL) is judged against the mg/dL reference range,
            // not the raw mmol/L number.
            if let plausible = reference.referenceRange(for: nil), resolvedValue > plausible.upperBound * 50 {
                continue
            }

            seenIDs.insert(reference.id)
            results.append(ScannedLabValue(reference: reference, value: resolvedValue, sourceLine: trimmed))
        }
        return results
    }

    // MARK: - Public single-image OCR (additive)

    /// Public wrapper over the private `recognizeLines(in:)` OCR pass, for
    /// callers that need raw recognized lines from one already-in-memory
    /// image rather than the lab-catalog-matching `scan(attachments:)` path
    /// — e.g. `MedicationsView`'s prescription scan, which matches lines
    /// against `RxNameMatcher` instead of `LabSynonyms`. Downsamples first
    /// via `ImageDownsampler`, the same convention `ScanReportView` and
    /// `EditReportView` use before handing a camera/photo-library image to
    /// Vision, so a full-resolution capture never hits OCR at full size.
    /// Returns an empty array (never throws) when the image can't be
    /// encoded/decoded; only Vision's own recognition failure is rethrown.
    static func recognizeText(in image: UIImage) async throws -> [String] {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return [] }
        let downsampled = ImageDownsampler.downsampledJPEG(from: jpeg) ?? jpeg
        guard let cgImage = UIImage(data: downsampled)?.cgImage else { return [] }
        return try await recognizeLines(in: cgImage)
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

/// Table-driven unit conversion for lab values reported in a non-canonical
/// unit — chiefly the mmol/L, µmol/L, and g/L units used on Russian/European
/// lab reports where `LabCatalog` stores the canonical value in mg/dL,
/// µg/dL, or g/dL. Applied only to catalog ids where BOTH the canonical
/// unit and a standard molar-conversion factor could be verified against
/// `LabCatalog`; see `LabScanService.parse` callers for where this is used.
///
/// Electrolytes reported in mmol/L whose catalog unit is already
/// numerically equivalent (sodium, potassium, chloride — mEq/L) have no
/// entry here on purpose: `convert` returns the value unchanged when an id
/// has no rule, which is exactly the desired pass-through behavior.
enum LabUnitConversion {

    /// One source-unit token (or spelling variant) plus the multiplier that
    /// turns a value reported in that unit into the catalog's canonical unit
    /// for a given test id.
    struct Rule {
        let tokens: [String]
        let multiplier: Double
    }

    /// Catalog id -> convertible source-unit rules. The search text (the
    /// matched OCR line, already lowercased) is scanned for each token in
    /// turn; the first one found wins.
    static let rules: [String: [Rule]] = [
        // mmol/L -> mg/dL (standard molar conversion factors).
        "fastingGlucose": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 18.016)],
        "totalCholesterol": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 38.67)],
        "ldlCholesterol": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 38.67)],
        "hdlCholesterol": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 38.67)],
        "triglycerides": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 88.57)],
        "calcium": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 4.008)],
        "magnesium": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 2.431)],
        // Urea (mmol/L) -> Blood Urea Nitrogen (mg/dL): the catalog's "bun"
        // id is nitrogen content, not whole-molecule urea, so the factor is
        // urea-mg/dL (×6.006) times the nitrogen fraction 28/60.06 (×0.4663)
        // = ×2.8 overall — the standard clinical urea(mmol/L)->BUN(mg/dL)
        // conversion factor.
        "bun": [Rule(tokens: ["mmol/l", "ммоль/л"], multiplier: 2.8)],

        // µmol/L -> mg/dL (creatinine, bilirubin, uric acid) or µg/dL (iron).
        "creatinine": [Rule(tokens: ["µmol/l", "umol/l", "мкмоль/л"], multiplier: 1 / 88.42)],
        "totalBilirubin": [Rule(tokens: ["µmol/l", "umol/l", "мкмоль/л"], multiplier: 1 / 17.104)],
        "uricAcid": [Rule(tokens: ["µmol/l", "umol/l", "мкмоль/л"], multiplier: 1 / 59.48)],
        "iron": [Rule(tokens: ["µmol/l", "umol/l", "мкмоль/л"], multiplier: 5.585)],

        // g/L -> g/dL (divide by 10).
        "hemoglobin": [Rule(tokens: ["g/l", "г/л"], multiplier: 0.1)],
        "albumin": [Rule(tokens: ["g/l", "г/л"], multiplier: 0.1)],
        "totalProtein": [Rule(tokens: ["g/l", "г/л"], multiplier: 0.1)]

        // Deliberately NOT converted (see LabScanService.swift file header
        // comment / PR notes for the full reasoning):
        //  - "iron" via mmol/L->mg/dL (×5.585): iron's catalog unit is
        //    µg/dL, not mg/dL, so that particular factor does not apply;
        //    the µmol/L->µg/dL rule above is the one that's actually used.
        //  - "phosphorus": commonly reported in mmol/L in Russian reports,
        //    but no factor for it was given/verified here, so it is left
        //    unconverted rather than guess at one.
    ]

    /// Converts `value` to the catalog's canonical unit for `id` if
    /// `searchText` (already lowercased) contains one of that id's
    /// recognized source-unit tokens. Returns `value` unchanged when there
    /// is no rule for `id`, or no token from its rules is found — which is
    /// also the correct behavior for units already matching the canonical
    /// unit (or electrolytes reported in mmol/L, numerically equal to their
    /// mEq/L canonical unit).
    static func convert(_ value: Double, id: String, searchText: String) -> Double {
        guard let candidateRules = rules[id] else { return value }
        for rule in candidateRules {
            for token in rule.tokens where containsToken(token, in: searchText) {
                return value * rule.multiplier
            }
        }
        return value
    }

    /// Same word-boundary rule as `LabSynonyms.match`: the characters
    /// immediately before/after the token (if any) must not be letters, so
    /// e.g. "г/л" doesn't fire inside "мг/л" or "мкг/л".
    private static func containsToken(_ token: String, in text: String) -> Bool {
        guard let range = text.range(of: token) else { return false }
        if range.lowerBound > text.startIndex, text[text.index(before: range.lowerBound)].isLetter {
            return false
        }
        if range.upperBound < text.endIndex, text[range.upperBound].isLetter {
            return false
        }
        return true
    }
}
