import Foundation

// MARK: - CARE-LINKS
//
// Rule-based links between medications and the labs that monitor them,
// symptom -> lab hints, and a prescription-name matcher for OCR. Everything
// here is pure and deterministic: no `Date()` inside, `now` is always passed
// in by the caller, and every type returns ids/enums/dates/numbers only —
// views own all display strings, exactly like `MedicationInteractions`,
// `AnalysisEngine`, and `RetestSchedule`.
//
// EDUCATIONAL, NOT DIAGNOSTIC: these links describe commonly recommended
// monitoring relationships, not a personalized clinical plan. `MedicationLabLinks.disclaimer`
// should accompany any UI list built from this file, matching how
// `MedicationInteractions.disclaimer` and `RetestSchedule.disclaimer` are used.

// MARK: - Monitored vital

/// A vital sign monitored for a medication instead of (or in addition to) a
/// lab test — e.g. amlodipine is followed with blood pressure readings, not
/// a lab draw. Kept as an enum (not a display string) so views localize it.
enum MonitoredVital: String, Equatable {
    case bloodPressure
}

// MARK: - Medication -> lab link

/// One medication class's monitoring profile: the `LabCatalog` test ids
/// worth tracking (primary first, used by `status(for:...)`) and/or a vital.
struct MedicationLabLink: Equatable {
    /// `LabCatalog` ids, primary first. Empty when the medication is
    /// monitored by a vital only (e.g. amlodipine).
    let labIDs: [String]
    /// A vital tracked alongside — or, for vital-only links, instead of —
    /// the labs above.
    let vital: MonitoredVital?
    /// Days of continuous use before the linked labs become relevant to
    /// check (e.g. PPI-associated B12/magnesium depletion is a long-term
    /// effect, not something to flag on day one). `nil` means "relevant from
    /// the start."
    let longTermThresholdDays: Int?

    init(labIDs: [String], vital: MonitoredVital? = nil, longTermThresholdDays: Int? = nil) {
        self.labIDs = labIDs
        self.vital = vital
        self.longTermThresholdDays = longTermThresholdDays
    }

    /// The lab `status(for:...)` tracks for this medication — `nil` for a
    /// vital-only link.
    var primaryLabID: String? { labIDs.first }
}

// MARK: - Medication monitor status

/// The result of checking one medication's linked lab against the latest
/// known data. Carries ids/dates only — no display strings.
enum MedicationMonitorStatus: Equatable {
    /// The linked lab's latest value is in range, measured on or after the
    /// medication's start date. `sinceDate` is that measurement's date.
    case working(labID: String, sinceDate: Date?)
    /// The linked lab's latest value is still out of range.
    case notImproving(labID: String)
    /// The linked lab's retest is overdue or due soon — the data on hand may
    /// be stale, so no working/notImproving call is made yet.
    case checkOverdue(labID: String, dueDate: Date)
    /// No usable snapshot (and no overdue/due-soon retest item) exists yet
    /// for the linked lab.
    case noData(labID: String)
}

// MARK: - MedicationLabLinks

/// Static map from a normalized medication name to the `LabCatalog` test(s)
/// commonly monitored alongside it, plus a status check against on-device
/// data. Name matching mirrors `MedicationInteractions`'s mechanics: a
/// lowercased-token synonym table resolved by longest-match-wins, so brand
/// names, generic names, and (for the drugs mapped here) small Russian/Turkish
/// transliteration aliases all resolve to the same canonical key.
enum MedicationLabLinks {

    static var disclaimer: String {
        String(
            localized: "careLinks.medicationLabLinks.disclaimer",
            defaultValue: """
                These are commonly recommended monitoring pairings, not a personalized \
                plan — your prescriber decides what to check and how often. Always \
                confirm your monitoring schedule with your doctor or pharmacist.
                """,
            table: "Engine"
        )
    }

    // MARK: Canonical drug keys -> monitoring link

