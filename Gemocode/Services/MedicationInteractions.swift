import Foundation

// MARK: - Medication interaction checker
//
// A curated, EDUCATIONAL check for well-established drug–drug interactions.
// This list is intentionally small and is NOT a substitute for a pharmacist's
// review. Absence of a warning here does not mean a combination is safe.

enum InteractionSeverity: Int, Comparable, CaseIterable, Identifiable {
    case minor = 0
    case moderate = 1
    case major = 2

    var id: Int { rawValue }

    static func < (lhs: InteractionSeverity, rhs: InteractionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .minor: "Minor"
        case .moderate: "Moderate"
        case .major: "Major"
        }
    }

    var systemImage: String {
        switch self {
        case .minor: "info.circle.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .major: "exclamationmark.octagon.fill"
        }
    }
}

struct DrugInteraction: Identifiable, Hashable {
    let id = UUID()
    let drugA: String
    let drugB: String
    let severity: InteractionSeverity
    let explanation: String
    let recommendation: String
}

enum MedicationInteractions {

    static let disclaimer = """
        This is an educational check against a small list of well-known \
        interactions — it is not exhaustive. The absence of a warning does \
        not mean a combination is safe. Always confirm your full medication \
        list with your pharmacist or doctor.
        """

    // MARK: Drug classes and synonyms
    //
    // Maps a lowercased token (brand or generic name, or a class term) to a
    // canonical class key. Matching is longest-token-first to avoid loose hits.

    private static let synonyms: [String: String] = [
        // Anticoagulant (warfarin)
        "warfarin": "warfarin", "coumadin": "warfarin", "jantoven": "warfarin",
        // Antiplatelet / aspirin
        "aspirin": "aspirin", "acetylsalicylic": "aspirin",
        "clopidogrel": "clopidogrel", "plavix": "clopidogrel",
        // NSAIDs
        "ibuprofen": "nsaid", "advil": "nsaid", "motrin": "nsaid",
        "naproxen": "nsaid", "aleve": "nsaid", "diclofenac": "nsaid",
        "meloxicam": "nsaid", "celecoxib": "nsaid", "nsaid": "nsaid",
        // Statins
        "atorvastatin": "statin", "lipitor": "statin",
        "simvastatin": "statin", "zocor": "statin",
        "rosuvastatin": "statin", "crestor": "statin",
        "pravastatin": "statin", "statin": "statin",
        // ACE inhibitors
        "lisinopril": "ace_inhibitor", "enalapril": "ace_inhibitor",
        "ramipril": "ace_inhibitor", "benazepril": "ace_inhibitor",
        "ace inhibitor": "ace_inhibitor",
        // ARBs
        "losartan": "arb", "valsartan": "arb", "olmesartan": "arb",
        "irbesartan": "arb", "candesartan": "arb",
        // Potassium-sparing / potassium
        "spironolactone": "potassium_sparing", "eplerenone": "potassium_sparing",
        "amiloride": "potassium_sparing", "triamterene": "potassium_sparing",
        "potassium chloride": "potassium", "potassium": "potassium",
        // SSRIs / SNRIs
        "sertraline": "ssri", "zoloft": "ssri",
        "fluoxetine": "ssri", "prozac": "ssri",
        "citalopram": "ssri", "escitalopram": "ssri", "lexapro": "ssri",
        "paroxetine": "ssri", "paxil": "ssri", "venlafaxine": "ssri",
        "duloxetine": "ssri", "cymbalta": "ssri",
        // MAOIs
        "phenelzine": "maoi", "tranylcypromine": "maoi",
        "isocarboxazid": "maoi", "selegiline": "maoi", "maoi": "maoi",
        // Triptans
        "sumatriptan": "triptan", "imitrex": "triptan",
        "rizatriptan": "triptan", "maxalt": "triptan", "triptan": "triptan",
        // Tramadol (its own key; also serotonergic)
        "tramadol": "tramadol", "ultram": "tramadol",
        // Opioids
        "oxycodone": "opioid", "oxycontin": "opioid", "hydrocodone": "opioid",
        "morphine": "opioid", "fentanyl": "opioid", "codeine": "opioid",
        // Benzodiazepines
        "alprazolam": "benzodiazepine", "xanax": "benzodiazepine",
        "lorazepam": "benzodiazepine", "ativan": "benzodiazepine",
        "diazepam": "benzodiazepine", "valium": "benzodiazepine",
        "clonazepam": "benzodiazepine", "klonopin": "benzodiazepine",
        // PPIs
        "omeprazole": "ppi", "prilosec": "ppi",
        "esomeprazole": "ppi", "nexium": "ppi",
        // Cardiac
        "digoxin": "digoxin", "lanoxin": "digoxin",
        "amiodarone": "amiodarone", "pacerone": "amiodarone",
        // PDE5 inhibitors
        "sildenafil": "pde5", "viagra": "pde5",
        "tadalafil": "pde5", "cialis": "pde5",
        // Nitrates
        "nitroglycerin": "nitrate", "isosorbide": "nitrate", "nitrate": "nitrate",
        // Other
        "methotrexate": "methotrexate",
        "lithium": "lithium",
        "metformin": "metformin",
        "levothyroxine": "levothyroxine", "synthroid": "levothyroxine",
        "grapefruit": "grapefruit",
    ]

    // MARK: Interaction table (keyed by sorted class-pair)

    private struct Rule {
        let severity: InteractionSeverity
        let explanation: String
        let recommendation: String
    }

