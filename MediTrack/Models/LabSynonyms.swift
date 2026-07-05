//
//  LabSynonyms.swift
//  MediTrack
//
//  OCR-matching helper. Maps common report-form aliases (as they appear on
//  scanned/OCR'd lab reports) to entries in `LabCatalog`. Each catalog test's
//  `name` and `shortName` are matched automatically by `match(in:)`, so the
//  `aliases` table below holds ONLY the extra spellings/abbreviations not
//  already present in the catalog. All aliases are lowercase, at least three
//  characters long, and word-bounded when matched.
//
//  Education only; not medical advice.
//

import Foundation

/// Maps common report-form aliases (OCR'd text) to catalog lab tests.
enum LabSynonyms {

    /// Extra lowercase aliases per catalog id. Names and shortNames from the
    /// catalog are matched automatically by `match(in:)` and must NOT be repeated here.
    static let aliases: [String: [String]] = [

        // MARK: Hematology (CBC)
        // (name "Hgb"/"Hct"/"WBC"/"RBC"/"PLT" short names are auto-matched)
        "hemoglobin": ["haemoglobin"],
        "hematocrit": ["haematocrit", "pcv"],
        "redBloodCells": ["erythrocytes"],
        "whiteBloodCells": ["leukocytes", "leucocytes"],
        "platelets": ["thrombocytes"],
        "neutrophilsPercent": ["neut", "neutrophil"],
        "lymphocytesPercent": ["lymph", "lymphocyte"],
        // mcv/mch/mchc/rdw: catalog name + shortName already suffice.

        // MARK: Lipid Panel
        "totalCholesterol": ["cholesterol", "cholesterol total", "total chol"],
        "ldlCholesterol": ["ldl-c", "ldl chol"],
        "hdlCholesterol": ["hdl-c", "hdl chol"],
        "triglycerides": ["trigs", "triglyceride"],

        // MARK: Metabolic
        "fastingGlucose": ["glucose", "glucose fasting", "fasting blood sugar", "fbs", "blood sugar"],
        "hba1c": ["a1c", "hb a1c", "glycated hemoglobin", "glycosylated hemoglobin", "glycohemoglobin"],
        "insulin": ["serum insulin"],

        // MARK: Kidney & Electrolytes
        "sodium": ["serum sodium"],
        "potassium": ["serum potassium"],
        "chloride": ["serum chloride"],
        "calcium": ["serum calcium", "calcium total"],
        "magnesium": ["serum magnesium"],
        "phosphorus": ["phosphate"],
        "creatinine": ["creat", "serum creatinine"],
        "bun": ["urea nitrogen", "urea"],
        "egfr": ["gfr", "glomerular filtration"],
        "uricAcid": ["urate", "uric acid serum"],

        // MARK: Liver Function
        "alt": ["sgpt", "alanine transaminase"],
        "ast": ["sgot", "aspartate transaminase"],
        "alp": ["alk phos"],
        "ggt": ["gamma gt", "gamma-gt", "gamma glutamyl transferase"],
        "totalBilirubin": ["bilirubin", "bilirubin total"],
        "albumin": ["serum albumin"],
        "totalProtein": ["protein total", "total protein serum"],

        // MARK: Thyroid
        "tsh": ["thyroid stimulating hormone", "thyrotropin"],
        "freeT4": ["free t4", "thyroxine free"],
        "freeT3": ["free t3"],

        // MARK: Vitamins & Minerals
        "vitaminD": ["vitamin d", "vitamin d3", "25-oh vitamin d", "25-hydroxyvitamin d", "25-oh"],
        "vitaminB12": ["vit b12", "cobalamin"],
        "folate": ["folic acid", "vitamin b9"],
        "ferritin": ["serum ferritin"],
        "tibc": ["total iron binding capacity", "iron binding capacity"],
        // iron: catalog name "Serum Iron" + shortName "Iron" already cover it.

        // MARK: Inflammation
        "crp": ["c reactive protein", "hs-crp", "hscrp"],
        "esr": ["sed rate", "sedimentation rate"]
    ]

    /// Finds the catalog test mentioned in an OCR'd line.
    /// - Parameter lowercasedLine: the line, ALREADY lowercased by the caller.
    /// - Returns: the matched reference and the range of the matched alias
    ///   within `lowercasedLine`. When several tests match, the longest
    ///   matched alias wins (ties: earliest range in the line).
    static func match(in lowercasedLine: String) -> (reference: LabReference, range: Range<String.Index>)? {
        var best: (reference: LabReference, range: Range<String.Index>, length: Int)?

        for test in LabCatalog.tests {
            var candidates = [test.name.lowercased(), test.shortName.lowercased()]
            if let extra = aliases[test.id] {
                candidates.append(contentsOf: extra)
            }

            for candidate in candidates {
                // Ignore candidates shorter than three characters.
                guard candidate.count >= 3 else { continue }
                guard let range = lowercasedLine.range(of: candidate) else { continue }

                // Word-boundary check: the neighbor characters (if any) must not be letters.
                if range.lowerBound > lowercasedLine.startIndex {
                    let before = lowercasedLine[lowercasedLine.index(before: range.lowerBound)]
                    if before.isLetter { continue }
                }
                if range.upperBound < lowercasedLine.endIndex {
                    let after = lowercasedLine[range.upperBound]
                    if after.isLetter { continue }
                }

                // Keep the longest match; break ties by earliest lower bound.
                let length = candidate.count
                if let current = best {
                    if length > current.length
                        || (length == current.length && range.lowerBound < current.range.lowerBound) {
                        best = (test, range, length)
                    }
                } else {
                    best = (test, range, length)
                }
            }
        }

        guard let best = best else { return nil }
        return (best.reference, best.range)
    }
}