    /// Keyed by canonical drug/class key (see `synonyms` below). Every
    /// `labIDs` entry is an ACTUAL `LabCatalog.tests` id.
    static let table: [String: MedicationLabLink] = [
        // Metformin -> HbA1c (primary) + fasting glucose.
        "metformin": MedicationLabLink(labIDs: ["hba1c", "fastingGlucose"]),

        // Statins (atorvastatin/rosuvastatin/simvastatin/pravastatin) ->
        // LDL (primary) + total cholesterol + ALT (muscle/liver monitoring).
        "statin": MedicationLabLink(labIDs: ["ldlCholesterol", "totalCholesterol", "alt"]),

        // Levothyroxine -> TSH (primary) + free T4.
        "levothyroxine": MedicationLabLink(labIDs: ["tsh", "freeT4"]),

        // ACE inhibitors / ARBs (lisinopril, losartan, ...) -> potassium
        // (primary) + creatinine.
        "aceArb": MedicationLabLink(labIDs: ["potassium", "creatinine"]),

        // Amlodipine -> blood pressure vital only (no linked lab test).
        "amlodipine": MedicationLabLink(labIDs: [], vital: .bloodPressure),

        // Warfarin intentionally omitted: its primary monitoring test (INR)
        // is not in LabCatalog, and no other catalog test is a faithful
        // stand-in.

        // Allopurinol -> uric acid.
        "allopurinol": MedicationLabLink(labIDs: ["uricAcid"]),

        // Iron supplements -> ferritin (primary) + hemoglobin.
        "ironSupplement": MedicationLabLink(labIDs: ["ferritin", "hemoglobin"]),

        // Vitamin D supplements -> vitamin D.
        "vitaminDSupplement": MedicationLabLink(labIDs: ["vitaminD"]),

        // Omeprazole / other PPIs -> B12 (primary) + magnesium; only
        // relevant after sustained long-term use.
        "ppi": MedicationLabLink(labIDs: ["vitaminB12", "magnesium"], longTermThresholdDays: 90),

        // Spironolactone -> potassium.
        "spironolactone": MedicationLabLink(labIDs: ["potassium"]),

        // Corticosteroids (prednisone) -> glucose.
        "corticosteroid": MedicationLabLink(labIDs: ["fastingGlucose"]),
    ]

    // MARK: Name -> canonical key synonyms
    //
    // Lowercased token -> canonical drug key. Longest-token-first matching,
    // mirroring `MedicationInteractions.classKey(for:)`. English generic and
    // brand names, plus a small Russian/Turkish transliteration alias set
    // for these specific drugs (Turkish already shares Latin spelling for
    // metformin/atorvastatin/losartan/allopurinol, so only the few names
    // that actually differ in Turkish need an alias).

    fileprivate static let synonyms: [String: String] = [
        // Metformin
        "metformin": "metformin", "glucophage": "metformin",
        "метформин": "metformin",

        // Statins
        "atorvastatin": "statin", "lipitor": "statin", "аторвастатин": "statin",
        "rosuvastatin": "statin", "crestor": "statin", "розувастатин": "statin",
        "simvastatin": "statin", "zocor": "statin", "симвастатин": "statin",
        "pravastatin": "statin", "правастатин": "statin",
        "statin": "statin",

        // Levothyroxine
        "levothyroxine": "levothyroxine", "synthroid": "levothyroxine", "levoxyl": "levothyroxine",
        "левотироксин": "levothyroxine", "levotiroksin": "levothyroxine",

        // ACE inhibitors / ARBs
        "lisinopril": "aceArb", "zestril": "aceArb", "prinivil": "aceArb", "лизиноприл": "aceArb",
        "losartan": "aceArb", "cozaar": "aceArb", "лозартан": "aceArb",
        "enalapril": "aceArb", "эналаприл": "aceArb",
        "ramipril": "aceArb", "рамиприл": "aceArb",
        "valsartan": "aceArb", "валсартан": "aceArb",

        // Amlodipine
        "amlodipine": "amlodipine", "norvasc": "amlodipine",
        "амлодипин": "amlodipine", "amlodipin": "amlodipine",

        // Allopurinol
        "allopurinol": "allopurinol", "zyloprim": "allopurinol", "аллопуринол": "allopurinol",

        // Iron supplements (specific phrases/brands only — a bare "iron"
        // token is deliberately excluded as too common a word for reliable
        // matching against free-text medication names).
        "ferrous sulfate": "ironSupplement", "ferrous gluconate": "ironSupplement",
        "ferrous fumarate": "ironSupplement", "iron supplement": "ironSupplement",
        "feosol": "ironSupplement", "slow fe": "ironSupplement",
        "сульфат железа": "ironSupplement", "железа сульфат": "ironSupplement",
        "demir sülfat": "ironSupplement",

        // Vitamin D supplements
        "vitamin d3": "vitaminDSupplement", "vitamin d supplement": "vitaminDSupplement",
        "cholecalciferol": "vitaminDSupplement", "ergocalciferol": "vitaminDSupplement",
        "vitamin d": "vitaminDSupplement",
        "витамин д3": "vitaminDSupplement", "холекальциферол": "vitaminDSupplement",
        "kolekalsiferol": "vitaminDSupplement",

        // PPIs
        "omeprazole": "ppi", "prilosec": "ppi",
        "esomeprazole": "ppi", "nexium": "ppi",
        "pantoprazole": "ppi", "protonix": "ppi",
        "lansoprazole": "ppi", "prevacid": "ppi",
        "омепразол": "ppi", "эзомепразол": "ppi", "пантопразол": "ppi", "лансопразол": "ppi",
        "omeprazol": "ppi", "pantoprazol": "ppi", "lansoprazol": "ppi", "esomeprazol": "ppi",

        // Spironolactone
        "spironolactone": "spironolactone", "aldactone": "spironolactone",
        "спиронолактон": "spironolactone", "spironolakton": "spironolactone",

        // Corticosteroids
        "prednisone": "corticosteroid", "prednisolone": "corticosteroid", "deltasone": "corticosteroid",
        "преднизон": "corticosteroid", "преднизолон": "corticosteroid",
        "prednizon": "corticosteroid", "prednizolon": "corticosteroid",
    ]