    private static let rules: [String: Rule] = {
        var table: [String: Rule] = [:]
        func add(_ a: String, _ b: String, _ severity: InteractionSeverity, _ explanation: String, _ recommendation: String) {
            table[key(a, b)] = Rule(severity: severity, explanation: explanation, recommendation: recommendation)
        }

        add("warfarin", "nsaid", .major,
            "Combining warfarin with NSAIDs meaningfully increases the risk of serious bleeding, including gastrointestinal bleeding.",
            "Ask your doctor about a safer pain reliever such as acetaminophen.")
        add("warfarin", "aspirin", .major,
            "Warfarin plus aspirin raises the risk of bleeding because both affect clotting.",
            "Only combine under a doctor's supervision.")
        add("warfarin", "clopidogrel", .major,
            "Two blood thinners together substantially increase bleeding risk.",
            "This combination should only be used when a doctor specifically directs it.")
        add("ssri", "maoi", .major,
            "SSRIs/SNRIs with MAOIs can cause serotonin syndrome, a potentially dangerous reaction.",
            "This combination is generally avoided; talk to your prescriber right away.")
        add("ssri", "tramadol", .moderate,
            "Tramadol with an SSRI/SNRI raises the risk of serotonin syndrome and can lower the seizure threshold.",
            "Mention this pairing to your doctor or pharmacist.")
        add("ssri", "triptan", .moderate,
            "Triptans with SSRIs/SNRIs can, uncommonly, contribute to serotonin syndrome.",
            "Usually manageable — review symptoms to watch for with your pharmacist.")
        add("tramadol", "triptan", .moderate,
            "Both increase serotonin activity, which can rarely lead to serotonin syndrome.",
            "Discuss with your pharmacist if used together often.")
        add("ace_inhibitor", "potassium_sparing", .moderate,
            "ACE inhibitors with potassium-sparing diuretics can raise blood potassium to unsafe levels.",
            "Your doctor may want to monitor your potassium and kidney function.")
        add("ace_inhibitor", "potassium", .moderate,
            "ACE inhibitors plus potassium supplements can raise blood potassium.",
            "Have your potassium checked as your doctor advises.")
        add("ace_inhibitor", "arb", .moderate,
            "Combining an ACE inhibitor and an ARB increases the risk of high potassium and kidney strain with little added benefit.",
            "This combination is usually avoided; confirm with your doctor.")
        add("ace_inhibitor", "nsaid", .moderate,
            "NSAIDs can reduce the effect of ACE inhibitors and, together, may strain the kidneys.",
            "Limit NSAID use and discuss alternatives with your doctor.")
        add("statin", "grapefruit", .moderate,
            "Grapefruit can raise levels of some statins (especially simvastatin and atorvastatin), increasing the risk of muscle problems.",
            "Ask your pharmacist whether your specific statin is affected.")
        add("pde5", "nitrate", .major,
            "PDE5 inhibitors (e.g. sildenafil) with nitrates can cause a dangerous drop in blood pressure.",
            "This combination should be avoided — tell any prescriber you take both.")
        add("opioid", "benzodiazepine", .major,
            "Opioids with benzodiazepines can cause profound sedation and dangerous slowing of breathing.",
            "Use together only under close medical supervision.")
        add("digoxin", "amiodarone", .major,
            "Amiodarone can raise digoxin levels and lead to toxicity.",
            "Your doctor may reduce your digoxin dose and monitor levels.")
        add("methotrexate", "nsaid", .major,
            "NSAIDs can raise methotrexate levels and increase toxicity, especially at higher methotrexate doses.",
            "Confirm any pain reliever with the doctor managing your methotrexate.")
        add("lithium", "nsaid", .moderate,
            "NSAIDs can raise lithium levels and increase the risk of lithium toxicity.",
            "Prefer acetaminophen and have lithium levels monitored.")
        add("clopidogrel", "ppi", .moderate,
            "Some PPIs (especially omeprazole) can reduce clopidogrel's anti-clotting effect.",
            "Ask your pharmacist about a PPI that interacts less, if one is needed.")
        add("aspirin", "nsaid", .moderate,
            "Taking aspirin with other NSAIDs increases stomach and bleeding risk and may blunt aspirin's heart benefit.",
            "Space doses or ask your pharmacist about the safest option.")
        add("statin", "amiodarone", .moderate,
            "Amiodarone can raise levels of some statins, increasing the risk of muscle injury.",
            "Your doctor may cap the statin dose; report muscle pain.")

        return table
    }()

    private static func key(_ a: String, _ b: String) -> String {
        a <= b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    // MARK: Normalization

    /// Longest matching synonym token contained in the name → class key.
    private static func classKey(for name: String) -> String? {
        let lower = name.lowercased()
        var best: (token: String, key: String)?
        for (token, key) in synonyms where lower.contains(token) {
            if best == nil || token.count > best!.token.count {
                best = (token, key)
            }
        }
        return best?.key
    }

    // MARK: Public check

    static func check(medicationNames: [String]) -> [DrugInteraction] {
        // Resolve each medication to a class, keeping the original display name.
        let resolved: [(name: String, key: String)] = medicationNames.compactMap { name in
            guard let key = classKey(for: name) else { return nil }
            return (name, key)
        }

        var results: [DrugInteraction] = []
        var seenPairs: Set<String> = []

        for i in 0..<resolved.count {
            for j in (i + 1)..<resolved.count {
                let a = resolved[i]
                let b = resolved[j]
                guard a.key != b.key else { continue }
                let pairKey = key(a.key, b.key)
                guard !seenPairs.contains(pairKey), let rule = rules[pairKey] else { continue }
                seenPairs.insert(pairKey)
                results.append(DrugInteraction(
                    drugA: a.name,
                    drugB: b.name,
                    severity: rule.severity,
                    explanation: rule.explanation,
                    recommendation: rule.recommendation
                ))
            }
        }

        return results.sorted { $0.severity > $1.severity }
    }
}
