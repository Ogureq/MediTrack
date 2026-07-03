//
//  LabCatalog.swift
//  MediTrack
//
//  A static catalog of common laboratory tests with typical adult reference
//  intervals, plain-language explanations, and helper lookups.
//
//  IMPORTANT: The ranges below are TYPICAL adult reference intervals expressed
//  in conventional US units. Reference ranges vary between laboratories,
//  populations, ages, and testing methods; always interpret results against the
//  range printed on your own lab report. This catalog is for general education
//  only and is NOT medical advice, a diagnosis, or a substitute for care from a
//  qualified clinician.
//

import Foundation

// MARK: - Biological Sex

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female, unspecified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .unspecified: return "Unspecified"
        }
    }
}

// MARK: - Lab Category

enum LabCategory: String, Codable, CaseIterable, Identifiable {
    case hematology, lipidPanel, metabolic, liver, kidney, thyroid, vitaminsMinerals, inflammation, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hematology: return "Blood Count (CBC)"
        case .lipidPanel: return "Lipid Panel"
        case .metabolic: return "Metabolic"
        case .liver: return "Liver Function"
        case .kidney: return "Kidney Function"
        case .thyroid: return "Thyroid"
        case .vitaminsMinerals: return "Vitamins & Minerals"
        case .inflammation: return "Inflammation"
        case .other: return "Other"
        }
    }

    /// A real SF Symbol name representing the category.
    var systemImage: String {
        switch self {
        case .hematology: return "drop.fill"
        case .lipidPanel: return "heart.fill"
        case .metabolic: return "bolt.fill"
        case .liver: return "cross.case.fill"
        case .kidney: return "drop.triangle.fill"
        case .thyroid: return "waveform.path.ecg"
        case .vitaminsMinerals: return "pills.fill"
        case .inflammation: return "flame.fill"
        case .other: return "staroflife"
        }
    }
}

// MARK: - Lab Reference

struct LabReference: Identifiable, Hashable {
    let id: String              // stable key, lowerCamelCase, e.g. "hemoglobin"
    let name: String            // "Hemoglobin"
    let shortName: String       // "Hgb"
    let unit: String            // "g/dL"
    let category: LabCategory
    let maleRange: ClosedRange<Double>?    // sex-specific range, nil if not sex-specific
    let femaleRange: ClosedRange<Double>?
    let commonRange: ClosedRange<Double>?  // used when not sex-specific (nil if sex-specific ranges given)
    let criticalLow: Double?    // value below which it is a critical/urgent flag (nil if N/A)
    let criticalHigh: Double?   // value above which it is critical (nil if N/A)
    let lowMeaning: String      // plain-language meaning of a LOW value
    let highMeaning: String     // plain-language meaning of a HIGH value
    let about: String           // what this test measures

    /// Resolved reference range for the given sex. Falls back to `commonRange`,
    /// and finally to the widest span across the sex-specific ranges.
    func referenceRange(for sex: BiologicalSex?) -> ClosedRange<Double>? {
        // Sex-specific ranges take priority when present.
        if maleRange != nil || femaleRange != nil {
            switch sex {
            case .male:
                return maleRange ?? commonRange ?? femaleRange
            case .female:
                return femaleRange ?? commonRange ?? maleRange
            case .unspecified, nil:
                if let common = commonRange {
                    return common
                }
                if let m = maleRange, let f = femaleRange {
                    let lower = Swift.min(m.lowerBound, f.lowerBound)
                    let upper = Swift.max(m.upperBound, f.upperBound)
                    return lower...upper
                }
                return maleRange ?? femaleRange
            }
        }
        return commonRange
    }
}

// MARK: - Lab Catalog

enum LabCatalog {

