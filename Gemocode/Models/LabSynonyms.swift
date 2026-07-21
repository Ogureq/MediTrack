//
//  LabSynonyms.swift
//  Gemocode
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
    ///
    /// Russian (ru) and Turkish (tr) entries follow the same rules as the
    /// English ones: lowercase, word-bounded by `match(in:)`. Where a
    /// Turkish source term uses a diacritic (ı, ş, ğ, ç, ö, ü), an
    /// ascii-folded spelling is included alongside it, because `parse(lines:)`
    /// lowercases OCR text with the locale-insensitive `String.lowercased()`,
    /// which folds the Turkish dotless capital "I" to ascii "i" (not "ı") —
    /// so all-caps report headers ("AÇLIK KAN ŞEKERİ") end up matching the
    /// ascii-folded spelling, not the native one.
    static let aliases: [String: [String]] = [

        // MARK: Hematology (CBC)
        // (name "Hgb"/"Hct"/"WBC"/"RBC"/"PLT" short names are auto-matched)
        // "haemoglobin" (UK spelling) was already added in a prior wave —
        // no change needed here.
        "hemoglobin": [
            "haemoglobin",
            "гемоглобин" // ru (tr spelling matches the English name already)
        ],
        // "haematocrit" (UK spelling) was already added in a prior wave.
        // There is no separate "hct" catalog id to alias onto — the single
        // "hematocrit" entry's own shortName ("Hct") already auto-matches
        // bare "HCT"/"Hct" on a report, so nothing further is needed.
        "hematocrit": [
            "haematocrit", "pcv",
            "гематокрит", // ru
            "hematokrit" // tr
        ],
        "redBloodCells": [
            "erythrocytes", "red cell count", // uk
            "эритроциты", // ru
            "eritrosit" // tr
        ],
        "whiteBloodCells": [
            "leukocytes", "leucocytes", "white cell count", // uk
            "лейкоциты", // ru
            "lökosit", "lokosit" // tr
        ],
        "platelets": [
            "thrombocytes",
            "тромбоциты", // ru
            "trombosit" // tr
        ],
        // "Platelet Count" is the catalog's own `name`, so it is already
        // auto-matched by `match(in:)` without needing an alias here.
        "neutrophilsPercent": [
            "neut", "neutrophil",
            "нейтрофилы", // ru
            "nötrofil", "notrofil" // tr
        ],
        "lymphocytesPercent": [
            "lymph", "lymphocyte",
            "лимфоциты", // ru
            "lenfosit" // tr
        ],
        // mcv/mch/mchc/rdw: catalog name + shortName already suffice — these
        // stay printed as English abbreviations on Russian/Turkish reports too.

        // MARK: Lipid Panel
        "totalCholesterol": [
            "cholesterol", "cholesterol total", "total chol", "fasting cholesterol", // uk
            "холестерин общий", "общий холестерин", // ru
            "total kolesterol", "toplam kolesterol" // tr
        ],
        "ldlCholesterol": [
            "ldl-c", "ldl chol",
            "лпнп", // ru
            "ldl kolesterol" // tr
        ],
        "hdlCholesterol": [
            "hdl-c", "hdl chol",
            "лпвп", // ru
            "hdl kolesterol" // tr
        ],
        "triglycerides": [
            "trigs", "triglyceride", "fasting triglycerides", // uk
            "триглицериды", // ru
            "trigliserid", "trigliserit" // tr (both spellings seen on reports)
        ],

        // MARK: Metabolic
        "fastingGlucose": [
            "glucose", "glucose fasting", "fasting blood glucose", "fasting blood sugar", "fbs", "blood sugar", // uk adds "fasting blood glucose"
            "глюкоза", "глюкоза натощак", // ru
            "glukoz", "açlık kan şekeri", "aclik kan sekeri" // tr
        ],
        "hba1c": [
            "a1c", "hb a1c", "glycated hemoglobin", "glycosylated hemoglobin", "glycohemoglobin",
            "гликированный гемоглобин", "гликозилированный гемоглобин", // ru
            "glikozile hemoglobin" // tr (also written just "HbA1c", auto-matched)
        ],
        "insulin": [
            "serum insulin",
            "инсулин", // ru
            "insülin", "insulin" // tr
        ],

        // MARK: Kidney & Electrolytes
        "sodium": [
            "serum sodium",
            "натрий", // ru
            "sodyum" // tr
        ],
        "potassium": [
            "serum potassium",
            "калий", // ru
            "potasyum" // tr
        ],
        "chloride": [
            "serum chloride",
            "хлор", "хлориды", // ru
            "klor", "klorür", "klorur" // tr
        ],
        // "corrected calcium" (albumin-adjusted) is added as an alias to the
        // same "calcium" catalog id rather than a separate test — the
        // catalog has no distinct entry for it. On a typical UK panel the
        // plain "Calcium" row is printed before "Corrected Calcium", and
        // `parse(lines:)` dedupes by first occurrence (`seenIDs`), so when
        // both rows are present the RAW (uncorrected) value is the one that
        // gets imported and the corrected row is silently skipped. That's an
        // accepted limitation here, not a bug this alias introduces: without
        // the alias, "Corrected Calcium" wouldn't import at all; with it,
        // whichever of the two rows appears first in the report wins, same
        // as every other duplicate-test row in this parser.
        "calcium": [
            "serum calcium", "calcium total", "corrected calcium",
            "кальций", // ru
            "kalsiyum" // tr
        ],
        "magnesium": [
            "serum magnesium",
            "магний", // ru
            "magnezyum" // tr
        ],
        "phosphorus": [
            "phosphate",
            "фосфор", // ru
            "fosfor" // tr
        ],
        "creatinine": [
            "creat", "serum creatinine",
            "креатинин", // ru
            "kreatinin" // tr
        ],
        "bun": [
            "urea nitrogen", "urea", // "urea" alone already covers UK reports that print just "Urea"
            "мочевина", "азот мочевины крови", // ru
            "üre", "ure", "kan üre azotu", "kan ure azotu" // tr
        ],
        "egfr": [
            "gfr", "glomerular filtration",
            "скорость клубочковой фильтрации", "скф", // ru
            "glomerüler filtrasyon hızı", "glomeruler filtrasyon hizi" // tr
        ],
        "uricAcid": [
            "urate", "uric acid serum",
            "мочевая кислота", // ru
            "ürik asit", "urik asit" // tr
        ],

        // MARK: Liver Function
        "alt": [
            "sgpt", "alanine transaminase", "alanine transferase", // uk (imprecise but seen on reports)
            "алт", "аланинаминотрансфераза", // ru
            "alanin aminotransferaz" // tr (also written "ALT", auto-matched)
        ],
        "ast": [
            "sgot", "aspartate transaminase", "aspartate transferase", // uk (imprecise but seen on reports)
            "аст", "аспартатаминотрансфераза", // ru
            "aspartat aminotransferaz" // tr (also written "AST", auto-matched)
        ],
        "alp": [
            "alk phos",
            "щелочная фосфатаза", // ru
            "alkalen fosfataz" // tr
        ],
        // "gamma gt" (UK form) was already added in a prior wave.
        "ggt": [
            "gamma gt", "gamma-gt", "gamma glutamyl transferase",
            "ггт", "гамма-глутамилтрансфераза", "гамма-гт", // ru
            "gama glutamil transferaz" // tr (also written "GGT", auto-matched)
        ],
        "totalBilirubin": [
            "bilirubin", "bilirubin total",
            "билирубин общий", "общий билирубин", // ru
            "total bilirubin", "toplam bilirubin" // tr
        ],
        "albumin": [
            "serum albumin",
            "альбумин", // ru
            "albümin", "albumin" // tr
        ],
        "totalProtein": [
            "protein total", "total protein serum",
            // "total protein" (UK form) is also the catalog's own `name`
            // ("Total Protein"), so it is already auto-matched by
            // `match(in:)` without needing to be repeated here.
            "общий белок", "белок общий", // ru
            "total protein", "toplam protein" // tr
        ],

        // MARK: Thyroid
        "tsh": [
            "thyroid stimulating hormone", "thyrotropin",
            "ттг" // ru (also written "TSH", auto-matched, incl. on Turkish reports)
        ],
        "freeT4": [
            "free t4", "thyroxine free",
            "т4 свободный", "свободный т4", "св т4", // ru
            "serbest t4" // tr
        ],
        "freeT3": [
            "free t3",
            "т3 свободный", "свободный т3", "св т3", // ru
            "serbest t3" // tr
        ],

        // MARK: Vitamins & Minerals
        "vitaminD": [
            "vitamin d", "vitamin d3", "25-oh vitamin d", "25-hydroxyvitamin d", "25-oh",
            "витамин d", "витамин д", // ru
            "d vitamini" // tr
        ],
        "vitaminB12": [
            "vit b12", "cobalamin",
            "витамин b12", "витамин в12", "кобаламин", // ru
            "b12 vitamini", "vitamin b12" // tr
        ],
        "folate": [
            "folic acid", "vitamin b9",
            "фолиевая кислота", "фолат", // ru
            "folat", "folik asit" // tr
        ],
        "ferritin": [
            "serum ferritin",
            "ферритин" // ru (tr spelling matches the English name already)
        ],
        "tibc": [
            "total iron binding capacity", "iron binding capacity",
            // Dotted UK form. Plain "tibc" already auto-matches via the
            // catalog's own shortName ("TIBC" -> lowercased "tibc"); the dots
            // here are non-letters, so the word-boundary check in
            // `match(in:)` (which only looks at the characters immediately
            // outside the matched range) is unaffected by them.
            "t.i.b.c",
            "ожсс", "общая железосвязывающая способность", // ru
            "demir bağlama kapasitesi", "demir baglama kapasitesi", "tdbk" // tr
        ],
        // iron: catalog name "Serum Iron" + shortName "Iron" already cover it
        // in English; extra ru/tr aliases below.
        "iron": [
            "железо", "сывороточное железо", // ru
            "demir" // tr
        ],
        // Transferrin saturation ("TSAT", "% saturation") appears on some UK
        // iron panels but has no corresponding entry in `LabCatalog` — it is
        // NOT added here. Adding an alias without a matching catalog id would
        // have nowhere to route the match, so per the task's own instruction
        // ("only for tests that EXIST in LabCatalog"), this one is skipped.

        // MARK: Inflammation
        "crp": [
            "c reactive protein", "hs-crp", "hscrp",
            "с-реактивный белок", "срб", // ru
            "c-reaktif protein" // tr (also written "CRP", auto-matched)
        ],
        "esr": [
            "sed rate", "sedimentation rate",
            "соэ", "скорость оседания эритроцитов", // ru
            "sedimantasyon", "sedimentasyon" // tr
        ]
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
