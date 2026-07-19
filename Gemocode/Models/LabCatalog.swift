//
//  LabCatalog.swift
//  Gemocode
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
        case .male: return String(localized: "biologicalSex.male", defaultValue: "Male", table: "Engine")
        case .female: return String(localized: "biologicalSex.female", defaultValue: "Female", table: "Engine")
        case .unspecified: return String(localized: "biologicalSex.unspecified", defaultValue: "Unspecified", table: "Engine")
        }
    }
}

// MARK: - Lab Category

enum LabCategory: String, Codable, CaseIterable, Identifiable {
    case hematology, lipidPanel, metabolic, liver, kidney, thyroid, vitaminsMinerals, inflammation, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hematology: return String(localized: "labCategory.hematology", defaultValue: "Blood Count (CBC)", table: "Engine")
        case .lipidPanel: return String(localized: "labCategory.lipidPanel", defaultValue: "Lipid Panel", table: "Engine")
        case .metabolic: return String(localized: "labCategory.metabolic", defaultValue: "Metabolic", table: "Engine")
        case .liver: return String(localized: "labCategory.liver", defaultValue: "Liver Function", table: "Engine")
        case .kidney: return String(localized: "labCategory.kidney", defaultValue: "Kidney Function", table: "Engine")
        case .thyroid: return String(localized: "labCategory.thyroid", defaultValue: "Thyroid", table: "Engine")
        case .vitaminsMinerals: return String(localized: "labCategory.vitaminsMinerals", defaultValue: "Vitamins & Minerals", table: "Engine")
        case .inflammation: return String(localized: "labCategory.inflammation", defaultValue: "Inflammation", table: "Engine")
        case .other: return String(localized: "labCategory.other", defaultValue: "Other", table: "Engine")
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
            name: String(localized: "lab.hemoglobin.name", defaultValue: "Hemoglobin", table: "Engine"),
            shortName: String(localized: "lab.hemoglobin.shortName", defaultValue: "Hgb", table: "Engine"),
            unit: "g/dL",
            category: .hematology,
            maleRange: 13.5...17.5,
            femaleRange: 12.0...15.5,
            commonRange: nil,
            criticalLow: 7.0,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.hemoglobin.lowMeaning", defaultValue: "A low value can accompany anemia, recent blood loss, low iron, or pregnancy. Fatigue or shortness of breath alongside a low value is worth discussing with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.hemoglobin.highMeaning", defaultValue: "A high value may reflect dehydration, living at high altitude, or smoking. Persistently high values are worth reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.hemoglobin.about", defaultValue: "Hemoglobin is the protein in red blood cells that carries oxygen from the lungs to the rest of the body.", table: "Engine")
        ),
        LabReference(
            id: "hematocrit",
            name: String(localized: "lab.hematocrit.name", defaultValue: "Hematocrit", table: "Engine"),
            shortName: String(localized: "lab.hematocrit.shortName", defaultValue: "Hct", table: "Engine"),
            unit: "%",
            category: .hematology,
            maleRange: 38.8...50.0,
            femaleRange: 34.9...44.5,
            commonRange: nil,
            criticalLow: 20.0,
            criticalHigh: 60.0,
            lowMeaning: String(localized: "lab.hematocrit.lowMeaning", defaultValue: "A low value often mirrors anemia, blood loss, or overhydration. Consider discussing with a clinician if it persists or comes with fatigue.", table: "Engine"),
            highMeaning: String(localized: "lab.hematocrit.highMeaning", defaultValue: "A high value is commonly caused by dehydration; it can also occur at high altitude. Persistent elevation is worth a clinician's review.", table: "Engine"),
            about: String(localized: "lab.hematocrit.about", defaultValue: "Hematocrit is the percentage of your blood volume made up of red blood cells.", table: "Engine")
        ),
        LabReference(
            id: "redBloodCells",
            name: String(localized: "lab.redBloodCells.name", defaultValue: "Red Blood Cell Count", table: "Engine"),
            shortName: String(localized: "lab.redBloodCells.shortName", defaultValue: "RBC", table: "Engine"),
            unit: "million/µL",
            category: .hematology,
            maleRange: 4.7...6.1,
            femaleRange: 4.2...5.4,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.redBloodCells.lowMeaning", defaultValue: "A low count can accompany anemia, blood loss, or nutritional shortfalls such as low iron, B12, or folate. Discuss with a clinician if it persists.", table: "Engine"),
            highMeaning: String(localized: "lab.redBloodCells.highMeaning", defaultValue: "A high count may reflect dehydration, smoking, or high-altitude living. Persistent elevation is worth reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.redBloodCells.about", defaultValue: "This measures the number of red blood cells, which carry oxygen throughout the body.", table: "Engine")
        ),
        LabReference(
            id: "whiteBloodCells",
            name: String(localized: "lab.whiteBloodCells.name", defaultValue: "White Blood Cell Count", table: "Engine"),
            shortName: String(localized: "lab.whiteBloodCells.shortName", defaultValue: "WBC", table: "Engine"),
            unit: "thousand/µL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 4.5...11.0,
            criticalLow: 2.0,
            criticalHigh: 30.0,
            lowMeaning: String(localized: "lab.whiteBloodCells.lowMeaning", defaultValue: "A low count can follow some viral infections, certain medications, or immune conditions. A very low count or frequent infections should be discussed with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.whiteBloodCells.highMeaning", defaultValue: "A high count often reflects the body responding to infection, inflammation, stress, or recent exercise. Persistent or very high values warrant a clinician's review.", table: "Engine"),
            about: String(localized: "lab.whiteBloodCells.about", defaultValue: "White blood cells are part of the immune system and help the body fight infection.", table: "Engine")
        ),
        LabReference(
            id: "platelets",
            name: String(localized: "lab.platelets.name", defaultValue: "Platelet Count", table: "Engine"),
            shortName: String(localized: "lab.platelets.shortName", defaultValue: "PLT", table: "Engine"),
            unit: "thousand/µL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 150...450,
            criticalLow: 50.0,
            criticalHigh: 1000.0,
            lowMeaning: String(localized: "lab.platelets.lowMeaning", defaultValue: "A low count can be linked to certain infections, medications, or immune conditions and may increase bruising or bleeding. Discuss notably low values with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.platelets.highMeaning", defaultValue: "A high count can occur temporarily after infection, inflammation, or iron deficiency. Persistent elevation is worth reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.platelets.about", defaultValue: "Platelets are small cell fragments that help blood clot and stop bleeding.", table: "Engine")
        ),
        LabReference(
            id: "mcv",
            name: String(localized: "lab.mcv.name", defaultValue: "Mean Corpuscular Volume", table: "Engine"),
            shortName: String(localized: "lab.mcv.shortName", defaultValue: "MCV", table: "Engine"),
            unit: "fL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 80...100,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.mcv.lowMeaning", defaultValue: "Smaller-than-average red cells (low MCV) are commonly associated with iron deficiency or certain inherited traits. Discuss with a clinician if paired with anemia.", table: "Engine"),
            highMeaning: String(localized: "lab.mcv.highMeaning", defaultValue: "Larger-than-average red cells (high MCV) can relate to low B12 or folate, some medications, or alcohol use. Consider reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.mcv.about", defaultValue: "MCV describes the average size of your red blood cells and helps classify anemias.", table: "Engine")
        ),
        LabReference(
            id: "mch",
            name: String(localized: "lab.mch.name", defaultValue: "Mean Corpuscular Hemoglobin", table: "Engine"),
            shortName: String(localized: "lab.mch.shortName", defaultValue: "MCH", table: "Engine"),
            unit: "pg",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 27...33,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.mch.lowMeaning", defaultValue: "A low value means each red cell carries less hemoglobin on average, often alongside iron deficiency. Discuss with a clinician if anemia is also present.", table: "Engine"),
            highMeaning: String(localized: "lab.mch.highMeaning", defaultValue: "A high value can accompany larger red cells, such as with low B12 or folate. Consider reviewing with a clinician if it persists.", table: "Engine"),
            about: String(localized: "lab.mch.about", defaultValue: "MCH is the average amount of hemoglobin contained in a single red blood cell.", table: "Engine")
        ),
        LabReference(
            id: "mchc",
            name: String(localized: "lab.mchc.name", defaultValue: "Mean Corpuscular Hemoglobin Concentration", table: "Engine"),
            shortName: String(localized: "lab.mchc.shortName", defaultValue: "MCHC", table: "Engine"),
            unit: "g/dL",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 32...36,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.mchc.lowMeaning", defaultValue: "A low value can be seen with iron deficiency. It is usually interpreted together with other red-cell indices; discuss persistent findings with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.mchc.highMeaning", defaultValue: "A high value is less common and can occasionally reflect certain red-cell conditions or a lab artifact. Consider reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.mchc.about", defaultValue: "MCHC is the concentration of hemoglobin within a given volume of red blood cells.", table: "Engine")
        ),
        LabReference(
            id: "rdw",
            name: String(localized: "lab.rdw.name", defaultValue: "Red Cell Distribution Width", table: "Engine"),
            shortName: String(localized: "lab.rdw.shortName", defaultValue: "RDW", table: "Engine"),
            unit: "%",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 11.5...14.5,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.rdw.lowMeaning", defaultValue: "A low value is generally not a concern and simply indicates red cells that are uniform in size.", table: "Engine"),
            highMeaning: String(localized: "lab.rdw.highMeaning", defaultValue: "A high value means red cells vary more in size, which can be an early sign of iron, B12, or folate shortfalls. Consider reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.rdw.about", defaultValue: "RDW measures how much red blood cells vary in size, which helps evaluate anemia.", table: "Engine")
        ),
        LabReference(
            id: "neutrophilsPercent",
            name: String(localized: "lab.neutrophilsPercent.name", defaultValue: "Neutrophils", table: "Engine"),
            shortName: String(localized: "lab.neutrophilsPercent.shortName", defaultValue: "Neut %", table: "Engine"),
            unit: "%",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 40...60,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.neutrophilsPercent.lowMeaning", defaultValue: "A low percentage can follow some viral infections or certain medications. Discuss persistently low values with a clinician, especially with frequent infections.", table: "Engine"),
            highMeaning: String(localized: "lab.neutrophilsPercent.highMeaning", defaultValue: "A high percentage commonly reflects the body responding to bacterial infection, inflammation, or physical stress. Consider reviewing persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.neutrophilsPercent.about", defaultValue: "Neutrophils are the most common white blood cell and are a first responder to infection.", table: "Engine")
        ),
        LabReference(
            id: "lymphocytesPercent",
            name: String(localized: "lab.lymphocytesPercent.name", defaultValue: "Lymphocytes", table: "Engine"),
            shortName: String(localized: "lab.lymphocytesPercent.shortName", defaultValue: "Lymph %", table: "Engine"),
            unit: "%",
            category: .hematology,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 20...40,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.lymphocytesPercent.lowMeaning", defaultValue: "A low percentage can occur with acute stress, certain infections, or medications. Discuss persistent values with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.lymphocytesPercent.highMeaning", defaultValue: "A high percentage is often seen with viral infections and usually resolves as you recover. Consider reviewing persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.lymphocytesPercent.about", defaultValue: "Lymphocytes are white blood cells central to the immune response, including against viruses.", table: "Engine")
        ),

        // MARK: Lipid Panel

        LabReference(
            id: "totalCholesterol",
            name: String(localized: "lab.totalCholesterol.name", defaultValue: "Total Cholesterol", table: "Engine"),
            shortName: String(localized: "lab.totalCholesterol.shortName", defaultValue: "TC", table: "Engine"),
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...199,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.totalCholesterol.lowMeaning", defaultValue: "A low value is generally not a concern on its own and is usually considered favorable for heart health.", table: "Engine"),
            highMeaning: String(localized: "lab.totalCholesterol.highMeaning", defaultValue: "A high value may relate to diet, activity level, genetics, or other conditions and can raise cardiovascular risk over time. Discuss elevated results with a clinician.", table: "Engine"),
            about: String(localized: "lab.totalCholesterol.about", defaultValue: "Total cholesterol sums the cholesterol carried by all lipoprotein particles in your blood.", table: "Engine")
        ),
        LabReference(
            id: "ldlCholesterol",
            name: String(localized: "lab.ldlCholesterol.name", defaultValue: "LDL Cholesterol", table: "Engine"),
            shortName: String(localized: "lab.ldlCholesterol.shortName", defaultValue: "LDL", table: "Engine"),
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...99,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.ldlCholesterol.lowMeaning", defaultValue: "A low value is generally desirable and associated with lower cardiovascular risk.", table: "Engine"),
            highMeaning: String(localized: "lab.ldlCholesterol.highMeaning", defaultValue: "A high value can build up in artery walls and raise cardiovascular risk over time. Diet, activity, genetics, and other factors contribute; discuss elevated results with a clinician.", table: "Engine"),
            about: String(localized: "lab.ldlCholesterol.about", defaultValue: "LDL, sometimes called \"bad\" cholesterol, can contribute to plaque buildup in arteries.", table: "Engine")
        ),
        LabReference(
            id: "hdlCholesterol",
            name: String(localized: "lab.hdlCholesterol.name", defaultValue: "HDL Cholesterol", table: "Engine"),
            shortName: String(localized: "lab.hdlCholesterol.shortName", defaultValue: "HDL", table: "Engine"),
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: 40...100,
            femaleRange: 50...100,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.hdlCholesterol.lowMeaning", defaultValue: "A low value offers less protective benefit and is linked to higher cardiovascular risk. Regular activity and other habits can help; discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.hdlCholesterol.highMeaning", defaultValue: "A higher value is generally considered protective for heart health.", table: "Engine"),
            about: String(localized: "lab.hdlCholesterol.about", defaultValue: "HDL, sometimes called \"good\" cholesterol, helps remove other cholesterol from the bloodstream.", table: "Engine")
        ),
        LabReference(
            id: "triglycerides",
            name: String(localized: "lab.triglycerides.name", defaultValue: "Triglycerides", table: "Engine"),
            shortName: String(localized: "lab.triglycerides.shortName", defaultValue: "TG", table: "Engine"),
            unit: "mg/dL",
            category: .lipidPanel,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...149,
            criticalLow: nil,
            criticalHigh: 500.0,
            lowMeaning: String(localized: "lab.triglycerides.lowMeaning", defaultValue: "A low value is generally desirable.", table: "Engine"),
            highMeaning: String(localized: "lab.triglycerides.highMeaning", defaultValue: "A high value can relate to diet, alcohol, excess weight, uncontrolled blood sugar, or a recent non-fasting sample. Very high values warrant prompt discussion with a clinician.", table: "Engine"),
            about: String(localized: "lab.triglycerides.about", defaultValue: "Triglycerides are a type of fat in the blood used and stored for energy.", table: "Engine")
        ),

        // MARK: Metabolic

        LabReference(
            id: "fastingGlucose",
            name: String(localized: "lab.fastingGlucose.name", defaultValue: "Fasting Glucose", table: "Engine"),
            shortName: String(localized: "lab.fastingGlucose.shortName", defaultValue: "Glu", table: "Engine"),
            unit: "mg/dL",
            category: .metabolic,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 70...99,
            criticalLow: 54.0,
            criticalHigh: 250.0,
            lowMeaning: String(localized: "lab.fastingGlucose.lowMeaning", defaultValue: "A low value can follow prolonged fasting, intense exercise, or certain medications, and may cause shakiness or lightheadedness. Frequent low readings deserve a clinician's attention.", table: "Engine"),
            highMeaning: String(localized: "lab.fastingGlucose.highMeaning", defaultValue: "A high value can reflect a non-fasting sample, stress, or elevated blood sugar. Repeated high values should be reviewed with a clinician.", table: "Engine"),
            about: String(localized: "lab.fastingGlucose.about", defaultValue: "Fasting glucose measures blood sugar after not eating, typically for at least 8 hours.", table: "Engine")
        ),
        LabReference(
            id: "hba1c",
            name: String(localized: "lab.hba1c.name", defaultValue: "Hemoglobin A1c", table: "Engine"),
            shortName: String(localized: "lab.hba1c.shortName", defaultValue: "HbA1c", table: "Engine"),
            unit: "%",
            category: .metabolic,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 4.0...5.6,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.hba1c.lowMeaning", defaultValue: "A low value is uncommon and can occasionally relate to anemia or shortened red-cell lifespan. Discuss unusual results with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.hba1c.highMeaning", defaultValue: "A higher value reflects higher average blood sugar over recent months. Discuss elevated results with a clinician to understand next steps.", table: "Engine"),
            about: String(localized: "lab.hba1c.about", defaultValue: "HbA1c estimates your average blood sugar over the past two to three months.", table: "Engine")
        ),
        LabReference(
            id: "insulin",
            name: String(localized: "lab.insulin.name", defaultValue: "Fasting Insulin", table: "Engine"),
            shortName: String(localized: "lab.insulin.shortName", defaultValue: "Insulin", table: "Engine"),
            unit: "µIU/mL",
            category: .metabolic,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.6...24.9,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.insulin.lowMeaning", defaultValue: "A low value can simply reflect fasting. Interpretation depends on your blood sugar at the same time; discuss with a clinician if you have questions.", table: "Engine"),
            highMeaning: String(localized: "lab.insulin.highMeaning", defaultValue: "A high value can accompany insulin resistance and is often linked to excess weight or inactivity. Consider reviewing elevated results with a clinician.", table: "Engine"),
            about: String(localized: "lab.insulin.about", defaultValue: "Insulin is the hormone that helps move sugar from the blood into cells for energy.", table: "Engine")
        ),

        // MARK: Kidney & Electrolytes

        LabReference(
            id: "sodium",
            name: String(localized: "lab.sodium.name", defaultValue: "Sodium", table: "Engine"),
            shortName: String(localized: "lab.sodium.shortName", defaultValue: "Na", table: "Engine"),
            unit: "mEq/L",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 135...145,
            criticalLow: 125.0,
            criticalHigh: 155.0,
            lowMeaning: String(localized: "lab.sodium.lowMeaning", defaultValue: "A low value can follow excess fluid intake, certain medications, or fluid loss. Marked or symptomatic changes should be evaluated promptly by a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.sodium.highMeaning", defaultValue: "A high value most often reflects dehydration or insufficient water intake. Persistent or marked elevation warrants a clinician's review.", table: "Engine"),
            about: String(localized: "lab.sodium.about", defaultValue: "Sodium is an electrolyte that helps regulate fluid balance and nerve and muscle function.", table: "Engine")
        ),
        LabReference(
            id: "potassium",
            name: String(localized: "lab.potassium.name", defaultValue: "Potassium", table: "Engine"),
            shortName: String(localized: "lab.potassium.shortName", defaultValue: "K", table: "Engine"),
            unit: "mEq/L",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 3.5...5.1,
            criticalLow: 2.8,
            criticalHigh: 6.2,
            lowMeaning: String(localized: "lab.potassium.lowMeaning", defaultValue: "A low value can result from fluid loss, certain diuretics, or vomiting and may affect muscles and heart rhythm. Notable lows should be discussed promptly with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.potassium.highMeaning", defaultValue: "A high value can relate to kidney function, medications, or a sample handling artifact. Genuine elevation should be reviewed promptly by a clinician.", table: "Engine"),
            about: String(localized: "lab.potassium.about", defaultValue: "Potassium is an electrolyte essential for nerve signals, muscle function, and heart rhythm.", table: "Engine")
        ),
        LabReference(
            id: "chloride",
            name: String(localized: "lab.chloride.name", defaultValue: "Chloride", table: "Engine"),
            shortName: String(localized: "lab.chloride.shortName", defaultValue: "Cl", table: "Engine"),
            unit: "mEq/L",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 98...107,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.chloride.lowMeaning", defaultValue: "A low value can accompany vomiting, certain medications, or fluid shifts. It is usually interpreted alongside other electrolytes; discuss with a clinician if it persists.", table: "Engine"),
            highMeaning: String(localized: "lab.chloride.highMeaning", defaultValue: "A high value can relate to dehydration or acid-base balance. It is typically reviewed with other electrolytes; consider discussing persistent values with a clinician.", table: "Engine"),
            about: String(localized: "lab.chloride.about", defaultValue: "Chloride is an electrolyte that works with sodium to maintain fluid and acid-base balance.", table: "Engine")
        ),
        LabReference(
            id: "calcium",
            name: String(localized: "lab.calcium.name", defaultValue: "Calcium", table: "Engine"),
            shortName: String(localized: "lab.calcium.shortName", defaultValue: "Ca", table: "Engine"),
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 8.6...10.3,
            criticalLow: 6.0,
            criticalHigh: 13.0,
            lowMeaning: String(localized: "lab.calcium.lowMeaning", defaultValue: "A low value can relate to low vitamin D, low albumin, or parathyroid or kidney factors. Discuss notable or symptomatic lows with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.calcium.highMeaning", defaultValue: "A high value can involve parathyroid activity, certain medications, or dehydration. Persistent elevation should be reviewed with a clinician.", table: "Engine"),
            about: String(localized: "lab.calcium.about", defaultValue: "Calcium supports bones, nerve signaling, muscle function, and blood clotting.", table: "Engine")
        ),
        LabReference(
            id: "magnesium",
            name: String(localized: "lab.magnesium.name", defaultValue: "Magnesium", table: "Engine"),
            shortName: String(localized: "lab.magnesium.shortName", defaultValue: "Mg", table: "Engine"),
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 1.7...2.2,
            criticalLow: 1.0,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.magnesium.lowMeaning", defaultValue: "A low value can follow poor intake, alcohol use, certain medications, or digestive losses and may cause cramps. Discuss notable lows with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.magnesium.highMeaning", defaultValue: "A high value is uncommon and is most often related to kidney function or magnesium-containing supplements. Consider reviewing with a clinician.", table: "Engine"),
            about: String(localized: "lab.magnesium.about", defaultValue: "Magnesium is a mineral involved in hundreds of processes, including muscle and nerve function.", table: "Engine")
        ),
        LabReference(
            id: "phosphorus",
            name: String(localized: "lab.phosphorus.name", defaultValue: "Phosphorus", table: "Engine"),
            shortName: String(localized: "lab.phosphorus.shortName", defaultValue: "Phos", table: "Engine"),
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.5...4.5,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.phosphorus.lowMeaning", defaultValue: "A low value can relate to nutrition, certain medications, or vitamin D status. Discuss persistent lows with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.phosphorus.highMeaning", defaultValue: "A high value is often linked to kidney function. It is usually reviewed alongside calcium; consider discussing persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.phosphorus.about", defaultValue: "Phosphorus works with calcium to build bones and support energy metabolism.", table: "Engine")
        ),
        LabReference(
            id: "creatinine",
            name: String(localized: "lab.creatinine.name", defaultValue: "Creatinine", table: "Engine"),
            shortName: String(localized: "lab.creatinine.shortName", defaultValue: "Cr", table: "Engine"),
            unit: "mg/dL",
            category: .kidney,
            maleRange: 0.74...1.35,
            femaleRange: 0.59...1.04,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.creatinine.lowMeaning", defaultValue: "A low value can reflect lower muscle mass and is usually not a concern on its own.", table: "Engine"),
            highMeaning: String(localized: "lab.creatinine.highMeaning", defaultValue: "A high value can relate to reduced kidney filtering, dehydration, high muscle mass, or a recent high-protein meal. Discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.creatinine.about", defaultValue: "Creatinine is a waste product from muscle activity that the kidneys filter out.", table: "Engine")
        ),
        LabReference(
            id: "bun",
            name: String(localized: "lab.bun.name", defaultValue: "Blood Urea Nitrogen", table: "Engine"),
            shortName: String(localized: "lab.bun.shortName", defaultValue: "BUN", table: "Engine"),
            unit: "mg/dL",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 7...20,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.bun.lowMeaning", defaultValue: "A low value can accompany a low-protein diet, overhydration, or liver factors and is usually not concerning on its own.", table: "Engine"),
            highMeaning: String(localized: "lab.bun.highMeaning", defaultValue: "A high value can relate to dehydration, a high-protein diet, or kidney function. It is usually interpreted with creatinine; discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.bun.about", defaultValue: "BUN measures the amount of nitrogen from urea, a waste product the kidneys remove.", table: "Engine")
        ),
        LabReference(
            id: "egfr",
            name: String(localized: "lab.egfr.name", defaultValue: "Estimated GFR", table: "Engine"),
            shortName: String(localized: "lab.egfr.shortName", defaultValue: "eGFR", table: "Engine"),
            unit: "mL/min/1.73m²",
            category: .kidney,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 60...120,
            criticalLow: 15.0,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.egfr.lowMeaning", defaultValue: "A lower value suggests the kidneys are filtering more slowly, which can occur with age, dehydration, or kidney conditions. Discuss persistently low results with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.egfr.highMeaning", defaultValue: "A higher value generally indicates strong kidney filtering and is not a concern.", table: "Engine"),
            about: String(localized: "lab.egfr.about", defaultValue: "eGFR estimates how well your kidneys filter waste, calculated from creatinine and other factors.", table: "Engine")
        ),
        LabReference(
            id: "uricAcid",
            name: String(localized: "lab.uricAcid.name", defaultValue: "Uric Acid", table: "Engine"),
            shortName: String(localized: "lab.uricAcid.shortName", defaultValue: "UA", table: "Engine"),
            unit: "mg/dL",
            category: .kidney,
            maleRange: 3.4...7.0,
            femaleRange: 2.4...6.0,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.uricAcid.lowMeaning", defaultValue: "A low value is usually not a concern and can relate to certain medications or diet.", table: "Engine"),
            highMeaning: String(localized: "lab.uricAcid.highMeaning", defaultValue: "A high value can be influenced by diet, alcohol, dehydration, or genetics and is associated with gout. Discuss persistent elevation, especially with joint pain, with a clinician.", table: "Engine"),
            about: String(localized: "lab.uricAcid.about", defaultValue: "Uric acid is a waste product from the breakdown of purines found in some foods and body cells.", table: "Engine")
        ),

        // MARK: Liver Function

        LabReference(
            id: "alt",
            name: String(localized: "lab.alt.name", defaultValue: "Alanine Aminotransferase", table: "Engine"),
            shortName: String(localized: "lab.alt.shortName", defaultValue: "ALT", table: "Engine"),
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 7...56,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.alt.lowMeaning", defaultValue: "A low value is generally not a concern.", table: "Engine"),
            highMeaning: String(localized: "lab.alt.highMeaning", defaultValue: "A high value can follow alcohol, certain medications, fatty liver, recent intense exercise, or infection. Discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.alt.about", defaultValue: "ALT is an enzyme found mainly in the liver; levels rise when liver cells are stressed.", table: "Engine")
        ),
        LabReference(
            id: "ast",
            name: String(localized: "lab.ast.name", defaultValue: "Aspartate Aminotransferase", table: "Engine"),
            shortName: String(localized: "lab.ast.shortName", defaultValue: "AST", table: "Engine"),
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 10...40,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.ast.lowMeaning", defaultValue: "A low value is generally not a concern.", table: "Engine"),
            highMeaning: String(localized: "lab.ast.highMeaning", defaultValue: "A high value can relate to the liver but also to muscle activity, since AST is found in muscle too. Recent exercise, medications, or alcohol may contribute; discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.ast.about", defaultValue: "AST is an enzyme found in the liver and muscles; it is used alongside ALT to assess the liver.", table: "Engine")
        ),
        LabReference(
            id: "alp",
            name: String(localized: "lab.alp.name", defaultValue: "Alkaline Phosphatase", table: "Engine"),
            shortName: String(localized: "lab.alp.shortName", defaultValue: "ALP", table: "Engine"),
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 44...147,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.alp.lowMeaning", defaultValue: "A low value is uncommon and can occasionally relate to nutrition or certain conditions. Discuss unusual results with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.alp.highMeaning", defaultValue: "A high value can involve the liver, bile ducts, or bone, and is normal during growth or pregnancy. Discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.alp.about", defaultValue: "ALP is an enzyme found in the liver, bile ducts, and bone.", table: "Engine")
        ),
        LabReference(
            id: "ggt",
            name: String(localized: "lab.ggt.name", defaultValue: "Gamma-Glutamyl Transferase", table: "Engine"),
            shortName: String(localized: "lab.ggt.shortName", defaultValue: "GGT", table: "Engine"),
            unit: "U/L",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 8...61,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.ggt.lowMeaning", defaultValue: "A low value is generally not a concern.", table: "Engine"),
            highMeaning: String(localized: "lab.ggt.highMeaning", defaultValue: "A high value can relate to alcohol use, certain medications, or bile-duct issues. It helps clarify the source of a raised ALP; discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.ggt.about", defaultValue: "GGT is a liver enzyme that helps pinpoint whether raised liver values stem from the bile ducts.", table: "Engine")
        ),
        LabReference(
            id: "totalBilirubin",
            name: String(localized: "lab.totalBilirubin.name", defaultValue: "Total Bilirubin", table: "Engine"),
            shortName: String(localized: "lab.totalBilirubin.shortName", defaultValue: "T. Bili", table: "Engine"),
            unit: "mg/dL",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0.1...1.2,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.totalBilirubin.lowMeaning", defaultValue: "A low value is generally not a concern.", table: "Engine"),
            highMeaning: String(localized: "lab.totalBilirubin.highMeaning", defaultValue: "A high value can cause yellowing of the skin or eyes and may relate to the liver, bile flow, red-cell breakdown, or a benign inherited pattern (Gilbert syndrome). Discuss elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.totalBilirubin.about", defaultValue: "Bilirubin is a yellow pigment made when red blood cells break down and is processed by the liver.", table: "Engine")
        ),
        LabReference(
            id: "albumin",
            name: String(localized: "lab.albumin.name", defaultValue: "Albumin", table: "Engine"),
            shortName: String(localized: "lab.albumin.shortName", defaultValue: "Alb", table: "Engine"),
            unit: "g/dL",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 3.5...5.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.albumin.lowMeaning", defaultValue: "A low value can relate to nutrition, inflammation, or liver or kidney factors. Discuss persistent lows with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.albumin.highMeaning", defaultValue: "A high value is most often caused by dehydration. Rehydrating usually resolves it; discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.albumin.about", defaultValue: "Albumin is a protein made by the liver that helps keep fluid in blood vessels and carries substances.", table: "Engine")
        ),
        LabReference(
            id: "totalProtein",
            name: String(localized: "lab.totalProtein.name", defaultValue: "Total Protein", table: "Engine"),
            shortName: String(localized: "lab.totalProtein.shortName", defaultValue: "TP", table: "Engine"),
            unit: "g/dL",
            category: .liver,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 6.0...8.3,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.totalProtein.lowMeaning", defaultValue: "A low value can relate to nutrition, or liver or kidney factors. Discuss persistent lows with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.totalProtein.highMeaning", defaultValue: "A high value can reflect dehydration or ongoing inflammation. Consider reviewing persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.totalProtein.about", defaultValue: "Total protein measures albumin and globulins together, reflecting overall protein in the blood.", table: "Engine")
        ),

        // MARK: Thyroid

        LabReference(
            id: "tsh",
            name: String(localized: "lab.tsh.name", defaultValue: "Thyroid-Stimulating Hormone", table: "Engine"),
            shortName: String(localized: "lab.tsh.shortName", defaultValue: "TSH", table: "Engine"),
            unit: "mIU/L",
            category: .thyroid,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0.4...4.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.tsh.lowMeaning", defaultValue: "A low value can suggest an overactive thyroid, since the body signals less. Certain medications also affect it; discuss with a clinician, often with free T4.", table: "Engine"),
            highMeaning: String(localized: "lab.tsh.highMeaning", defaultValue: "A high value can suggest an underactive thyroid, as the body signals harder for hormone. Discuss elevated results with a clinician, usually alongside free T4.", table: "Engine"),
            about: String(localized: "lab.tsh.about", defaultValue: "TSH is a pituitary hormone that signals the thyroid; it is the primary screen for thyroid function.", table: "Engine")
        ),
        LabReference(
            id: "freeT4",
            name: String(localized: "lab.freeT4.name", defaultValue: "Free Thyroxine", table: "Engine"),
            shortName: String(localized: "lab.freeT4.shortName", defaultValue: "FT4", table: "Engine"),
            unit: "ng/dL",
            category: .thyroid,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0.8...1.8,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.freeT4.lowMeaning", defaultValue: "A low value can accompany an underactive thyroid and is interpreted together with TSH. Discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.freeT4.highMeaning", defaultValue: "A high value can accompany an overactive thyroid and is interpreted together with TSH. Discuss with a clinician.", table: "Engine"),
            about: String(localized: "lab.freeT4.about", defaultValue: "Free T4 is the active, unbound form of the main thyroid hormone circulating in the blood.", table: "Engine")
        ),
        LabReference(
            id: "freeT3",
            name: String(localized: "lab.freeT3.name", defaultValue: "Free Triiodothyronine", table: "Engine"),
            shortName: String(localized: "lab.freeT3.shortName", defaultValue: "FT3", table: "Engine"),
            unit: "pg/mL",
            category: .thyroid,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.3...4.2,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.freeT3.lowMeaning", defaultValue: "A low value can occur with an underactive thyroid or during other illness. It is interpreted with TSH and free T4; discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.freeT3.highMeaning", defaultValue: "A high value can occur with an overactive thyroid. It is interpreted alongside TSH and free T4; discuss with a clinician.", table: "Engine"),
            about: String(localized: "lab.freeT3.about", defaultValue: "Free T3 is the active form of the more potent thyroid hormone and helps assess thyroid function.", table: "Engine")
        ),

        // MARK: Vitamins & Minerals

        LabReference(
            id: "vitaminD",
            name: String(localized: "lab.vitaminD.name", defaultValue: "Vitamin D, 25-Hydroxy", table: "Engine"),
            shortName: String(localized: "lab.vitaminD.shortName", defaultValue: "Vit D", table: "Engine"),
            unit: "ng/mL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 30...100,
            criticalLow: 10.0,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.vitaminD.lowMeaning", defaultValue: "A low value is common, especially with limited sun exposure, and can affect bone health. Diet, sunlight, or supplements may help; discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.vitaminD.highMeaning", defaultValue: "A high value usually results from taking high-dose supplements. Very high values can affect calcium; review supplement use with a clinician.", table: "Engine"),
            about: String(localized: "lab.vitaminD.about", defaultValue: "This measures your body's vitamin D stores, important for bone health and calcium absorption.", table: "Engine")
        ),
        LabReference(
            id: "vitaminB12",
            name: String(localized: "lab.vitaminB12.name", defaultValue: "Vitamin B12", table: "Engine"),
            shortName: String(localized: "lab.vitaminB12.shortName", defaultValue: "B12", table: "Engine"),
            unit: "pg/mL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 200...900,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.vitaminB12.lowMeaning", defaultValue: "A low value can relate to diet (such as a plant-based diet), absorption, or certain medications, and may affect energy and nerves. Discuss persistent lows with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.vitaminB12.highMeaning", defaultValue: "A high value often reflects supplement intake and is usually not concerning. Consider reviewing unexplained elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.vitaminB12.about", defaultValue: "Vitamin B12 supports nerve function and the formation of red blood cells.", table: "Engine")
        ),
        LabReference(
            id: "folate",
            name: String(localized: "lab.folate.name", defaultValue: "Folate", table: "Engine"),
            shortName: String(localized: "lab.folate.shortName", defaultValue: "Folate", table: "Engine"),
            unit: "ng/mL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 2.7...17.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.folate.lowMeaning", defaultValue: "A low value can relate to diet or absorption and may affect red-cell formation. Folate-rich foods or supplements may help; discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.folate.highMeaning", defaultValue: "A high value is usually harmless and often reflects supplements or fortified foods.", table: "Engine"),
            about: String(localized: "lab.folate.about", defaultValue: "Folate (vitamin B9) is needed to make DNA and red blood cells and is important in pregnancy.", table: "Engine")
        ),
        LabReference(
            id: "ferritin",
            name: String(localized: "lab.ferritin.name", defaultValue: "Ferritin", table: "Engine"),
            shortName: String(localized: "lab.ferritin.shortName", defaultValue: "Ferritin", table: "Engine"),
            unit: "ng/mL",
            category: .vitaminsMinerals,
            maleRange: 24...336,
            femaleRange: 11...307,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.ferritin.lowMeaning", defaultValue: "A low value is a sensitive sign of low iron stores and can accompany fatigue. Diet or iron supplements may help; discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.ferritin.highMeaning", defaultValue: "A high value can reflect iron overload but also rises with inflammation or infection. Discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.ferritin.about", defaultValue: "Ferritin reflects the amount of iron your body has in storage.", table: "Engine")
        ),
        LabReference(
            id: "iron",
            name: String(localized: "lab.iron.name", defaultValue: "Serum Iron", table: "Engine"),
            shortName: String(localized: "lab.iron.shortName", defaultValue: "Iron", table: "Engine"),
            unit: "µg/dL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 60...170,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.iron.lowMeaning", defaultValue: "A low value can accompany iron deficiency or blood loss and varies through the day. It is interpreted with ferritin and TIBC; discuss with a clinician.", table: "Engine"),
            highMeaning: String(localized: "lab.iron.highMeaning", defaultValue: "A high value can follow iron supplements, a recent iron-rich meal, or iron overload. Consider reviewing persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.iron.about", defaultValue: "Serum iron measures the amount of iron circulating in the blood at the time of the test.", table: "Engine")
        ),
        LabReference(
            id: "tibc",
            name: String(localized: "lab.tibc.name", defaultValue: "Total Iron-Binding Capacity", table: "Engine"),
            shortName: String(localized: "lab.tibc.shortName", defaultValue: "TIBC", table: "Engine"),
            unit: "µg/dL",
            category: .vitaminsMinerals,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 250...450,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.tibc.lowMeaning", defaultValue: "A low value can be seen with inflammation or iron overload. It is interpreted with iron and ferritin; discuss with a clinician if needed.", table: "Engine"),
            highMeaning: String(localized: "lab.tibc.highMeaning", defaultValue: "A high value often accompanies iron deficiency, as the blood has more capacity to carry iron. Discuss with a clinician alongside iron and ferritin.", table: "Engine"),
            about: String(localized: "lab.tibc.about", defaultValue: "TIBC measures the blood's total capacity to bind and transport iron, reflecting iron status.", table: "Engine")
        ),

        // MARK: Inflammation

        LabReference(
            id: "crp",
            name: String(localized: "lab.crp.name", defaultValue: "C-Reactive Protein", table: "Engine"),
            shortName: String(localized: "lab.crp.shortName", defaultValue: "CRP", table: "Engine"),
            unit: "mg/L",
            category: .inflammation,
            maleRange: nil,
            femaleRange: nil,
            commonRange: 0...3.0,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.crp.lowMeaning", defaultValue: "A low value is generally desirable and suggests little active inflammation.", table: "Engine"),
            highMeaning: String(localized: "lab.crp.highMeaning", defaultValue: "A high value signals inflammation, which can follow infection, injury, or a chronic condition, and rises temporarily with minor illness. Discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.crp.about", defaultValue: "CRP is a protein made by the liver that rises when there is inflammation in the body.", table: "Engine")
        ),
        LabReference(
            id: "esr",
            name: String(localized: "lab.esr.name", defaultValue: "Erythrocyte Sedimentation Rate", table: "Engine"),
            shortName: String(localized: "lab.esr.shortName", defaultValue: "ESR", table: "Engine"),
            unit: "mm/hr",
            category: .inflammation,
            maleRange: 0...15,
            femaleRange: 0...20,
            commonRange: nil,
            criticalLow: nil,
            criticalHigh: nil,
            lowMeaning: String(localized: "lab.esr.lowMeaning", defaultValue: "A low value is generally not a concern.", table: "Engine"),
            highMeaning: String(localized: "lab.esr.highMeaning", defaultValue: "A high value is a nonspecific sign of inflammation and can rise with infection, age, anemia, or pregnancy. Discuss persistent elevation with a clinician.", table: "Engine"),
            about: String(localized: "lab.esr.about", defaultValue: "ESR measures how quickly red blood cells settle, an indirect and general marker of inflammation.", table: "Engine")
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
