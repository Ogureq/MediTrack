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
        "hemoglobin": [
            "haemoglobin",
            "гемоглобин" // ru (tr spelling matches the English name already)
        ],
        "hematocrit": [
            "haematocrit", "pcv",
            "гематокрит", // ru
            "hematokrit" // tr
        ],
        "redBloodCells": [
            "erythrocytes",
            "эритроциты", // ru
            "eritrosit" // tr
        ],
        "whiteBloodCells": [
            "leukocytes", "leucocytes",
            "лейкоциты", // ru
            "lökosit", "lokosit" // tr
        ],
        "platelets": [
            "thrombocytes",
            "тромбоциты", // ru
            "trombosit" // tr
        ],
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
            "cholesterol", "cholesterol total", "total chol",
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
            "trigs", "triglyceride",
            "триглицериды", // ru
            "trigliserid", "trigliserit" // tr (both spellings seen on reports)
        ],

        // MARK: Metabolic
        "fastingGlucose": [
            "glucose", "glucose fasting", "fasting blood sugar", "fbs", "blood sugar",
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
        "calcium": [
            "serum calcium", "calcium total",
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
            "urea nitrogen", "urea",
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
            "sgpt", "alanine transaminase",
            "алт", "аланинаминотрансфераза", // ru
            "alanin aminotransferaz" // tr (also written "ALT", auto-matched)
        ],
        "ast": [
            "sgot", "aspartate transaminase",
            "аст", "аспартатаминотрансфераза", // ru
            "aspartat aminotransferaz" // tr (also written "AST", auto-matched)
        ],
        "alp": [
            "alk phos",
            "щелочная фосфатаза", // ru
            "alkalen fosfataz" // tr
        ],
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
            "ожсс", "общая железосвязывающая способность", // ru
            "demir bağlama kapasitesi", "demir baglama kapasitesi", "tdbk" // tr
        ],
        // iron: catalog name "Serum Iron" + shortName "Iron" already cover it
        // in English; extra ru/tr aliases below.
        "iron": [
            "железо", "сывороточное железо", // ru
            "demir" // tr
        ],

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