    /// Longest matching synonym token contained in `name` -> canonical drug
    /// key. Mirrors `MedicationInteractions.classKey(for:)` exactly.
    fileprivate static func classKey(for name: String) -> String? {
        let lower = name.lowercased()
        var best: (token: String, key: String)?
        for (token, key) in synonyms where lower.contains(token) {
            if best == nil || token.count > best!.token.count {
                best = (token, key)
            }
        }
        return best?.key
    }

    /// The canonical drug key for a free-text medication name, or `nil` if
    /// unrecognized. Case-insensitive.
    static func drugKey(for medicationName: String) -> String? {
        classKey(for: medicationName)
    }

    /// The monitoring link for a free-text medication name, or `nil` if the
    /// name isn't recognized.
    static func link(for medicationName: String) -> MedicationLabLink? {
        guard let key = classKey(for: medicationName) else { return nil }
        return table[key]
    }

    // MARK: Status

    /// Checks a medication's linked lab against on-device data. Returns
    /// `nil` when the medication isn't recognized, has no linked lab (a
    /// vital-only link like amlodipine), or its long-term threshold hasn't
    /// been reached yet as of `now`.
    static func status(
        for medication: Medication,
        snapshots: [LabSnapshot],
        retestItems: [RetestItem],
        now: Date
    ) -> MedicationMonitorStatus? {
        guard let key = classKey(for: medication.name),
              let link = table[key],
              let labID = link.primaryLabID else { return nil }

        if let thresholdDays = link.longTermThresholdDays {
            let elapsedDays = now.timeIntervalSince(medication.startDate) / 86_400
            guard elapsedDays >= Double(thresholdDays) else { return nil }
        }

        let snapshot = snapshots.first { $0.id.caseInsensitiveCompare(labID) == .orderedSame }
        let retestItem = retestItems.first { $0.id.caseInsensitiveCompare(labID) == .orderedSame }

        if let retestItem, retestItem.status == .overdue || retestItem.status == .dueSoon {
            return .checkOverdue(labID: labID, dueDate: retestItem.dueDate)
        }

        guard let snapshot else {
            return .noData(labID: labID)
        }

        switch snapshot.status {
        case .low, .high, .criticalLow, .criticalHigh:
            return .notImproving(labID: labID)
        case .normal:
            if snapshot.date >= medication.startDate {
                return .working(labID: labID, sinceDate: snapshot.date)
            }
            return .noData(labID: labID)
        case .unknown:
            return .noData(labID: labID)
        }
    }
}

// MARK: - Symptom hint

/// One symptom -> lab suggestion, returned only when the lab is actually out
/// of range in the caller's data — never speculative.
struct SymptomHint {
    let symptomID: String
    let labID: String
    let status: LabStatus
}

// MARK: - SymptomLabHints

/// Static map from a normalized symptom name to the `LabCatalog` test(s)
/// worth checking, gated on that lab actually being low/high in the given
/// snapshots. Symptom names are matched case-insensitively via a small
/// English + Russian alias list.
enum SymptomLabHints {

    private enum Direction {
        case low
        case high
    }

    private struct Rule {
        let labID: String
        let direction: Direction
    }