    /// All tests, grouped logically, in a stable display order.
    static let tests: [LabReference] = [

        // MARK: Hematology (CBC)

        LabReference(
            id: "hemoglobin",
            name: "Hemoglobin",
            shortName: "Hgb",
            unit: "g/dL",
            category: .hematology,
            maleRange: 13.5...17.5,
            femaleRange: 12.0...15.5,
            commonRange: nil,
            criticalLow: 7.0,
            criticalHigh: nil,
            lowMeaning: "A low value can accompany anemia, recent blood loss, low iron, or pregnancy. Fatigue or shortness of breath alongside a low value is worth discussing with a clinician.",
            highMeaning: "A high value may reflect dehydration, living at high altitude, or smoking. Persistently high values are worth reviewing with a clinician.",
            about: "Hemoglobin is the protein in red blood cells that carries oxygen from the lungs to the rest of the body."
        ),
        LabReference(
            id: "hematocrit",
            name: "Hematocrit",
            shortName: "Hct",
            unit: "%",
            category: .hematology,
            maleRange: 38.8...50.0,
            femaleRange: 34.9...44.5,
            commonRange: nil,
            criticalLow: 20.0,
            criticalHigh: 60.0,
            lowMeaning: "A low value often mirrors anemia, blood loss, or overhydration. Consider discussing with a clinician if it persists or comes with fatigue.",
            highMeaning: "A high value is commonly caused by dehydration; it can also occur at high altitude. Persistent elevation is worth a clinician's review.",
            about: "Hematocrit is the percentage of your blood volume made up of red blood cells."
        ),
        LabReference(
            id: "redBloodCells",
            name: "Red Blood Cell Count",
            shortName: "RBC",
            unit: "million/µL",
            category: .hematology,
            maleRange: 4.7...6.1,
            femaleRange: 4.2...5.4,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low count can accompany anemia, blood loss, or nutritional shortfalls such as low iron, B12, or folate. Discuss with a clinician if it persists.",
            highMeaning: "A high count may reflect dehydration, smoking, or high-altitude living. Persistent elevation is worth reviewing with a clinician.",
            about: "This measures the number of red blood cells, which carry oxygen throughout the body."
        ),
        LabReference(
            id: "whiteBloodCells",
            name: "White Blood Cell Count",
            shortName: "WBC",
            unit: "thousand/µL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 4.5...11.0,
            criticalLow: 2.0,
            criticalHigh: 30.0,
            lowMeaning: "A low count can follow some viral infections, certain medications, or immune conditions. A very low count or frequent infections should be discussed with a clinician.",
            highMeaning: "A high count often reflects the body responding to infection, inflammation, stress, or recent exercise. Persistent or very high values warrant a clinician's review.",
            about: "White blood cells are part of the immune system and help the body fight infection."
        ),
        LabReference(
            id: "platelets",
            name: "Platelet Count",
            shortName: "PLT",
            unit: "thousand/µL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 150...450,
            criticalLow: 50.0,
            criticalHigh: 1000.0,
            lowMeaning: "A low count can be linked to certain infections, medications, or immune conditions and may increase bruising or bleeding. Discuss notably low values with a clinician.",
            highMeaning: "A high count can occur temporarily after infection, inflammation, or iron deficiency. Persistent elevation is worth reviewing with a clinician.",
            about: "Platelets are small cell fragments that help blood clot and stop bleeding."
        ),
        LabReference(
            id: "mcv",
            name: "Mean Corpuscular Volume",
            shortName: "MCV",
            unit: "fL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 80...100,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "Smaller-than-average red cells (low MCV) are commonly associated with iron deficiency or certain inherited traits. Discuss with a clinician if paired with anemia.",
            highMeaning: "Larger-than-average red cells (high MCV) can relate to low B12 or folate, some medications, or alcohol use. Consider reviewing with a clinician.",
            about: "MCV describes the average size of your red blood cells and helps classify anemias."
        ),
        LabReference(
            id: "mch",
            name: "Mean Corpuscular Hemoglobin",
            shortName: "MCH",
            unit: "pg",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 27...33,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value means each red cell carries less hemoglobin on average, often alongside iron deficiency. Discuss with a clinician if anemia is also present.",
            highMeaning: "A high value can accompany larger red cells, such as with low B12 or folate. Consider reviewing with a clinician if it persists.",
            about: "MCH is the average amount of hemoglobin contained in a single red blood cell."
        ),
        LabReference(
            id: "mchc",
            name: "Mean Corpuscular Hemoglobin Concentration",
            shortName: "MCHC",
            unit: "g/dL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 32...36,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can be seen with iron deficiency. It is usually interpreted together with other red-cell indices; discuss persistent findings with a clinician.",
            highMeaning: "A high value is less common and can occasionally reflect certain red-cell conditions or a lab artifact. Consider reviewing with a clinician.",
            about: "MCHC is the concentration of hemoglobin within a given volume of red blood cells."
        ),
        LabReference(
            id: "rdw",
            name: "Red Cell Distribution Width",
            shortName: "RDW",
            unit: "%",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 11.5...14.5,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern and simply indicates red cells that are uniform in size.",
            highMeaning: "A high value means red cells vary more in size, which can be an early sign of iron, B12, or folate shortfalls. Consider reviewing with a clinician.",
            about: "RDW measures how much red blood cells vary in size, which helps evaluate anemia."
        ),
        LabReference(
            id: "neutrophilsPercent",
            name: "Neutrophils",
            shortName: "Neut %",
            unit: "%",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 40...60,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low percentage can follow some viral infections or certain medications. Discuss persistently low values with a clinician, especially with frequent infections.",
            highMeaning: "A high percentage commonly reflects the body responding to bacterial infection, inflammation, or physical stress. Consider reviewing persistent elevation with a clinician.",
            about: "Neutrophils are the most common white blood cell and are a first responder to infection."
        ),
        LabReference(
            id: "lymphocytesPercent",
            name: "Lymphocytes",
            shortName: "Lymph %",
            unit: "%",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 20...40,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low percentage can occur with acute stress, certain infections, or medications. Discuss persistent values with a clinician.",
            highMeaning: "A high percentage is often seen with viral infections and usually resolves as you recover. Consider reviewing persistent elevation with a clinician.",
            about: "Lymphocytes are white blood cells central to the immune response, including against viruses."
        ),

        // MARK: Lipid Panel

        LabReference(
            id: "totalCholesterol",
            name: "Total Cholesterol",
            shortName: "TC",
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...199,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern on its own and is usually considered favorable for heart health.",
            highMeaning: "A high value may relate to diet, activity level, genetics, or other conditions and can raise cardiovascular risk over time. Discuss elevated results with a clinician.",
            about: "Total cholesterol sums the cholesterol carried by all lipoprotein particles in your blood."
        ),
        LabReference(
            id: "ldlCholesterol",
            name: "LDL Cholesterol",
            shortName: "LDL",
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...99,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally desirable and associated with lower cardiovascular risk.",
            highMeaning: "A high value can build up in artery walls and raise cardiovascular risk over time. Diet, activity, genetics, and other factors contribute; discuss elevated results with a clinician.",
            about: "LDL, sometimes called \"bad\" cholesterol, can contribute to plaque buildup in arteries."
        ),
        LabReference(
            id: "hdlCholesterol",
            name: "HDL Cholesterol",
            shortName: "HDL",
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: 40...100,
            femaleRange: 50...100,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value offers less protective benefit and is linked to higher cardiovascular risk. Regular activity and other habits can help; discuss with a clinician.",
            highMeaning: "A higher value is generally considered protective for heart health.",
            about: "HDL, sometimes called \"good\" cholesterol, helps remove other cholesterol from the bloodstream."
        ),
        LabReference(
            id: "triglycerides",
            name: "Triglycerides",
            shortName: "TG",
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...149,
            criticalLow: nil,
            criticalHigh: 500.0,
            lowMeaning: "A low value is generally desirable.",
            highMeaning: "A high value can relate to diet, alcohol, excess weight, uncontrolled blood sugar, or a recent non-fasting sample. Very high values warrant prompt discussion with a clinician.",
            about: "Triglycerides are a type of fat in the blood used and stored for energy."
        ),

        // MARK: Metabolic

        LabReference(
            id: "fastingGlucose",
            name: "Fasting Glucose",
            shortName: "Glu",
            unit: "mg/dL",
            category: .metabolic,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 70...99,
            criticalLow: 54.0,
            criticalHigh: 250.0,
            lowMeaning: "A low value can follow prolonged fasting, intense exercise, or certain medications, and may cause shakiness or lightheadedness. Frequent low readings deserve a clinician's attention.",
            highMeaning: "A high value can reflect a non-fasting sample, stress, or elevated blood sugar. Repeated high values should be reviewed with a clinician.",
            about: "Fasting glucose measures blood sugar after not eating, typically for at least 8 hours."
        ),
        LabReference(
            id: "hba1c",
            name: "Hemoglobin A1c",
            shortName: "HbA1c",
            unit: "%",
            category: .metabolic,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 4.0...5.6,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is uncommon and can occasionally relate to anemia or shortened red-cell lifespan. Discuss unusual results with a clinician.",
            highMeaning: "A higher value reflects higher average blood sugar over recent months. Discuss elevated results with a clinician to understand next steps.",
            about: "HbA1c estimates your average blood sugar over the past two to three months."
        ),
        LabReference(
            id: "insulin",
            name: "Fasting Insulin",
            shortName: "Insulin",
            unit: "µIU/mL",
            category: .metabolic,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.6...24.9,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can simply reflect fasting. Interpretation depends on your blood sugar at the same time; discuss with a clinician if you have questions.",
            highMeaning: "A high value can accompany insulin resistance and is often linked to excess weight or inactivity. Consider reviewing elevated results with a clinician.",
            about: "Insulin is the hormone that helps move sugar from the blood into cells for energy."
        ),

        // MARK: Kidney & Electrolytes

        LabReference(
            id: "sodium",
            name: "Sodium",
            shortName: "Na",
            unit: "mEq/L",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 135...145,
            criticalLow: 125.0,
            criticalHigh: 155.0,
            lowMeaning: "A low value can follow excess fluid intake, certain medications, or fluid loss. Marked or symptomatic changes should be evaluated promptly by a clinician.",
            highMeaning: "A high value most often reflects dehydration or insufficient water intake. Persistent or marked elevation warrants a clinician's review.",
            about: "Sodium is an electrolyte that helps regulate fluid balance and nerve and muscle function."
        ),
        LabReference(
            id: "potassium",
            name: "Potassium",
            shortName: "K",
            unit: "mEq/L",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 3.5...5.1,
            criticalLow: 2.8,
            criticalHigh: 6.2,
            lowMeaning: "A low value can result from fluid loss, certain diuretics, or vomiting and may affect muscles and heart rhythm. Notable lows should be discussed promptly with a clinician.",
            highMeaning: "A high value can relate to kidney function, medications, or a sample handling artifact. Genuine elevation should be reviewed promptly by a clinician.",
            about: "Potassium is an electrolyte essential for nerve signals, muscle function, and heart rhythm."
        ),
        LabReference(
            id: "chloride",
            name: "Chloride",
            shortName: "Cl",
            unit: "mEq/L",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 98...107,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can accompany vomiting, certain medications, or fluid shifts. It is usually interpreted alongside other electrolytes; discuss with a clinician if it persists.",
            highMeaning: "A high value can relate to dehydration or acid-base balance. It is typically reviewed with other electrolytes; consider discussing persistent values with a clinician.",
            about: "Chloride is an electrolyte that works with sodium to maintain fluid and acid-base balance."
        ),
        LabReference(
            id: "calcium",
            name: "Calcium",
            shortName: "Ca",
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 8.6...10.3,
            criticalLow: 6.0,
            criticalHigh: 13.0,
            lowMeaning: "A low value can relate to low vitamin D, low albumin, or parathyroid or kidney factors. Discuss notable or symptomatic lows with a clinician.",
            highMeaning: "A high value can involve parathyroid activity, certain medications, or dehydration. Persistent elevation should be reviewed with a clinician.",
            about: "Calcium supports bones, nerve signaling, muscle function, and blood clotting."
        ),
        LabReference(
            id: "magnesium",
            name: "Magnesium",
            shortName: "Mg",
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 1.7...2.2,
            criticalLow: 1.0,
            criticalHigh: nil,
            lowMeaning: "A low value can follow poor intake, alcohol use, certain medications, or digestive losses and may cause cramps. Discuss notable lows with a clinician.",
            highMeaning: "A high value is uncommon and is most often related to kidney function or magnesium-containing supplements. Consider reviewing with a clinician.",
            about: "Magnesium is a mineral involved in hundreds of processes, including muscle and nerve function."
        ),
        LabReference(
            id: "phosphorus",
            name: "Phosphorus",
            shortName: "Phos",
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.5...4.5,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can relate to nutrition, certain medications, or vitamin D status. Discuss persistent lows with a clinician.",
            highMeaning: "A high value is often linked to kidney function. It is usually reviewed alongside calcium; consider discussing persistent elevation with a clinician.",
            about: "Phosphorus works with calcium to build bones and support energy metabolism."
        ),
        LabReference(
            id: "creatinine",
            name: "Creatinine",
            shortName: "Cr",
            unit: "mg/dL",
            category: .kidney,
            maleRange: 0.74...1.35,
            femaleRange: 0.59...1.04,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can reflect lower muscle mass and is usually not a concern on its own.",
            highMeaning: "A high value can relate to reduced kidney filtering, dehydration, high muscle mass, or a recent high-protein meal. Discuss persistent elevation with a clinician.",
            about: "Creatinine is a waste product from muscle activity that the kidneys filter out."
        ),
        LabReference(
            id: "bun",
            name: "Blood Urea Nitrogen",
            shortName: "BUN",
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 7...20,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can accompany a low-protein diet, overhydration, or liver factors and is usually not concerning on its own.",
            highMeaning: "A high value can relate to dehydration, a high-protein diet, or kidney function. It is usually interpreted with creatinine; discuss persistent elevation with a clinician.",
            about: "BUN measures the amount of nitrogen from urea, a waste product the kidneys remove."
        ),
        LabReference(
            id: "egfr",
            name: "Estimated GFR",
            shortName: "eGFR",
            unit: "mL/min/1.73m²",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 60...120,
            criticalLow: 15.0,
            criticalHigh: nil,
            lowMeaning: "A lower value suggests the kidneys are filtering more slowly, which can occur with age, dehydration, or kidney conditions. Discuss persistently low results with a clinician.",
            highMeaning: "A higher value generally indicates strong kidney filtering and is not a concern.",
            about: "eGFR estimates how well your kidneys filter waste, calculated from creatinine and other factors."
        ),
        LabReference(
            id: "uricAcid",
            name: "Uric Acid",
            shortName: "UA",
            unit: "mg/dL",
            category: .kidney,
            maleRange: 3.4...7.0,
            femaleRange: 2.4...6.0,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is usually not a concern and can relate to certain medications or diet.",
            highMeaning: "A high value can be influenced by diet, alcohol, dehydration, or genetics and is associated with gout. Discuss persistent elevation, especially with joint pain, with a clinician.",
            about: "Uric acid is a waste product from the breakdown of purines found in some foods and body cells."
        ),

        // MARK: Liver Function

        LabReference(
            id: "alt",
            name: "Alanine Aminotransferase",
            shortName: "ALT",
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 7...56,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern.",
            highMeaning: "A high value can follow alcohol, certain medications, fatty liver, recent intense exercise, or infection. Discuss persistent elevation with a clinician.",
            about: "ALT is an enzyme found mainly in the liver; levels rise when liver cells are stressed."
        ),
        LabReference(
            id: "ast",
            name: "Aspartate Aminotransferase",
            shortName: "AST",
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 10...40,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern.",
            highMeaning: "A high value can relate to the liver but also to muscle activity, since AST is found in muscle too. Recent exercise, medications, or alcohol may contribute; discuss persistent elevation with a clinician.",
            about: "AST is an enzyme found in the liver and muscles; it is used alongside ALT to assess the liver."
        ),
        LabReference(
            id: "alp",
            name: "Alkaline Phosphatase",
            shortName: "ALP",
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 44...147,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is uncommon and can occasionally relate to nutrition or certain conditions. Discuss unusual results with a clinician.",
            highMeaning: "A high value can involve the liver, bile ducts, or bone, and is normal during growth or pregnancy. Discuss persistent elevation with a clinician.",
            about: "ALP is an enzyme found in the liver, bile ducts, and bone."
        ),
        LabReference(
            id: "ggt",
            name: "Gamma-Glutamyl Transferase",
            shortName: "GGT",
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 8...61,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern.",
            highMeaning: "A high value can relate to alcohol use, certain medications, or bile-duct issues. It helps clarify the source of a raised ALP; discuss persistent elevation with a clinician.",
            about: "GGT is a liver enzyme that helps pinpoint whether raised liver values stem from the bile ducts."
        ),
        LabReference(
            id: "totalBilirubin",
            name: "Total Bilirubin",
            shortName: "T. Bili",
            unit: "mg/dL",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0.1...1.2,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern.",
            highMeaning: "A high value can cause yellowing of the skin or eyes and may relate to the liver, bile flow, red-cell breakdown, or a benign inherited pattern (Gilbert syndrome). Discuss elevation with a clinician.",
            about: "Bilirubin is a yellow pigment made when red blood cells break down and is processed by the liver."
        ),
        LabReference(
            id: "albumin",
            name: "Albumin",
            shortName: "Alb",
            unit: "g/dL",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 3.5...5.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can relate to nutrition, inflammation, or liver or kidney factors. Discuss persistent lows with a clinician.",
            highMeaning: "A high value is most often caused by dehydration. Rehydrating usually resolves it; discuss persistent elevation with a clinician.",
            about: "Albumin is a protein made by the liver that helps keep fluid in blood vessels and carries substances."
        ),
        LabReference(
            id: "totalProtein",
            name: "Total Protein",
            shortName: "TP",
            unit: "g/dL",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 6.0...8.3,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can relate to nutrition, or liver or kidney factors. Discuss persistent lows with a clinician.",
            highMeaning: "A high value can reflect dehydration or ongoing inflammation. Consider reviewing persistent elevation with a clinician.",
            about: "Total protein measures albumin and globulins together, reflecting overall protein in the blood."
        ),

        // MARK: Thyroid

        LabReference(
            id: "tsh",
            name: "Thyroid-Stimulating Hormone",
            shortName: "TSH",
            unit: "mIU/L",
            category: .thyroid,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0.4...4.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can suggest an overactive thyroid, since the body signals less. Certain medications also affect it; discuss with a clinician, often with free T4.",
            highMeaning: "A high value can suggest an underactive thyroid, as the body signals harder for hormone. Discuss elevated results with a clinician, usually alongside free T4.",
            about: "TSH is a pituitary hormone that signals the thyroid; it is the primary screen for thyroid function."
        ),
        LabReference(
            id: "freeT4",
            name: "Free Thyroxine",
            shortName: "FT4",
            unit: "ng/dL",
            category: .thyroid,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0.8...1.8,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can accompany an underactive thyroid and is interpreted together with TSH. Discuss with a clinician.",
            highMeaning: "A high value can accompany an overactive thyroid and is interpreted together with TSH. Discuss with a clinician.",
            about: "Free T4 is the active, unbound form of the main thyroid hormone circulating in the blood."
        ),
        LabReference(
            id: "freeT3",
            name: "Free Triiodothyronine",
            shortName: "FT3",
            unit: "pg/mL",
            category: .thyroid,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.3...4.2,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can occur with an underactive thyroid or during other illness. It is interpreted with TSH and free T4; discuss with a clinician.",
            highMeaning: "A high value can occur with an overactive thyroid. It is interpreted alongside TSH and free T4; discuss with a clinician.",
            about: "Free T3 is the active form of the more potent thyroid hormone and helps assess thyroid function."
        ),

        // MARK: Vitamins & Minerals

        LabReference(
            id: "vitaminD",
            name: "Vitamin D, 25-Hydroxy",
            shortName: "Vit D",
            unit: "ng/mL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 30...100,
            criticalLow: 10.0,
            criticalHigh: nil,
            lowMeaning: "A low value is common, especially with limited sun exposure, and can affect bone health. Diet, sunlight, or supplements may help; discuss with a clinician.",
            highMeaning: "A high value usually results from taking high-dose supplements. Very high values can affect calcium; review supplement use with a clinician.",
            about: "This measures your body's vitamin D stores, important for bone health and calcium absorption."
        ),
        LabReference(
            id: "vitaminB12",
            name: "Vitamin B12",
            shortName: "B12",
            unit: "pg/mL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 200...900,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can relate to diet (such as a plant-based diet), absorption, or certain medications, and may affect energy and nerves. Discuss persistent lows with a clinician.",
            highMeaning: "A high value often reflects supplement intake and is usually not concerning. Consider reviewing unexplained elevation with a clinician.",
            about: "Vitamin B12 supports nerve function and the formation of red blood cells."
        ),
        LabReference(
            id: "folate",
            name: "Folate",
            shortName: "Folate",
            unit: "ng/mL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.7...17.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can relate to diet or absorption and may affect red-cell formation. Folate-rich foods or supplements may help; discuss with a clinician.",
            highMeaning: "A high value is usually harmless and often reflects supplements or fortified foods.",
            about: "Folate (vitamin B9) is needed to make DNA and red blood cells and is important in pregnancy."
        ),
        LabReference(
            id: "ferritin",
            name: "Ferritin",
            shortName: "Ferritin",
            unit: "ng/mL",
            category: .vitaminsMinerals,
            maleRange: 24...336,
            femaleRange: 11...307,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is a sensitive sign of low iron stores and can accompany fatigue. Diet or iron supplements may help; discuss with a clinician.",
            highMeaning: "A high value can reflect iron overload but also rises with inflammation or infection. Discuss persistent elevation with a clinician.",
            about: "Ferritin reflects the amount of iron your body has in storage."
        ),
        LabReference(
            id: "iron",
            name: "Serum Iron",
            shortName: "Iron",
            unit: "µg/dL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 60...170,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can accompany iron deficiency or blood loss and varies through the day. It is interpreted with ferritin and TIBC; discuss with a clinician.",
            highMeaning: "A high value can follow iron supplements, a recent iron-rich meal, or iron overload. Consider reviewing persistent elevation with a clinician.",
            about: "Serum iron measures the amount of iron circulating in the blood at the time of the test."
        ),
        LabReference(
            id: "tibc",
            name: "Total Iron-Binding Capacity",
            shortName: "TIBC",
            unit: "µg/dL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 250...450,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value can be seen with inflammation or iron overload. It is interpreted with iron and ferritin; discuss with a clinician if needed.",
            highMeaning: "A high value often accompanies iron deficiency, as the blood has more capacity to carry iron. Discuss with a clinician alongside iron and ferritin.",
            about: "TIBC measures the blood's total capacity to bind and transport iron, reflecting iron status."
        ),

        // MARK: Inflammation

        LabReference(
            id: "crp",
            name: "C-Reactive Protein",
            shortName: "CRP",
            unit: "mg/L",
            category: .inflammation,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...3.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally desirable and suggests little active inflammation.",
            highMeaning: "A high value signals inflammation, which can follow infection, injury, or a chronic condition, and rises temporarily with minor illness. Discuss persistent elevation with a clinician.",
            about: "CRP is a protein made by the liver that rises when there is inflammation in the body."
        ),
        LabReference(
            id: "esr",
            name: "Erythrocyte Sedimentation Rate",
            shortName: "ESR",
            unit: "mm/hr",
            category: .inflammation,
            maleRange: 0...15,
            femaleRange: 0...20,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: "A low value is generally not a concern.",
            highMeaning: "A high value is a nonspecific sign of inflammation and can rise with infection, age, anemia, or pregnancy. Discuss persistent elevation with a clinician.",
            about: "ESR measures how quickly red blood cells settle, an indirect and general marker of inflammation."
        )
    ]

    /// Fast lookup index keyed by lowercased id, built once.
    private static let index: [String: LabReference] = {
        var dict = [String: LabReference](minimumCapacity: tests.count)
        for test in tests {
            dict[test.id.lowercased()] = test
        }
        return dict
    }()

    /// Lookup by `LabReference.id`. Case-insensitive.
    static func reference(for id: String) -> LabReference? {
        index[id.lowercased()]
    }

    /// Case-insensitive substring search over name, shortName, and id.
    static func search(_ query: String) -> [LabReference] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tests }
        return tests.filter { test in
            test.name.lowercased().contains(q)
                || test.shortName.lowercased().contains(q)
                || test.id.lowercased().contains(q)
        }
    }

    /// All tests in the given category, preserving catalog order.
    static func tests(in category: LabCategory) -> [LabReference] {
        tests.filter { $0.category == category }
    }
}
