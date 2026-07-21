import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import AVFoundation

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @Query private var profiles: [HealthProfile]

    @State private var showingAdd = false
    @State private var editingMedication: Medication?

    // MARK: Prescription scan
    @State private var showingScanOptions = false
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isScanningPrescription = false
    @State private var detectedMedications: [DetectedMedication] = []
    @State private var showingScanResults = false
    @State private var showingCameraAlert = false
    @State private var cameraAlertMessage = ""
    /// The in-flight OCR task, cancelled if the view disappears mid-scan —
    /// mirrors `ScanReportView.scanTask`.
    @State private var scanTask: Task<Void, Never>?

    private var activeMedications: [Medication] {
        medications.filter(\.isActive)
    }

    private var pastMedications: [Medication] {
        medications.filter { !$0.isActive }
    }

    private var interactions: [DrugInteraction] {
        MedicationInteractions.check(medicationNames: activeMedications.map(\.name))
    }

    /// Full `AnalysisEngine` pass — re-runs on every access, so `body` binds
    /// it to one local `let` (see below) and threads the result through
    /// instead of letting every row recompute it. Mirrors
    /// `DashboardView.review`/`let review = self.review`.
    private var review: HealthReview {
        AnalysisEngine.generateReview(
            profile: profiles.first,
            reports: reports,
            vitals: vitals,
            medications: medications,
            symptoms: symptoms,
            appointments: appointments
        )
    }

    // MARK: Prescriptions vs. supplements
    //
    // Computed only — no schema change. A medication classifies as a
    // supplement when its `MedicationLabLinks` drug key is one of that
    // table's two supplement-form entries (`ironSupplement`,
    // `vitaminDSupplement`), or its name contains a common supplement-ish
    // token (vitamin/mineral names, English or Russian) that table's
    // synonym list doesn't cover on its own (e.g. a plain "Multivitamin"
    // with no matched drug key at all). Everything else — including every
    // unrecognized name — stays a prescription, the safer default.

    // Includes a bare "iron"/"железо" token (e.g. for "Iron Bisglycinate",
    // not itself one of `MedicationLabLinks`' narrower iron-supplement
    // phrases) even though `MedicationLabLinks`'s own synonym table
    // deliberately excludes it as too common a word — that caution is about
    // not mis-LINKING a medication to lab-monitoring advice; here a false
    // match only puts a row under the wrong section header, a much lower
    // stakes mistake, so the broader token is worth it for coverage.
    private static let supplementKeywordTokens: [String] = [
        "vitamin", "витамин", "supplement", "добавка", "добавки",
        "iron", "железо", "magnesium", "магний",
        "folate", "folic", "фолиев", "фолат",
        "calcium", "кальций", "zinc", "цинк",
        "omega", "омега", "fish oil", "рыбий жир",
        "probiotic", "пробиотик", "multivitamin", "мультивитамин",
    ]

    private func isSupplement(_ medication: Medication) -> Bool {
        if let key = MedicationLabLinks.drugKey(for: medication.name),
           key == "ironSupplement" || key == "vitaminDSupplement" {
            return true
        }
        let lower = medication.name.lowercased()
        return Self.supplementKeywordTokens.contains { lower.contains($0) }
    }

    private var activePrescriptions: [Medication] {
        activeMedications.filter { !isSupplement($0) }
    }

    private var activeSupplements: [Medication] {
        activeMedications.filter { isSupplement($0) }
    }

    var body: some View {
        Group {
            if medications.isEmpty {
                ContentUnavailableView {
                    Label("No Medications", systemImage: "pills")
                } description: {
                    Text("Track the medications you take, with dosage and schedule.")
                } actions: {
                    Button("Add Medication") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                    Button {
                        showingScanOptions = true
                    } label: {
                        Label("Scan a Prescription", systemImage: "doc.text.viewfinder")
                    }
                    .buttonStyle(OutlinedPillButtonStyle())
                    .frame(maxWidth: 220)
                }
            } else {
                // Computed once per render and threaded through explicitly —
                // `review` re-runs the full `AnalysisEngine` pass on every
                // access, and `RetestSchedule.dueOrSoon` flattens every
                // report's lab results; neither should be redone per row.
                let review = self.review
                let retestItems = RetestSchedule.dueOrSoon(reports: reports, now: .now)
                List {
                    if !interactions.isEmpty {
                        Section {
                            ForEach(interactions) { interaction in
                                InteractionRow(interaction: interaction)
                                    .ledgerRow()
                            }
                        } header: {
                            MicroLabel("Possible Interactions")
                        } footer: {
                            Text(MedicationInteractions.disclaimer)
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !activePrescriptions.isEmpty {
                        Section {
                            ForEach(activePrescriptions) { medication in
                                linkedMedicationRow(medication, review: review, retestItems: retestItems)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: activePrescriptions)
                            }
                        } header: {
                            MicroLabel("Prescriptions")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !activeSupplements.isEmpty {
                        Section {
                            ForEach(activeSupplements) { medication in
                                linkedMedicationRow(medication, review: review, retestItems: retestItems)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: activeSupplements)
                            }
                        } header: {
                            MicroLabel("Supplements — from your plan")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !pastMedications.isEmpty {
                        Section {
                            ForEach(pastMedications) { medication in
                                MedicationRow(medication: medication) {
                                    editingMedication = medication
                                }
                                .ledgerRow()
                            }
                            .onDelete { offsets in
                                delete(offsets, from: pastMedications)
                            }
                        } header: {
                            MicroLabel("Past")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if isScanningPrescription {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Scanning for medication names…")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    Section {
                        Button {
                            showingScanOptions = true
                        } label: {
                            Label("Scan a Prescription", systemImage: "doc.text.viewfinder")
                        }
                        .buttonStyle(OutlinedPillButtonStyle())
                        .disabled(isScanningPrescription)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .ambientScreen()
        .navigationTitle("Medications")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
            }
            .accessibilityLabel("Add medication")
        }
        .sheet(isPresented: $showingAdd) { AddMedicationSheet() }
        .sheet(item: $editingMedication) { medication in
            AddMedicationSheet(medication: medication)
        }
        .confirmationDialog("Scan a Prescription", isPresented: $showingScanOptions, titleVisibility: .visible) {
            Button("Take Photo") { presentCamera() }
            Button("Choose from Library") { showingPhotosPicker = true }
        }
        .sheet(isPresented: $showingCamera) {
            PrescriptionCameraCaptureView { image in
                runScan(image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $photoItems, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard let item = items.first else { return }
            photoItems = []
            Task { await loadPhoto(item) }
        }
        .alert("Camera", isPresented: $showingCameraAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraAlertMessage)
        }
        .sheet(isPresented: $showingScanResults) {
            PrescriptionScanResultsSheet(detected: detectedMedications) { selected in
                addDetectedMedications(selected)
            }
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    /// One active medication row: resolves its `MedicationLabLinks` link and
    /// `MedicationMonitorStatus` from the already-cached `review`/
    /// `retestItems` (a cheap lookup over small arrays, not a re-run of the
    /// engine itself) and threads both into `MedicationRow`.
    @ViewBuilder
    private func linkedMedicationRow(_ medication: Medication, review: HealthReview, retestItems: [RetestItem]) -> some View {
        let linkedLabID = MedicationLabLinks.link(for: medication.name)?.primaryLabID
        let status = MedicationLabLinks.status(
            for: medication,
            snapshots: review.labSnapshots,
            retestItems: retestItems,
            now: .now
        )
        MedicationRow(medication: medication, linkedLabID: linkedLabID, monitorStatus: status) {
            editingMedication = medication
        }
        .ledgerRow()
        .contextMenu {
            Button {
                medication.endDate = .now
                NotificationService.cancelReminder(id: medication.reminderID)
            } label: {
                Label("Mark as Ended", systemImage: "checkmark.circle")
            }
        }
    }

    private func delete(_ offsets: IndexSet, from list: [Medication]) {
        for index in offsets {
            NotificationService.cancelReminder(id: list[index].reminderID)
            modelContext.delete(list[index])
        }
    }

    // MARK: - Prescription scan

    private func runScan(_ image: UIImage) {
        isScanningPrescription = true
        scanTask = Task {
            let lines = (try? await LabScanService.recognizeText(in: image)) ?? []
            let found = RxNameMatcher.detect(lines: lines)
            guard !Task.isCancelled else { return }
            detectedMedications = found
            isScanningPrescription = false
            showingScanResults = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            return
        }
        runScan(image)
    }

    private func addDetectedMedications(_ selected: [DetectedMedication]) {
        for item in selected {
            let dosage: String
            if let doseValue = item.doseValue, let doseUnit = item.doseUnit {
                dosage = "\(doseValue.compactFormatted) \(doseUnit)"
            } else {
                dosage = ""
            }
            modelContext.insert(Medication(
                name: item.matchedName,
                dosage: dosage,
                frequency: item.frequencyHint ?? ""
            ))
        }
        if !selected.isEmpty {
            Haptics.success()
        }
    }

    // MARK: - Camera permission (mirrors ScanReportView.presentCamera)

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlertMessage = String(localized: "This device doesn't have a camera available. Use Choose from Library instead.")
            showingCameraAlert = true
            return
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            cameraAlertMessage = String(localized: "Camera access isn't configured in this build yet. Use Choose from Library instead.")
            showingCameraAlert = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingCamera = true
                    } else {
                        cameraAlertMessage = String(localized: "Camera access was denied. Enable it in Settings, or use Choose from Library instead.")
                        showingCameraAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = String(localized: "Camera access is disabled for Gemocode. Enable it in Settings, or use Choose from Library instead.")
            showingCameraAlert = true
        @unknown default:
            cameraAlertMessage = String(localized: "Camera access isn't available. Use Choose from Library instead.")
            showingCameraAlert = true
        }
    }
}

struct InteractionRow: View {
    let interaction: DrugInteraction

    @Environment(\.colorScheme) private var colorScheme

    private var tagKind: TagKind {
        switch interaction.severity {
        case .major: .bad
        case .moderate, .minor: .warn
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(interaction.drugA) + \(interaction.drugB)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                EditorialTag(verbatim: interaction.severity.displayName, kind: tagKind)
            }
            Text(interaction.explanation)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
            Text(interaction.recommendation)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .accessibilityElement(children: .combine)
    }
}

struct MedicationRow: View {
    let medication: Medication
    /// The medication's primary linked `LabCatalog` id
    /// (`MedicationLabLinks.link(for:).primaryLabID`), resolved once by the
    /// caller — `nil` when the medication isn't recognized or is a
    /// vital-only link (e.g. amlodipine). Drives the trailing lab chip.
    var linkedLabID: String? = nil
    /// Resolved once by the caller via `MedicationLabLinks.status(for:...)`
    /// against the render's cached snapshots/retest items — never computed
    /// inside this row. Drives the status caption line.
    var monitorStatus: MedicationMonitorStatus? = nil
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        medication: Medication,
        linkedLabID: String? = nil,
        monitorStatus: MedicationMonitorStatus? = nil,
        onTap: @escaping () -> Void
    ) {
        self.medication = medication
        self.linkedLabID = linkedLabID
        self.monitorStatus = monitorStatus
        self.onTap = onTap
    }

    /// `.noData` omits the line entirely — there's nothing honest to say
    /// yet, matching `MedicationLabLinks.status`'s own "no usable snapshot"
    /// semantics.
    private var monitorLineText: String? {
        guard let monitorStatus else { return nil }
        switch monitorStatus {
        case .working(let labID, _):
            let name = LabCatalog.reference(for: labID)?.shortName ?? labID
            return String(format: String(localized: "Working — %@ in range since started"), name)
        case .checkOverdue(_, let dueDate):
            let dateText = dueDate.formatted(.dateTime.month(.abbreviated).day())
            return String(format: String(localized: "Tracking lab overdue — retest %@ checks if it's working"), dateText)
        case .notImproving(let labID):
            let name = LabCatalog.reference(for: labID)?.shortName ?? labID
            return String(format: String(localized: "%@ still out of range — worth discussing"), name)
        case .noData:
            return nil
        }
    }

    private var monitorLineColor: Color {
        switch monitorStatus {
        case .working: Editorial.tagGood(colorScheme)
        case .checkOverdue: Editorial.tagWarn(colorScheme)
        case .notImproving, .noData, nil: Editorial.muted(colorScheme)
        }
    }

    private var labChipText: String {
        guard let linkedLabID else { return "" }
        let shortName = LabCatalog.reference(for: linkedLabID)?.shortName ?? linkedLabID
        return "\(shortName) ↗"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(medication.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        if medication.isActive, medication.reminderEnabled, let time = medication.reminderTime {
                            Label(time.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(Editorial.accent(colorScheme))
                        }
                    }
                    if !medication.dosage.isEmpty || !medication.frequency.isEmpty {
                        Text([medication.dosage, medication.frequency].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    if !medication.purpose.isEmpty {
                        Text(medication.purpose)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    HStack(spacing: 4) {
                        Text("Since \(medication.startDate.formatted(date: .abbreviated, time: .omitted))")
                        if let endDate = medication.endDate {
                            Text("– \(endDate.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    if let monitorLineText {
                        Text(monitorLineText)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(monitorLineColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if let linkedLabID {
                NavigationLink {
                    LabDetailView(seriesKey: linkedLabID)
                } label: {
                    Text(verbatim: labChipText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Editorial.accent(colorScheme))
                }
                .accessibilityLabel(
                    String(format: String(localized: "View %@ lab detail"), LabCatalog.reference(for: linkedLabID)?.shortName ?? linkedLabID)
                )
            }
        }
    }
}

// MARK: - Prescription scan results

/// Confirms `RxNameMatcher.detect(lines:)` results before creating
/// `Medication` records — a lighter parallel to `ScanReportView`'s
/// scan-confirmation flow (`ScannedResultsSheet`), reusing that file's
/// "selection indicator + ledger row" grammar without touching it.
private struct PrescriptionScanResultsSheet: View {
    let detected: [DetectedMedication]
    let onAdd: ([DetectedMedication]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndices: Set<Int>

    init(detected: [DetectedMedication], onAdd: @escaping ([DetectedMedication]) -> Void) {
        self.detected = detected
        self.onAdd = onAdd
        _selectedIndices = State(initialValue: Set(detected.indices))
    }

    var body: some View {
        NavigationStack {
            Group {
                if detected.isEmpty {
                    ContentUnavailableView(
                        "No Medication Names Recognized",
                        systemImage: "text.viewfinder",
                        description: Text("We couldn't find any medication names in that photo. Try a clearer photo of the label, or add it manually instead.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(Array(detected.enumerated()), id: \.offset) { index, item in
                                detectedRow(index: index, item: item)
                            }
                        } header: {
                            MicroLabel("Detected Medications")
                        } footer: {
                            Text("Review each one against the original photo before adding — text recognition can make mistakes.")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .ambientScreen()
            .navigationTitle("Scan a Prescription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !detected.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add (\(selectedIndices.count))") {
                            onAdd(detected.enumerated().filter { selectedIndices.contains($0.offset) }.map(\.element))
                            dismiss()
                        }
                        .disabled(selectedIndices.isEmpty)
                    }
                }
            }
        }
    }

    private func detectedRow(index: Int, item: DetectedMedication) -> some View {
        let isSelected = selectedIndices.contains(index)
        let details = [
            [item.doseValue?.compactFormatted, item.doseUnit].compactMap { $0 }.joined(separator: " "),
            item.frequencyHint ?? "",
        ].filter { !$0.isEmpty }

        return Button {
            toggle(index)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Editorial.accent(colorScheme) : Editorial.controlBorder(colorScheme))
                    .accessibilityHidden(true)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.matchedName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    Text("“\(item.sourceLine)”")
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }
}

// MARK: - Camera capture (mirrors ScanReportView.CameraCaptureView)

/// Thin `UIImagePickerController` wrapper for capturing a single photo of a
/// prescription. Duplicated rather than shared with `ScanReportView`'s own
/// camera wrapper — that file is owned by another pass and stays untouched;
/// this type only mirrors its picker mechanics (delegate hookup, off-main
/// JPEG encode via `Task.detached`).
private struct PrescriptionCameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let onCapture = onCapture
            let dismiss = dismiss
            if let image {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existingMedication: Medication?

    @State private var name: String
    @State private var dosage: String
    @State private var frequency: String
    @State private var purpose: String
    @State private var notes: String
    @State private var startDate: Date
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var showingDetails: Bool
    /// Guards `save()` against a double tap firing two inserts before the
    /// sheet has dismissed — checked and set at the top of `save()`, and
    /// mirrored onto the Save button's `disabled` state.
    @State private var isSaving = false

    private static let frequencyOptions = [
        "Once daily", "Twice daily", "Every morning", "Every night", "As needed",
    ]
    private static let dosageUnits = ["mg", "mcg", "ml", "tablets"]

    init(medication: Medication? = nil) {
        existingMedication = medication
        _name = State(initialValue: medication?.name ?? "")
        _dosage = State(initialValue: medication?.dosage ?? "")
        _frequency = State(initialValue: medication?.frequency ?? "")
        _purpose = State(initialValue: medication?.purpose ?? "")
        _notes = State(initialValue: medication?.notes ?? "")
        _startDate = State(initialValue: medication?.startDate ?? .now)
        _reminderEnabled = State(initialValue: medication?.reminderEnabled ?? false)
        _reminderTime = State(initialValue: medication?.reminderTime
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
        _showingDetails = State(initialValue: !(medication?.purpose ?? "").isEmpty || !(medication?.notes ?? "").isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: "pills.fill",
                        tint: .teal,
                        title: existingMedication == nil ? "Add Medication" : "Edit Medication",
                        subtitle: "Track dosage, schedule, and reminders."
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel("Name")
                        TextField("e.g. Lisinopril", text: $name)
                            .font(.body)

                        Divider().opacity(0.5)

                        SheetFieldLabel("Dosage")
                        TextField("e.g. 500 mg", text: $dosage)
                            .font(.body)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.dosageUnits, id: \.self) { unit in
                                    SuggestionChip(label: unit, isSelected: false) {
                                        appendUnit(unit)
                                    }
                                }
                            }
                        }

                        Divider().opacity(0.5)

                        SheetFieldLabel("Frequency")
                        TextField("e.g. Twice daily", text: $frequency)
                            .font(.body)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.frequencyOptions, id: \.self) { option in
                                    SuggestionChip(label: option, isSelected: frequency == option) {
                                        frequency = option
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Start Date")
                        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Daily reminder", isOn: $reminderEnabled.animation())
                            .font(.body.weight(.semibold))
                        if reminderEnabled {
                            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        }
                        Text("Gemocode sends a local notification every day at this time while the medication is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 14) {
                            SheetFieldLabel("Purpose")
                            TextField("e.g. Blood pressure", text: $purpose)
                                .font(.body)

                            SheetFieldLabel("Notes")
                            TextField("Notes", text: $notes, axis: .vertical)
                                .font(.body)
                                .lineLimit(2...4)
                        }
                        .padding(.top, 12)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .padding()
            }
            .ambientScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Replaces any existing unit suffix on the dosage field with the tapped one.
    private func appendUnit(_ unit: String) {
        SheetHaptics.selection()
        let numberPart = dosage.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        dosage = numberPart.isEmpty ? unit : "\(numberPart) \(unit)"
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let medication: Medication
        if let existingMedication {
            medication = existingMedication
            medication.name = name.trimmingCharacters(in: .whitespaces)
            medication.dosage = dosage.trimmingCharacters(in: .whitespaces)
            medication.frequency = frequency.trimmingCharacters(in: .whitespaces)
            medication.purpose = purpose.trimmingCharacters(in: .whitespaces)
            medication.notes = notes
            medication.startDate = startDate
        } else {
            medication = Medication(
                name: name.trimmingCharacters(in: .whitespaces),
                dosage: dosage.trimmingCharacters(in: .whitespaces),
                frequency: frequency.trimmingCharacters(in: .whitespaces),
                purpose: purpose.trimmingCharacters(in: .whitespaces),
                notes: notes,
                startDate: startDate
            )
            modelContext.insert(medication)
        }
        medication.reminderEnabled = reminderEnabled
        medication.reminderTime = reminderEnabled ? reminderTime : nil

        // Reschedule from scratch so edits never leave a stale notification.
        NotificationService.cancelReminder(id: medication.reminderID)
        if reminderEnabled && medication.isActive {
            let id = medication.reminderID
            let medicationName = medication.name
            let dosageText = medication.dosage
            let time = reminderTime
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleDailyReminder(
                        id: id,
                        medicationName: medicationName,
                        dosage: dosageText,
                        at: time
                    )
                }
            }
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Shared sheet UI

/// Friendly header shown at the top of the add/edit sheet: a tinted icon
/// tile plus a bold title and one-line subtitle, replacing a bare nav title.
private struct SheetHeader: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small uppercase caption used above a field inside a glass block.
private struct SheetFieldLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Tappable capsule chip used to fill a field without typing.
private struct SuggestionChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            SheetHaptics.selection()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .background(isSelected ? Editorial.accent(colorScheme).opacity(0.22) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Editorial.accent(colorScheme).opacity(0.7) : Editorial.controlBorder(colorScheme),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Editorial.accent(colorScheme) : Editorial.ink(colorScheme))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Light selection feedback for chip taps — UIHelpers only defines the
/// success notification haptic, so this stays local to each sheet file.
private enum SheetHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
