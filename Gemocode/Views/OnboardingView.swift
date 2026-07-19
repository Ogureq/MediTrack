import SwiftUI
import SwiftData

// MARK: - Onboarding quiz
//
// First-run flow: a short welcome, a personalized quiz that seeds the
// on-device `HealthProfile`, a privacy reminder, and a preview of what
// Gemocode will show once real data comes in. Every quiz step can be
// skipped — skipping simply leaves that step's fields at the "unset"
// sentinel values already documented on `HealthProfile` (empty string /
// zero / nil), so a fully-skipped quiz produces the same profile as an
// untouched one. Nothing is written until the final "Open Gemocode" tap.

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var existingProfiles: [HealthProfile]

    @State private var step: QuizStep = .welcome

    // Step: About you
    @State private var name = ""
    @State private var dateOfBirth: Date?
    @State private var sex: BiologicalSex = .unspecified

    // Step: Body basics
    @State private var heightText = ""
    @State private var weightText = ""

    // Step: Daily rhythm
    @State private var activityLevel: ActivityLevel?
    @State private var typicalSleepHours: Double = 7
    @State private var exerciseDaysPerWeek: Int = 3

    // Step: Diet
    @State private var dietStyle = ""

    // Steps: Goals / concerns / supplements
    @State private var goalTags: [String] = []
    @State private var concernTags: [String] = []
    @State private var supplements: [String] = []
    @State private var customSupplementText = ""

    private var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .animation(.easeInOut(duration: 0.25), value: step)

                // Each step manages its own scrolling: `QuizStepScaffold` (used by
                // every step but `preview`) puts the icon/title/content in a
                // `ScrollView` with the Continue/Skip footer pinned below it via
                // `.safeAreaInset`, and `previewStep` does the same itself. Wrapping
                // *this* in another `ScrollView` would nest two vertical scroll
                // views — the inner one's content can fail to lay out (rendering as
                // an empty frame) and a pinned footer can't reserve its own height
                // from a scroll view it isn't inside.
                //
                // The step-change animation used to sit on the outer `ZStack`
                // above, as one blanket `.animation(value: step)` covering
                // everything. Because switching `step` swaps in an entirely new
                // `QuizStepScaffold` (or `previewStep`) instance, that blanket
                // scope gave the *whole* outgoing/incoming view — scrolling
                // content **and** the `.safeAreaInset` footer bundled inside it
                // — the default implicit opacity cross-fade, so two different
                // Continue/Skip button sets rendered blended together on every
                // tap. Scoping the animation to just `stepContent` (and,
                // separately, to `progressBar`) keeps that same pleasant
                // cross-fade for content and the progress capsule, while
                // `QuizStepScaffold`'s footer explicitly opts out via
                // `.transaction { $0.animation = nil }` so it swaps instantly.
                // `previewStep` has no separate footer — its button lives in the
                // same scroll content as everything else — so it cross-fades
                // consistently with the other steps without any extra handling.
                stepContent
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
    }

    // MARK: Progress

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Glass.accentGradient)
                    .frame(width: geometry.size.width * progressFraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var progressFraction: CGFloat {
        let all = QuizStep.allCases
        guard let index = all.firstIndex(of: step), all.count > 1 else { return 0 }
        return CGFloat(index) / CGFloat(all.count - 1)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .aboutYou: aboutYouStep
        case .bodyBasics: bodyBasicsStep
        case .dailyRhythm: dailyRhythmStep
        case .diet: dietStep
        case .goals: goalsStep
        case .concerns: concernsStep
        case .supplements: supplementsStep
        case .privacy: privacyStep
        case .preview: previewStep
        }
    }

    private func advance(resetting reset: (() -> Void)? = nil) {
        reset?()
        step = step.next
    }

    // MARK: Steps

    private var welcomeStep: some View {
        QuizStepScaffold(
            systemImage: "heart.text.square.fill",
            title: "Let's Personalize Gemocode",
            subtitle: "Answer a few quick questions so your Health Review, reminders, and trends are tailored to you. Every question is optional — skip anything you'd rather not answer.",
            primaryTitle: "Get Started",
            onPrimary: { advance() }
        ) {
            EmptyView()
        }
    }

    private var aboutYouStep: some View {
        QuizStepScaffold(
            systemImage: "person.text.rectangle.fill",
            title: "About You",
            subtitle: "This helps Gemocode greet you by name and pick the right reference ranges for lab results.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: {
                name = ""
                dateOfBirth = nil
                sex = .unspecified
            }) }
        ) {
            VStack(spacing: 14) {
                TextField("Name", text: $name)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                DatePicker(
                    "Date of birth",
                    selection: Binding(
                        get: { dateOfBirth ?? defaultDateOfBirth },
                        set: { dateOfBirth = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Picker("Biological sex", selection: $sex) {
                    ForEach(BiologicalSex.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var bodyBasicsStep: some View {
        QuizStepScaffold(
            systemImage: "ruler.fill",
            title: "Body Basics",
            subtitle: "Height and weight let Gemocode calculate BMI and chart trends over time.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: {
                heightText = ""
                weightText = ""
            }) }
        ) {
            VStack(spacing: 14) {
                HStack {
                    Text("Height")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    TextField("cm", text: $heightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 50, maxWidth: 110)
                    Text("cm")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Text("Weight")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    TextField(Units.label(for: .weight), text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 50, maxWidth: 110)
                    Text(Units.label(for: .weight))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var dailyRhythmStep: some View {
        QuizStepScaffold(
            systemImage: "figure.run",
            title: "Daily Rhythm",
            subtitle: "Activity and sleep patterns give context to your vitals and findings.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: {
                activityLevel = nil
                typicalSleepHours = 0
                exerciseDaysPerWeek = 0
            }) }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity level")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 8) {
                        ForEach(ActivityLevel.allCases) { level in
                            SelectableChip(
                                title: level.displayName,
                                isSelected: activityLevel == level
                            ) {
                                activityLevel = (activityLevel == level) ? nil : level
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Typical sleep")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(typicalSleepHours > 0 ? "\(typicalSleepHours.compactFormatted) h" : "Not set")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $typicalSleepHours, in: 4...10, step: 0.5)
                        .accessibilityLabel("Typical sleep hours")
                        .accessibilityValue("\(typicalSleepHours.compactFormatted) hours")
                }

                Stepper(
                    exerciseDaysPerWeek == 1
                        ? "Exercise: \(exerciseDaysPerWeek) day/week"
                        : "Exercise: \(exerciseDaysPerWeek) days/week",
                    value: $exerciseDaysPerWeek,
                    in: 0...7
                )
            }
            .padding(16)
            .glassCard(cornerRadius: 16)
        }
    }

    private var dietStep: some View {
        QuizStepScaffold(
            systemImage: "fork.knife.circle.fill",
            title: "Diet Style",
            subtitle: "Pick the description that fits best — you can change this anytime in Profile & Settings.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: { dietStyle = "" }) }
        ) {
            FlowLayout(spacing: 10) {
                ForEach(dietOptions) { option in
                    SelectableChip(
                        title: option.label,
                        systemImage: option.systemImage,
                        isSelected: dietStyle == option.label
                    ) {
                        dietStyle = (dietStyle == option.label) ? "" : option.label
                    }
                }
            }
        }
    }

    private var goalsStep: some View {
        QuizStepScaffold(
            systemImage: "target",
            title: "Your Goals",
            subtitle: "Select as many as apply — Gemocode will highlight progress toward them.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: { goalTags = [] }) }
        ) {
            FlowLayout(spacing: 10) {
                ForEach(goalOptions) { option in
                    SelectableChip(
                        title: option.label,
                        systemImage: option.systemImage,
                        isSelected: goalTags.contains(option.label)
                    ) {
                        toggle(option.label, in: $goalTags)
                    }
                }
            }
        }
    }

    private var concernsStep: some View {
        QuizStepScaffold(
            systemImage: "stethoscope",
            title: "What Are You Watching?",
            subtitle: "Gemocode will pay closer attention to findings related to these areas.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: { concernTags = [] }) }
        ) {
            FlowLayout(spacing: 10) {
                ForEach(concernOptions) { option in
                    SelectableChip(
                        title: option.label,
                        systemImage: option.systemImage,
                        isSelected: concernTags.contains(option.label)
                    ) {
                        toggle(option.label, in: $concernTags)
                    }
                }
            }
        }
    }

    private var supplementsStep: some View {
        QuizStepScaffold(
            systemImage: "pills.fill",
            title: "Supplements",
            subtitle: "Gemocode can set up a daily reminder for each one you take.",
            primaryTitle: "Continue",
            onPrimary: { advance() },
            onSkip: { advance(resetting: {
                supplements = []
                customSupplementText = ""
            }) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                FlowLayout(spacing: 10) {
                    ForEach(supplementOptions) { option in
                        SelectableChip(
                            title: option.label,
                            systemImage: option.systemImage,
                            isSelected: supplements.contains(option.label)
                        ) {
                            toggle(option.label, in: $supplements)
                        }
                    }
                    ForEach(customSupplements, id: \.self) { custom in
                        SelectableChip(title: custom, systemImage: "checkmark", isSelected: true) {
                            toggle(custom, in: $supplements)
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Add another…", text: $customSupplementText)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit { addCustomSupplement() }
                    Button {
                        addCustomSupplement()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Glass.accentGradient)
                    }
                    .accessibilityLabel("Add supplement")
                    .disabled(customSupplementText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var privacyStep: some View {
        QuizStepScaffold(
            systemImage: "lock.shield.fill",
            title: "Private by Design",
            subtitle: "Everything you just entered — and everything Gemocode tracks — stays on this device.",
            primaryTitle: "Continue",
            onPrimary: { advance() }
        ) {
            // Previously this text sat inside its own `ScrollView` (capped at
            // 160pt) nested inside the step's outer scroll view. A `ScrollView`
            // nested inside another vertical `ScrollView` can fail to size its
            // content on first layout — the card's glass background rendered,
            // but the disclaimer text inside it did not, reading as a big empty
            // box. The disclaimer is a short, fixed string that always fits
            // comfortably, so it doesn't need to scroll on its own — showing it
            // as a plain `Text` inside the card (which itself sits in the
            // step's single scroll view) fixes the rendering and removes the
            // redundant inner scroller.
            Text(HealthReview.disclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .glassCard(cornerRadius: 16)
        }
    }

    private var previewStep: some View {
        // Unlike the other steps, `preview` doesn't route through
        // `QuizStepScaffold`, so it owns its own scroll container — matching
        // every other step now that the outer `OnboardingView` body no longer
        // wraps `stepContent` in a `ScrollView` itself (see `body`).
        ScrollView {
            VStack(spacing: 24) {
                Text("Your Starting Point")
                    .font(.title2.bold())
                    .padding(.top, 24)

                QuizPreviewRing(percent: completenessPercent)
                    .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(previewLines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkle")
                                .foregroundStyle(Glass.accentGradient)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(18)
                .glassCard(cornerRadius: 16)
                .padding(.horizontal, 24)

                Spacer(minLength: 12)

                Button("Open Gemocode") {
                    completeQuiz()
                }
                .buttonStyle(GlassProminentButtonStyle())
                .frame(maxWidth: 300)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .padding(.top, 12)
        }
    }

    // MARK: Supplements helpers

    private var customSupplements: [String] {
        let catalogLabels = Set(supplementOptions.map(\.label))
        return supplements.filter { !catalogLabels.contains($0) }
    }

    private func addCustomSupplement() {
        let trimmed = customSupplementText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !supplements.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            supplements.append(trimmed)
        }
        customSupplementText = ""
    }

    // MARK: Preview helpers

    private var completenessPercent: Int {
        let total = 8
        var answered = 0
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { answered += 1 }
        if dateOfBirth != nil { answered += 1 }
        if sex != .unspecified { answered += 1 }
        if parsedHeightCm != nil || parsedWeight != nil { answered += 1 }
        if activityLevel != nil { answered += 1 }
        if !dietStyle.isEmpty { answered += 1 }
        if !goalTags.isEmpty || !concernTags.isEmpty { answered += 1 }
        if !supplements.isEmpty { answered += 1 }
        return Int((Double(answered) / Double(total) * 100).rounded())
    }

    private var parsedHeightCm: Double? {
        Double(heightText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    /// Descriptive, educational lines only — never medical advice. Falls back
    /// to a generic encouragement if the whole quiz was skipped.
    private var previewLines: [String] {
        var lines: [String] = []

        if let heightCm = parsedHeightCm, heightCm > 0, let weightValue = parsedWeight {
            let weightKg = Units.canonical(weightValue, for: .weight)
            let heightM = heightCm / 100
            if heightM > 0 {
                let bmi = weightKg / (heightM * heightM)
                lines.append(String(localized: "Your BMI is in the \(bmiRangeLabel(bmi)) range — you'll see this reflected in your Health Review."))
            }
        }

        if typicalSleepHours > 0, let healthyRange = VitalType.sleepHours.healthyRange {
            let hours = typicalSleepHours.compactFormatted
            if healthyRange.contains(typicalSleepHours) {
                lines.append(String(localized: "You typically sleep \(hours) hours — right in the 7–9 hour range Gemocode looks for."))
            } else if typicalSleepHours < healthyRange.lowerBound {
                lines.append(String(localized: "You typically sleep \(hours) hours — a little under the 7–9 hour range Gemocode looks for."))
            } else {
                lines.append(String(localized: "You typically sleep \(hours) hours — a little over the 7–9 hour range Gemocode looks for."))
            }
        }

        if !supplements.isEmpty {
            lines.append(
                supplements.count == 1
                    ? String(localized: "We've set up \(supplements.count) reminder for the supplements you take.")
                    : String(localized: "We've set up \(supplements.count) reminders for the supplements you take.")
            )
        } else if !goalTags.isEmpty {
            lines.append(
                goalTags.count == 1
                    ? String(localized: "Gemocode will keep an eye on your \(goalTags.count) selected goal as new data comes in.")
                    : String(localized: "Gemocode will keep an eye on your \(goalTags.count) selected goals as new data comes in.")
            )
        } else if !concernTags.isEmpty {
            lines.append(
                concernTags.count == 1
                    ? String(localized: "Gemocode will pay closer attention to findings related to the \(concernTags.count) area you flagged.")
                    : String(localized: "Gemocode will pay closer attention to findings related to the \(concernTags.count) areas you flagged.")
            )
        }

        if lines.isEmpty {
            lines.append(String(localized: "Add reports, vitals, and medications anytime — your Health Review builds itself as you go."))
        }

        return Array(lines.prefix(3))
    }

    private func bmiRangeLabel(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: "below-typical"
        case 18.5..<25: "healthy"
        case 25..<30: "above-typical"
        default: "higher"
        }
    }

    // MARK: Completion

    private func completeQuiz() {
        let profile: HealthProfile
        if let existing = existingProfiles.first {
            profile = existing
        } else {
            profile = HealthProfile()
            modelContext.insert(profile)
        }

        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.dateOfBirth = dateOfBirth
        profile.sex = sex
        profile.heightCm = parsedHeightCm
        profile.activityLevel = activityLevel?.rawValue ?? ""
        profile.typicalSleepHours = typicalSleepHours
        profile.dietStyle = dietStyle
        profile.exerciseDaysPerWeek = exerciseDaysPerWeek
        profile.healthGoalTags = goalTags
        profile.healthConcerns = concernTags
        profile.supplements = supplements
        profile.hasCompletedQuiz = true

        if let weightValue = parsedWeight {
            modelContext.insert(VitalSample(type: .weight, value: Units.canonical(weightValue, for: .weight)))
        }

        for supplement in supplements {
            modelContext.insert(Reminder(title: supplement, systemImage: "pills.fill"))
        }

        Haptics.success()
        onFinish()
    }
}

// MARK: - Quiz step sequence

private enum QuizStep: CaseIterable, Equatable {
    case welcome, aboutYou, bodyBasics, dailyRhythm, diet, goals, concerns, supplements, privacy, preview

    var next: QuizStep {
        let all = QuizStep.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return self }
        return all[index + 1]
    }
}

// MARK: - Shared step scaffold

private struct QuizStepScaffold<Content: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let onPrimary: () -> Void
    var onSkip: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Scrollable header + content, with Continue/Skip pinned in a
        // `.safeAreaInset` footer below the scroll view rather than living
        // inside it. `.safeAreaInset` automatically reserves bottom content
        // inset equal to the footer's own height (plus the safe area), so
        // every row of a wrapping chip layout (e.g. the Goals step's
        // `FlowLayout`) can scroll fully into view above the footer instead
        // of being cut off / drawn underneath it, while Continue/Skip stay
        // fixed on screen as the content scrolls behind them.
        //
        // The footer view below carries `.transaction { $0.animation = nil }`
        // so it is immune to the step-change cross-fade animation applied to
        // `stepContent` in `OnboardingView.body` — without that override, the
        // implicit opacity transition used when this whole scaffold instance
        // is swapped for the next step's would blend the outgoing and
        // incoming Continue/Skip button sets together instead of swapping
        // them instantly.
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 5)
                        .frame(width: 78, height: 78)

                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Glass.accentGradient)
                }
                .padding(.top, 20)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)

                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(GlassProminentButtonStyle())
                if let onSkip {
                    Button("Skip", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
            .transaction { $0.animation = nil }
        }
    }
}

// MARK: - Selectable chip

private struct SelectableChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    init(title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                // `title` is the identity tag stored/compared elsewhere
                // (`dietStyle`, `goalTags`, …) and must stay the original
                // English value — see `HealthProfile`. Wrapping it in
                // `LocalizedStringKey` here only affects *display*: known
                // catalog tags (the chip option lists below) render
                // translated, while free-typed custom entries (e.g. a
                // custom supplement) simply fall back to showing their own
                // text verbatim when no catalog entry matches.
                Text(LocalizedStringKey(title))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : .primary)
            .background {
                if isSelected {
                    Capsule().fill(Glass.accentGradient)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Capsule().strokeBorder(isSelected ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Glass.bevelStroke), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Flow layout

/// Wraps its children left-to-right, moving to a new row when a child would
/// overflow the available width. Used to lay out variable-length chip sets.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)

        // Report the full proposed width, not just the widest wrapped row.
        // `placeSubviews(in:)` is called with `bounds` equal to whatever this
        // method returns for the *same* proposal, and re-derives its own row
        // wrapping from `bounds.maxX` — if that were narrower than `maxWidth`
        // (e.g. the widest row hugged to less than the available width),
        // placement would wrap more aggressively than this measurement pass
        // did, needing more rows — and more height — than were reserved here.
        // The result: trailing chips render past the bounds the parent
        // allocated and overlap whatever follows (or each other, as rows
        // disagree between the two passes). Keeping both passes' width basis
        // identical keeps the measured height accurate.
        let width = maxWidth.isFinite ? maxWidth : totalWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview ring
//
// A small, self-contained ring for the quiz's final preview screen. It
// visualizes profile completeness, not a health score, so it is kept
// intentionally separate from Dashboard's `ScoreRing`.

private struct QuizPreviewRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(percent) / 100))
                .stroke(Glass.accentGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Profile")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile \(percent) percent complete")
    }
}

// MARK: - Chip catalogs

private struct QuizChipOption: Identifiable, Hashable {
    let label: String
    let systemImage: String
    var id: String { label }
}

private let dietOptions: [QuizChipOption] = [
    QuizChipOption(label: "Balanced", systemImage: "fork.knife"),
    QuizChipOption(label: "Vegetarian", systemImage: "leaf.fill"),
    QuizChipOption(label: "Vegan", systemImage: "leaf.circle.fill"),
    QuizChipOption(label: "Low-Carb", systemImage: "chart.pie.fill"),
    QuizChipOption(label: "Other", systemImage: "ellipsis.circle.fill"),
]

private let goalOptions: [QuizChipOption] = [
    QuizChipOption(label: "Lose Weight", systemImage: "arrow.down.circle.fill"),
    QuizChipOption(label: "Build Muscle", systemImage: "figure.strengthtraining.traditional"),
    QuizChipOption(label: "Improve Sleep", systemImage: "bed.double.fill"),
    QuizChipOption(label: "Reduce Stress", systemImage: "brain.head.profile"),
    QuizChipOption(label: "Eat Healthier", systemImage: "fork.knife"),
    QuizChipOption(label: "Increase Energy", systemImage: "bolt.fill"),
    QuizChipOption(label: "Manage a Condition", systemImage: "cross.case.fill"),
    QuizChipOption(label: "Stay Active", systemImage: "figure.walk"),
]

private let concernOptions: [QuizChipOption] = [
    QuizChipOption(label: "Blood Pressure", systemImage: "waveform.path.ecg"),
    QuizChipOption(label: "Cholesterol", systemImage: "heart.fill"),
    QuizChipOption(label: "Blood Sugar", systemImage: "drop.fill"),
    QuizChipOption(label: "Weight", systemImage: "scalemass.fill"),
    QuizChipOption(label: "Sleep", systemImage: "bed.double.fill"),
    QuizChipOption(label: "Stress & Mood", systemImage: "brain.head.profile"),
    QuizChipOption(label: "Joint & Muscle Pain", systemImage: "bandage.fill"),
    QuizChipOption(label: "Digestive Health", systemImage: "cross.case.fill"),
    QuizChipOption(label: "Family History", systemImage: "person.2.fill"),
]

private let supplementOptions: [QuizChipOption] = [
    QuizChipOption(label: "Vitamin D", systemImage: "sun.max.fill"),
    QuizChipOption(label: "Magnesium", systemImage: "pills.fill"),
    QuizChipOption(label: "Omega-3", systemImage: "fish.fill"),
    QuizChipOption(label: "Iron", systemImage: "pills.fill"),
    QuizChipOption(label: "B12", systemImage: "pills.fill"),
    QuizChipOption(label: "Multivitamin", systemImage: "pills.fill"),
]

private func toggle(_ value: String, in binding: Binding<[String]>) {
    if let index = binding.wrappedValue.firstIndex(of: value) {
        binding.wrappedValue.remove(at: index)
    } else {
        binding.wrappedValue.append(value)
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .modelContainer(for: [HealthProfile.self, VitalSample.self, Reminder.self], inMemory: true)
}