    /// Lowercased token -> canonical symptom id. Longest-token-first
    /// matching, same mechanics as `MedicationLabLinks.classKey(for:)`.
    fileprivate static let symptomAliases: [String: String] = [
        // Fatigue
        "fatigue": "fatigue", "tired": "fatigue", "tiredness": "fatigue", "exhaustion": "fatigue", "low energy": "fatigue",
        "усталость": "fatigue", "слабость": "fatigue", "утомляемость": "fatigue",

        // Dizziness
        "dizziness": "dizziness", "dizzy": "dizziness", "vertigo": "dizziness", "lightheaded": "dizziness",
        "головокружение": "dizziness",

        // Headache (aliased for normalization even though it has no hint rule)
        "headache": "headache", "migraine": "headache",
        "головная боль": "headache", "мигрень": "headache",

        // Hair loss
        "hair loss": "hairLoss", "hair thinning": "hairLoss", "alopecia": "hairLoss",
        "выпадение волос": "hairLoss",

        // Muscle cramps
        "muscle cramps": "muscleCramps", "cramps": "muscleCramps", "muscle spasms": "muscleCramps", "spasms": "muscleCramps",
        "судороги": "muscleCramps", "мышечные спазмы": "muscleCramps",

        // Bone / joint pain
        "bone pain": "bonePain", "joint pain": "bonePain", "joint ache": "bonePain",
        "боль в костях": "bonePain", "боль в суставах": "bonePain",

        // Bruising
        "bruising": "bruising", "bruises": "bruising", "easy bruising": "bruising",
        "синяки": "bruising", "кровоподтеки": "bruising",

        // Thirst / frequent urination
        "thirst": "frequentUrination", "frequent urination": "frequentUrination",
        "increased thirst": "frequentUrination", "polyuria": "frequentUrination",
        "жажда": "frequentUrination", "частое мочеиспускание": "frequentUrination",

        // Cold intolerance
        "cold intolerance": "coldIntolerance", "feeling cold": "coldIntolerance", "sensitivity to cold": "coldIntolerance",
        "непереносимость холода": "coldIntolerance", "зябкость": "coldIntolerance",
    ]

    /// Canonical symptom id -> labs worth checking, gated on the stated
    /// direction. `dizziness` also carries a blood-pressure vital
    /// association (see `linkedVital(for:)`) that isn't evaluated here since
    /// `hints(for:snapshots:)` only receives lab snapshots.
    private static let rules: [String: [Rule]] = [
        "fatigue": [
            Rule(labID: "ferritin", direction: .low),
            Rule(labID: "hemoglobin", direction: .low),
            Rule(labID: "tsh", direction: .low),
            Rule(labID: "vitaminD", direction: .low),
            Rule(labID: "vitaminB12", direction: .low),
        ],
        "dizziness": [
            Rule(labID: "hemoglobin", direction: .low),
        ],
        "hairLoss": [
            Rule(labID: "ferritin", direction: .low),
            Rule(labID: "tsh", direction: .high),
        ],
        "muscleCramps": [
            Rule(labID: "magnesium", direction: .low),
            Rule(labID: "potassium", direction: .low),
            Rule(labID: "calcium", direction: .low),
        ],
        "bonePain": [
            Rule(labID: "vitaminD", direction: .low),
        ],
        "bruising": [
            Rule(labID: "platelets", direction: .low),
        ],
        "frequentUrination": [
            Rule(labID: "fastingGlucose", direction: .high),
            Rule(labID: "hba1c", direction: .high),
        ],
        "coldIntolerance": [
            Rule(labID: "tsh", direction: .high),
        ],
    ]

    /// A vital worth checking alongside a symptom's labs, for symptoms where
    /// one applies (e.g. dizziness -> blood pressure). `nil` for symptoms
    /// with no vital association. Informational only — this file has no
    /// vital-status classifier, so the vital itself is never evaluated here.
    static func linkedVital(for symptomName: String) -> MonitoredVital? {
        guard let id = normalizedSymptomID(for: symptomName) else { return nil }
        return id == "dizziness" ? .bloodPressure : nil
    }

    /// Longest matching alias token contained in `symptomName` -> canonical
    /// symptom id, or `nil` if unrecognized.
    static func normalizedSymptomID(for symptomName: String) -> String? {
        let lower = symptomName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var best: (token: String, id: String)?
        for (token, id) in symptomAliases where lower.contains(token) {
            if best == nil || token.count > best!.token.count {
                best = (token, id)
            }
        }
        return best?.id
    }

