//
//  QuickAddParser.swift
//  MediTrack
//
//  Deterministic, rule-based natural-language parser for the "Quick Add" bar.
//  No AI, no networking — a keyword-table matcher in the same spirit as
//  `LabSynonyms.match(in:)`. Given a free-text line it picks the single most
//  confident interpretation (vital > medication > symptom > appointment >
//  reminder) and returns a draft the UI can prefill and let the user confirm.
//
//  All relative date/time math is performed against the caller-supplied
//  `now`/`calendar` — never `Date()` or `Calendar.current` — so parsing stays
//  unit-testable and reproducible.
//

import Foundation

/// A best-effort structured interpretation of a Quick Add line.
enum QuickAddDraft: Equatable {
    case medication(name: String, dosage: String, frequency: String)
    case vital(type: VitalType, value: Double, secondary: Double?)
    case symptom(name: String, severity: Int)
    case appointment(title: String, date: Date)
    case reminder(title: String, time: Date?)
}

enum QuickAddParser {

    /// Deterministic best-effort parse. Returns nil when nothing confident matched.
    static func parse(_ text: String, now: Date, calendar: Calendar) -> QuickAddDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if let vital = parseVital(lower) { return vital }
        if let medication = parseMedication(lower) { return medication }
        if let symptom = parseSymptom(lower) { return symptom }
        if let appointment = parseAppointment(lower, now: now, calendar: calendar) { return appointment }
        if let reminder = parseReminder(lower, now: now, calendar: calendar) { return reminder }
        return nil
    }

    // MARK: - Vitals

    /// Matches lb → kg display conversion in `Support/Units.swift` (`WeightUnit.pounds`).
    private static let poundsPerKilogram = 2.204_62

    private static func parseVital(_ lower: String) -> QuickAddDraft? {
        parseBloodPressure(lower)
            ?? parseWeight(lower)
            ?? parseHeartRate(lower)
            ?? parseTemperature(lower)
            ?? parseGlucose(lower)
            ?? parseOxygenSaturation(lower)
            ?? parseRespiratoryRate(lower)
            ?? parseSleepHours(lower)
    }

    private static func parseBloodPressure(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("bp", in: lower) ?? rangeOfKeyword("blood pressure", in: lower) else {
            return nil
        }
        let readings = Array(numbers(in: String(lower[range.upperBound...])).prefix(2))
        guard readings.count == 2 else { return nil }
        let systolic = readings[0]
        let diastolic = readings[1]
        guard (60...260).contains(systolic), (30...200).contains(diastolic) else { return nil }
        return .vital(type: .bloodPressure, value: systolic, secondary: diastolic)
    }

    private static func parseWeight(_ lower: String) -> QuickAddDraft? {
        let hasKeyword = rangeOfKeyword("weight", in: lower) != nil || rangeOfKeyword("weigh", in: lower) != nil
        let hasPoundUnit = ["lbs", "lb", "pounds", "pound"].contains { rangeOfKeyword($0, in: lower) != nil }
        let hasKgUnit = ["kg", "kilograms", "kilogram"].contains { rangeOfKeyword($0, in: lower) != nil }
        guard hasKeyword || hasPoundUnit || hasKgUnit else { return nil }
        guard let raw = numbers(in: lower).first else { return nil }
        let kg = hasPoundUnit ? raw / poundsPerKilogram : raw
        guard (20...300).contains(kg) else { return nil }
        return .vital(type: .weight, value: kg, secondary: nil)
    }

    private static func parseHeartRate(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("heart rate", in: lower)
            ?? rangeOfKeyword("pulse", in: lower)
            ?? rangeOfKeyword("hr", in: lower) else { return nil }
        guard let raw = numbers(in: String(lower[range.upperBound...])).first else { return nil }
        guard (25...250).contains(raw) else { return nil }
        return .vital(type: .heartRate, value: raw, secondary: nil)
    }

    private static func parseTemperature(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("temperature", in: lower) ?? rangeOfKeyword("temp", in: lower) else {
            return nil
        }
        guard let raw = numbers(in: String(lower[range.upperBound...])).first else { return nil }
        // Body temperature is never plausibly above 45 in Celsius, so treat larger readings as Fahrenheit.
        let celsius = raw > 45 ? (raw - 32) * 5 / 9 : raw
        guard (25...45).contains(celsius) else { return nil }
        return .vital(type: .temperature, value: celsius, secondary: nil)
    }

    private static func parseGlucose(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("glucose", in: lower) ?? rangeOfKeyword("blood sugar", in: lower) else {
            return nil
        }
        guard let raw = numbers(in: String(lower[range.upperBound...])).first else { return nil }
        guard (30...600).contains(raw) else { return nil }
        return .vital(type: .bloodGlucose, value: raw, secondary: nil)
    }

    private static func parseOxygenSaturation(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("spo2", in: lower) ?? rangeOfKeyword("oxygen", in: lower) else {
            return nil
        }
        guard let raw = numbers(in: String(lower[range.upperBound...])).first else { return nil }
        guard (50...100).contains(raw) else { return nil }
        return .vital(type: .oxygenSaturation, value: raw, secondary: nil)
    }

    private static func parseRespiratoryRate(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("respiratory rate", in: lower)
            ?? rangeOfKeyword("resp rate", in: lower)
            ?? rangeOfKeyword("resp", in: lower) else { return nil }
        guard let raw = numbers(in: String(lower[range.upperBound...])).first else { return nil }
        guard (4...60).contains(raw) else { return nil }
        return .vital(type: .respiratoryRate, value: raw, secondary: nil)
    }

    private static func parseSleepHours(_ lower: String) -> QuickAddDraft? {
        guard let range = rangeOfKeyword("slept", in: lower) ?? rangeOfKeyword("sleep", in: lower) else {
            return nil
        }
        guard let raw = numbers(in: String(lower[range.upperBound...])).first else { return nil }
        guard (0...24).contains(raw) else { return nil }
        return .vital(type: .sleepHours, value: raw, secondary: nil)
    }

    // MARK: - Medication

    /// Lowercased dosage-unit spellings → canonical display unit.
    private static let dosageUnits: [String: String] = [
        "mg": "mg", "milligram": "mg", "milligrams": "mg",
        "mcg": "mcg", "microgram": "mcg", "micrograms": "mcg",
        "g": "g", "gram": "g", "grams": "g",
        "ml": "ml", "milliliter": "ml", "milliliters": "ml",
        "iu": "IU",
        "unit": "units", "units": "units",
        "tablet": "tablets", "tablets": "tablets", "tab": "tablets", "tabs": "tablets",
        "capsule": "capsules", "capsules": "capsules", "cap": "capsules", "caps": "capsules"
    ]

    private static let leadVerbs: Set<String> = ["take", "taking", "start", "started", "starting", "began", "begin"]
    private static let medicationFillerWords: Set<String> = [
        "a", "an", "the", "of", "my", "some", "to", "remind", "me", "please"
    ]
    private static let frequencyStopWords: Set<String> = [
        "daily", "weekly", "monthly", "morning", "night", "evening", "needed",
        "every", "once", "twice", "three", "times", "as", "per", "day"
    ]

    private static let frequencyPhrases: [(phrase: String, normalized: String)] = [
        ("twice daily", "twice daily"),
        ("three times daily", "three times daily"),
        ("once daily", "once daily"),
        ("every morning", "every morning"),
        ("every night", "every night"),
        ("every evening", "every night"),
        ("as needed", "as needed"),
        ("weekly", "weekly"),
        ("daily", "once daily")
    ]

    private static func matchFrequency(in lower: String) -> String {
        for entry in frequencyPhrases where lower.contains(entry.phrase) {
            return entry.normalized
        }
        return ""
    }

    private static func parseMedication(_ lower: String) -> QuickAddDraft? {
        let words = lower.split(separator: " ").map { stripPunctuation(String($0)) }
        guard !words.isEmpty else { return nil }

        var dosageStart: Int?
        var dosageEnd: Int?
        var normalizedDosage = ""

        for i in 0..<words.count {
            if let (number, unit) = splitNumberAndUnit(words[i]), let canonical = dosageUnits[unit] {
                dosageStart = i
                dosageEnd = i
                normalizedDosage = "\(formattedDosageNumber(number)) \(canonical)"
                break
            }
            if i + 1 < words.count, let number = Double(words[i]), let canonical = dosageUnits[words[i + 1]] {
                dosageStart = i
                dosageEnd = i + 1
                normalizedDosage = "\(formattedDosageNumber(number)) \(canonical)"
                break
            }
        }

        let hasLeadVerb = words.first.map(leadVerbs.contains) ?? false
        guard dosageStart != nil || hasLeadVerb else { return nil }

        func isStop(_ word: String) -> Bool {
            leadVerbs.contains(word) || medicationFillerWords.contains(word) || frequencyStopWords.contains(word)
        }

        let nameWords: [String]
        if let dosageStart, let dosageEnd {
            let before = (0..<dosageStart).map { words[$0] }.filter { !isStop($0) }
            if !before.isEmpty {
                nameWords = before
            } else if dosageEnd + 1 < words.count, !isStop(words[dosageEnd + 1]) {
                nameWords = [words[dosageEnd + 1]]
            } else {
                nameWords = []
            }
        } else {
            nameWords = (1..<words.count).map { words[$0] }.filter { !isStop($0) }
        }
        guard !nameWords.isEmpty else { return nil }

        let name = nameWords.map(capitalizeWord).joined(separator: " ")
        return .medication(name: name, dosage: normalizedDosage, frequency: matchFrequency(in: lower))
    }

    /// Splits a fused token like "10mg" into its numeric and unit parts.
    /// Returns nil for tokens that aren't a plain number-then-letters shape.
    private static func splitNumberAndUnit(_ word: String) -> (number: Double, unit: String)? {
        var numberPart = ""
        var unitPart = ""
        for character in word {
            if character.isNumber || character == "." {
                guard unitPart.isEmpty else { return nil }
                numberPart.append(character)
            } else {
                unitPart.append(character)
            }
        }
        guard let number = Double(numberPart), !unitPart.isEmpty else { return nil }
        return (number, unitPart)
    }

    /// Locale-independent numeric formatting for dosage strings (no thousands grouping).
    private static func formattedDosageNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: - Symptoms

    private static let simpleSymptoms: [String] = [
        "headache", "migraine", "nausea", "fatigue", "dizziness",
        "cough", "fever", "insomnia", "anxiety", "rash"
    ]

    private static let painQualifiers: [String] = [
        "back", "chest", "stomach", "abdominal", "joint", "muscle",
        "neck", "knee", "shoulder", "ear", "tooth", "head"
    ]

    private static func parseSymptom(_ lower: String) -> QuickAddDraft? {
        var name: String?

        if let painRange = rangeOfKeyword("pain", in: lower) {
            for qualifier in painQualifiers {
                guard let qualifierRange = rangeOfKeyword(qualifier, in: lower),
                      qualifierRange.upperBound <= painRange.lowerBound else { continue }
                let between = lower[qualifierRange.upperBound..<painRange.lowerBound]
                if between.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = "\(capitalizeWord(qualifier)) Pain"
                    break
                }
            }
            if name == nil { name = "Pain" }
        } else {
            for symptom in simpleSymptoms where rangeOfKeyword(symptom, in: lower) != nil {
                name = capitalizeWord(symptom)
                break
            }
        }

        guard let symptomName = name else { return nil }
        return .symptom(name: symptomName, severity: matchSeverity(in: lower) ?? 5)
    }

    private static func matchSeverity(in lower: String) -> Int? {
        if let range = rangeOfKeyword("severity", in: lower) ?? rangeOfKeyword("level", in: lower),
           let raw = numbers(in: String(lower[range.upperBound...])).first {
            return clampSeverity(raw)
        }
        if let slashRange = lower.range(of: "/10") {
            let before = lower[lower.startIndex..<slashRange.lowerBound]
            if let raw = numbers(in: String(before)).last {
                return clampSeverity(raw)
            }
        }
        return nil
    }

    private static func clampSeverity(_ value: Double) -> Int {
        min(10, max(1, Int(value.rounded())))
    }

    // MARK: - Appointments

    private static let appointmentTriggers = [
        "appointment", "appt", "doctor", "dentist", "checkup", "follow-up", "follow up"
    ]

    private static let appointmentStopWords: Set<String> = [
        "tomorrow", "today", "next", "week", "weeks", "day", "days", "in", "on", "at",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "am", "pm", "i", "have", "a", "an", "schedule", "book", "set", "up", "my", "with", "for", "the"
    ]

    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7
    ]

    private static func parseAppointment(_ lower: String, now: Date, calendar: Calendar) -> QuickAddDraft? {
        let hasDoctorPrefix = rangeOfKeyword("dr", in: lower) != nil
        guard hasDoctorPrefix || appointmentTriggers.contains(where: { lower.contains($0) }) else { return nil }

        let dateOnly = resolveRelativeDate(in: lower, now: now, calendar: calendar)
        let time = resolveTime(in: lower)

        var components = calendar.dateComponents([.year, .month, .day], from: dateOnly)
        components.hour = time?.hour ?? 10
        components.minute = time?.minute ?? 0
        components.second = 0
        guard let finalDate = calendar.date(from: components) else { return nil }

        return .appointment(title: cleanedAppointmentTitle(lower), date: finalDate)
    }

    private static func resolveRelativeDate(in lower: String, now: Date, calendar: Calendar) -> Date {
        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        if lower.contains("next week") {
            return calendar.date(byAdding: .day, value: 7, to: now) ?? now
        }
        if let days = matchInNDays(in: lower) {
            return calendar.date(byAdding: .day, value: days, to: now) ?? now
        }
        if let weeks = matchInNWeeks(in: lower) {
            return calendar.date(byAdding: .day, value: weeks * 7, to: now) ?? now
        }
        for (name, weekday) in weekdayNames where rangeOfKeyword(name, in: lower) != nil {
            return nextOccurrence(of: weekday, from: now, calendar: calendar)
        }
        // Covers "today" and the default when no relative phrase is present.
        return now
    }

    private static func matchInNDays(in lower: String) -> Int? {
        guard let range = rangeOfKeyword("in", in: lower) else { return nil }
        let tail = String(lower[range.upperBound...])
        guard tail.contains("day"), !tail.contains("week"), let raw = numbers(in: tail).first else { return nil }
        return Int(raw)
    }

    private static func matchInNWeeks(in lower: String) -> Int? {
        guard let range = rangeOfKeyword("in", in: lower) else { return nil }
        let tail = String(lower[range.upperBound...])
        guard tail.contains("week"), let raw = numbers(in: tail).first else { return nil }
        return Int(raw)
    }

    private static func nextOccurrence(of weekday: Int, from now: Date, calendar: Calendar) -> Date {
        var date = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        for _ in 0..<7 {
            if calendar.component(.weekday, from: date) == weekday { return date }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    /// Parses "at 3pm" / "at 15:30" style phrases; nil when no clock time is present.
    private static func resolveTime(in lower: String) -> (hour: Int, minute: Int)? {
        guard let range = rangeOfKeyword("at", in: lower) else { return nil }
        return parseClockTime(String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private static func parseClockTime(_ text: String) -> (hour: Int, minute: Int)? {
        var hourPart = ""
        var minutePart = ""
        var seenColon = false
        for character in text {
            if character.isNumber {
                if seenColon { minutePart.append(character) } else { hourPart.append(character) }
            } else if character == ":", !seenColon {
                seenColon = true
            } else if !hourPart.isEmpty {
                break
            }
        }
        guard var hour = Int(hourPart) else { return nil }
        let minute = Int(minutePart) ?? 0
        if text.contains("pm"), hour < 12 { hour += 12 }
        if text.contains("am"), hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func cleanedAppointmentTitle(_ lower: String) -> String {
        let words = lower.split(separator: " ").map { stripPunctuation(String($0)) }
        let kept = words.filter { word in
            guard !appointmentStopWords.contains(word) else { return false }
            guard Double(word) == nil else { return false }
            let hasDigit = word.contains { $0.isNumber }
            if hasDigit && (word.contains("am") || word.contains("pm") || word.contains(":")) { return false }
            return true
        }
        guard !kept.isEmpty else { return "Appointment" }
        return capitalizeWord(kept.joined(separator: " "))
    }

    // MARK: - Reminders

    private static func parseReminder(_ lower: String, now: Date, calendar: Calendar) -> QuickAddDraft? {
        var bodyStart: String.Index?
        if let range = rangeOfKeyword("remind me to", in: lower) {
            bodyStart = range.upperBound
        } else if let range = lower.range(of: "reminder:") {
            bodyStart = range.upperBound
        } else if let range = rangeOfKeyword("reminder", in: lower) {
            bodyStart = range.upperBound
        }
        guard let bodyStart else { return nil }

        var body = String(lower[bodyStart...]).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        let time = resolveTime(in: body)
        if let atRange = body.range(of: " at ") {
            body = String(body[body.startIndex..<atRange.lowerBound])
        } else if body.hasPrefix("at ") {
            body = ""
        }
        body = body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        var concreteTime: Date?
        if let time {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = time.hour
            components.minute = time.minute
            components.second = 0
            concreteTime = calendar.date(from: components)
        }
        return .reminder(title: capitalizeWord(body), time: concreteTime)
    }

    // MARK: - Shared helpers

    /// Extracts every decimal number in the text, in order of appearance.
    private static func numbers(in text: String) -> [Double] {
        var result: [Double] = []
        var current = ""
        for character in text {
            if character.isNumber || character == "." {
                current.append(character)
            } else {
                if !current.isEmpty, let value = Double(current) { result.append(value) }
                current = ""
            }
        }
        if !current.isEmpty, let value = Double(current) { result.append(value) }
        return result
    }

    /// Finds the first word-bounded occurrence of `keyword` in `text` (neighboring
    /// characters, if any, must not be letters). Mirrors `LabSynonyms.match(in:)`.
    private static func rangeOfKeyword(_ keyword: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let range = text.range(of: keyword, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if beforeOK && afterOK { return range }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func stripPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// Capitalizes only the first character; the rest is lowercased. Applied to
    /// already-lowercased fragments to produce display-ready titles/names.
    private static func capitalizeWord(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }
}