    /// Labs worth checking for `symptomName`, restricted to those that are
    /// ACTUALLY out of range (in the stated direction) in `snapshots`.
    /// Returns an empty array for an unrecognized symptom, a symptom with no
    /// rule (e.g. headache), or when every linked lab is in range/missing.
    static func hints(for symptomName: String, snapshots: [LabSnapshot]) -> [SymptomHint] {
        guard let id = normalizedSymptomID(for: symptomName), let ruleList = rules[id] else { return [] }

        var results: [SymptomHint] = []
        for rule in ruleList {
            guard let snapshot = snapshots.first(where: { $0.id.caseInsensitiveCompare(rule.labID) == .orderedSame }) else { continue }
            if matches(rule.direction, status: snapshot.status) {
                results.append(SymptomHint(symptomID: id, labID: rule.labID, status: snapshot.status))
            }
        }
        return results
    }

    private static func matches(_ direction: Direction, status: LabStatus) -> Bool {
        switch direction {
        case .low:
            switch status {
            case .low, .criticalLow: return true
            default: return false
            }
        case .high:
            switch status {
            case .high, .criticalHigh: return true
            default: return false
            }
        }
    }
}

// MARK: - Detected medication (RxNameMatcher)

/// One medication recognized in a scanned prescription line.
struct DetectedMedication: Equatable {
    /// Canonical drug/class key — a `MedicationLabLinks.table` key when the
    /// drug is one we monitor labs for, otherwise a mirrored
    /// `MedicationInteractions` class key (e.g. "warfarin", "nsaid").
    let drugKey: String
    /// The exact substring matched in the source line (original casing).
    let matchedName: String
    /// Parsed dose amount, if an adjacent number + unit token was found.
    let doseValue: Double?
    /// Canonicalized dose unit: "mg", "mcg", or "iu".
    let doseUnit: String?
    /// Remaining free text after the dose (or after the drug name, if no
    /// dose was found) — e.g. "2 times a day" or "nightly". Raw OCR text,
    /// not a display string authored by this app.
    let frequencyHint: String?
    let sourceLine: String
}

// MARK: - RxNameMatcher

/// Scans OCR'd prescription-photo lines for known drug names and extracts an
/// adjacent dose and optional frequency hint. Deterministic and static,
/// tested the same way as `LabScanService.parse(lines:)`.
enum RxNameMatcher {

    /// Mirrors `MedicationInteractions`'s private synonym table (English
    /// generic + brand names only) so prescription photos can flag
    /// interaction-relevant drugs even when they aren't part of
    /// `MedicationLabLinks.table`. Kept in sync by hand since the original
    /// table is private to that file and this file may not edit it.
    fileprivate static let mirroredInteractionTokens: [String: String] = [
        "warfarin": "warfarin", "coumadin": "warfarin", "jantoven": "warfarin",
        "aspirin": "aspirin", "acetylsalicylic": "aspirin",
        "clopidogrel": "clopidogrel", "plavix": "clopidogrel",
        "ibuprofen": "nsaid", "advil": "nsaid", "motrin": "nsaid",
        "naproxen": "nsaid", "aleve": "nsaid", "diclofenac": "nsaid",
        "meloxicam": "nsaid", "celecoxib": "nsaid",
        "sertraline": "ssri", "zoloft": "ssri",
        "fluoxetine": "ssri", "prozac": "ssri",
        "citalopram": "ssri", "escitalopram": "ssri", "lexapro": "ssri",
        "paroxetine": "ssri", "paxil": "ssri", "venlafaxine": "ssri",
        "duloxetine": "ssri", "cymbalta": "ssri",
        "phenelzine": "maoi", "tranylcypromine": "maoi", "isocarboxazid": "maoi", "selegiline": "maoi",
        "sumatriptan": "triptan", "imitrex": "triptan", "rizatriptan": "triptan", "maxalt": "triptan",
        "tramadol": "tramadol", "ultram": "tramadol",
        "oxycodone": "opioid", "oxycontin": "opioid", "hydrocodone": "opioid",
        "morphine": "opioid", "fentanyl": "opioid", "codeine": "opioid",
        "alprazolam": "benzodiazepine", "xanax": "benzodiazepine",
        "lorazepam": "benzodiazepine", "ativan": "benzodiazepine",
        "diazepam": "benzodiazepine", "valium": "benzodiazepine",
        "clonazepam": "benzodiazepine", "klonopin": "benzodiazepine",
        "digoxin": "digoxin", "lanoxin": "digoxin",
        "amiodarone": "amiodarone", "pacerone": "amiodarone",
        "sildenafil": "pde5", "viagra": "pde5",
        "tadalafil": "pde5", "cialis": "pde5",
        "nitroglycerin": "nitrate", "isosorbide": "nitrate",
        "methotrexate": "methotrexate",
        "lithium": "lithium",
    ]

    /// The union of `MedicationLabLinks`'s synonyms and the mirrored
    /// `MedicationInteractions` tokens — every drug name/alias this matcher
    /// recognizes. `MedicationLabLinks`'s entries win on key collisions
    /// (there are none in practice; both sides agree where drugs overlap).
    fileprivate static let knownDrugTokens: [String: String] =
        MedicationLabLinks.synonyms.merging(mirroredInteractionTokens) { existing, _ in existing }

    /// Recognized dose-unit tokens (lowercased) -> canonical unit string.
    fileprivate static let doseUnitAliases: [String: String] = [
        "mg": "mg", "мг": "mg",
        "mcg": "mcg", "µg": "mcg", "мкг": "mcg",
        "iu": "iu", "ме": "iu",
    ]

    /// Scans each line independently for the best (longest) known drug
    /// match, then extracts an adjacent dose and trailing frequency hint.
    /// Lines with no recognized drug name produce no result.
    static func detect(lines: [String]) -> [DetectedMedication] {
        var results: [DetectedMedication] = []
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            guard let match = bestMatch(in: trimmed) else { continue }

            let remainder = String(trimmed[match.range.upperBound...])
            let dose = extractDose(from: remainder)

            let frequencySource: Substring
            if let dose {
                frequencySource = remainder[dose.range.upperBound...]
            } else {
                frequencySource = Substring(remainder)
            }
            let frequency = frequencySource.trimmingCharacters(in: .whitespaces)

            results.append(DetectedMedication(
                drugKey: match.drugKey,
                matchedName: String(trimmed[match.range]),
                doseValue: dose?.value,
                doseUnit: dose?.unit,
                frequencyHint: frequency.isEmpty ? nil : frequency,
                sourceLine: trimmed
            ))
        }
        return results
    }

    // MARK: Matching

    private static func bestMatch(in trimmed: String) -> (token: String, drugKey: String, range: Range<String.Index>)? {
        let lowerLine = trimmed.lowercased()
        guard lowerLine.count >= 3 else { return nil }

        var best: (token: String, drugKey: String, lowerRange: Range<String.Index>)?
        for (token, drugKey) in knownDrugTokens where lowerLine.contains(token) {
            guard let range = lowerLine.range(of: token) else { continue }
            if best == nil || token.count > best!.token.count {
                best = (token, drugKey, range)
            }
        }
        guard let best else { return nil }

        let startOffset = lowerLine.distance(from: lowerLine.startIndex, to: best.lowerRange.lowerBound)
        let endOffset = lowerLine.distance(from: lowerLine.startIndex, to: best.lowerRange.upperBound)
        let start = trimmed.index(trimmed.startIndex, offsetBy: startOffset)
        let end = trimmed.index(trimmed.startIndex, offsetBy: endOffset)
        return (best.token, best.drugKey, start..<end)
    }

    // MARK: Dose extraction

    /// Finds the first `<number><optional space><unit>` token in `text`
    /// (e.g. "500 мг", "20mg"). A bare number with no recognized unit right
    /// after it is skipped — this is the guard that keeps a frequency count
    /// like "2 times a day" from being misread as a dose.
    private static func extractDose(from text: String) -> (value: Double, unit: String, range: Range<String.Index>)? {
        var idx = text.startIndex
        while idx < text.endIndex {
            guard text[idx].isNumber else {
                idx = text.index(after: idx)
                continue
            }

            var numberEnd = idx
            while numberEnd < text.endIndex, text[numberEnd].isNumber || text[numberEnd] == "." || text[numberEnd] == "," {
                numberEnd = text.index(after: numberEnd)
            }
            let numberToken = text[idx..<numberEnd].replacingOccurrences(of: ",", with: ".")

            defer { idx = numberEnd }
            guard let value = Double(numberToken) else { continue }

            var unitStart = numberEnd
            while unitStart < text.endIndex, text[unitStart] == " " {
                unitStart = text.index(after: unitStart)
            }
            var unitEnd = unitStart
            while unitEnd < text.endIndex, text[unitEnd].isLetter {
                unitEnd = text.index(after: unitEnd)
            }
            let rawUnit = text[unitStart..<unitEnd].lowercased()
            guard let canonicalUnit = doseUnitAliases[rawUnit] else { continue }

            return (value, canonicalUnit, idx..<unitEnd)
        }
        return nil
    }
}
