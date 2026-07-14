import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// Single-flag gate for report *creation*. Flip `reportCreation` to `false`
/// to make scanning free again — that one-line edit is the entire revert of
/// the premium gate placed around adding reports.
enum PremiumGates {
    static let reportCreation = true
}

/// Scan-only report creation: photograph or import a document, let
/// `LabScanService`'s on-device OCR find lab values automatically, confirm,
/// and save. There is no manual entry form here by design — the manual
/// form still exists for *editing* an existing report (`EditReportView`),
/// which is how users fix or fill in anything a scan missed.
///
/// Gated by `PremiumGates.reportCreation`: when the gate is on and the user
/// isn't premium, the same scan UI is shown underneath a lock card rather
/// than being replaced by a dead end, and the lock card's own button always
/// works (it opens `PaywallView`).
struct ScanReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var premiumStore = PremiumStore.shared

    @State private var attachments: [AttachmentDraft] = []
    @State private var confirmedLabs: [ScannedLabValue] = []
    @State private var scannedValues: [ScannedLabValue] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var showingScanResults = false

    @State private var showingPaywall = false
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var showingPhotosPicker = false
    @State private var photoItems: [PhotosPickerItem] = []

    @State private var selectedCategory: ReportCategory?

    @State private var showingCameraAlert = false
    @State private var cameraAlertMessage = ""

    private var isLocked: Bool {
        PremiumGates.reportCreation && !premiumStore.isPremium
    }

    private var canSave: Bool {
        !attachments.isEmpty && !isScanning && !isLocked
    }

    /// True once a scan has run over every current attachment and found
    /// nothing new — the trigger for the category fallback chips and the
    /// "couldn't find lab values" note.
    private var nothingExtracted: Bool {
        hasScanned && !isScanning && confirmedLabs.isEmpty && scannedValues.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ScanReportHeader()

                    if isLocked {
                        ZStack {
                            unlockedBody
                                .disabled(true)
                                .opacity(0.28)
                                .accessibilityHidden(true)
                            lockedCard
                        }
                    } else {
                        unlockedBody
                    }
                }
                .padding()
            }
            .ambientScreen()
            .navigationTitle("New Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingScanResults) {
                ScannedResultsSheet(values: scannedValues) { selected in
                    confirmedLabs.append(contentsOf: selected)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { data in
                    attachments.append(AttachmentDraft(
                        filename: "Photo \(attachments.count + 1)",
                        kind: .image,
                        data: data
                    ))
                    scanAttachments()
                }
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true,
                onCompletion: handleFileImport
            )
            .photosPicker(isPresented: $showingPhotosPicker, selection: $photoItems, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
            .alert("Camera", isPresented: $showingCameraAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraAlertMessage)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var unlockedBody: some View {
        VStack(spacing: 16) {
            scanActions

            if isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning for lab values…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }

            if !attachments.isEmpty {
                attachmentsSection
            }

            if !confirmedLabs.isEmpty {
                confirmedLabsSection
            }

            if !scannedValues.isEmpty {
                reviewButton
            }

            if nothingExtracted {
                categoryFallbackSection
            }

            if !attachments.isEmpty {
                Text("You can rename or edit details any time from the report's Edit button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var scanActions: some View {
        Button {
            presentCamera()
        } label: {
            ScanActionCard(
                icon: "camera.fill",
                title: "Photograph a Document",
                subtitle: "Use your camera to capture a lab report"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photograph a document")
        .accessibilityHint("Opens the camera to capture a lab report.")

        Menu {
            Button {
                showingPhotosPicker = true
            } label: {
                Label("Photo from Library", systemImage: "photo.on.rectangle")
            }
            Button {
                showingFileImporter = true
            } label: {
                Label("PDF File", systemImage: "doc.richtext")
            }
        } label: {
            ScanActionCard(
                icon: "square.and.arrow.down.on.square",
                title: "Import PDF or Photo",
                subtitle: "Choose an existing file from your library"
            )
        }
        .accessibilityLabel("Import PDF or photo")
        .accessibilityHint("Choose a PDF or photo already saved on your device.")
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Attached", systemImage: "paperclip")
                .font(.subheadline.weight(.semibold))
            ForEach(attachments) { attachment in
                HStack {
                    Label(
                        attachment.filename,
                        systemImage: attachment.kind == .pdf ? "doc.richtext" : "photo"
                    )
                    .font(.subheadline)
                    Spacer()
                    Button {
                        removeAttachment(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(attachment.filename)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var confirmedLabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Detected Lab Values", systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))
            ForEach(confirmedLabs) { scanned in
                HStack {
                    Text(scanned.reference.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(scanned.value.compactFormatted) \(scanned.reference.unit)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var reviewButton: some View {
        Button {
            showingScanResults = true
        } label: {
            Label(
                "Review \(scannedValues.count) Detected Value\(scannedValues.count == 1 ? "" : "s")",
                systemImage: "checkmark.circle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var categoryFallbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "We couldn't find lab values in this document — that's OK, it was saved with your attachment.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("What kind of report is this?")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportCategory.allCases) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var lockedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Glass.accentGradient, in: Circle())
                .accessibilityHidden(true)
            Text("Scan Lab Reports with Premium")
                .font(.headline)
            Text("Photograph or import a lab report and Gemocode extracts your results automatically — no manual typing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingPaywall = true
            } label: {
                Text("Unlock Premium")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan lab reports with Premium. Photograph or import a lab report and Gemocode extracts your results automatically.")
        .accessibilityHint("Double tap Unlock Premium to see plans.")
    }

    // MARK: - Attachment ingestion (mirrors EditReportView's working patterns)

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var addedAny = false
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                attachments.append(AttachmentDraft(
                    filename: "Photo \(attachments.count + 1)",
                    kind: .image,
                    data: data
                ))
                addedAny = true
            }
        }
        photoItems = []
        if addedAny { scanAttachments() }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var addedAny = false
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: url) {
                attachments.append(AttachmentDraft(
                    filename: url.lastPathComponent,
                    kind: .pdf,
                    data: data
                ))
                addedAny = true
            }
        }
        if addedAny { scanAttachments() }
    }

    private func removeAttachment(_ attachment: AttachmentDraft) {
        attachments.removeAll { $0.id == attachment.id }
        if attachments.isEmpty {
            scannedValues = []
            hasScanned = false
        } else {
            scanAttachments()
        }
    }

    /// Runs `LabScanService` over every current attachment — the same
    /// scan machinery `EditReportView` exposes behind a button, just kicked
    /// off automatically the moment a document is attached. Values already
    /// confirmed are filtered out so re-scanning after a new attachment
    /// only surfaces what's new.
    private func scanAttachments() {
        guard !attachments.isEmpty else { return }
        isScanning = true
        let inputs = attachments.map { (kind: $0.kind, data: $0.data) }
        let existingKeys = Set(confirmedLabs.map { $0.reference.id.lowercased() })
        Task {
            let found = await LabScanService.scan(attachments: inputs)
                .filter { !existingKeys.contains($0.reference.id.lowercased()) }
            scannedValues = found
            isScanning = false
            hasScanned = true
            if !found.isEmpty {
                showingScanResults = true
            }
        }
    }

    // MARK: - Camera permission

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlertMessage = "This device doesn't have a camera available. Use Import PDF or Photo instead."
            showingCameraAlert = true
            return
        }
        // This build doesn't yet declare NSCameraUsageDescription in
        // Info.plist — presenting the camera without it would crash at the
        // OS level. Fail soft to the alert instead until that key is added.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            cameraAlertMessage = "Camera access isn't configured in this build yet. Use Import PDF or Photo instead."
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
                        cameraAlertMessage = "Camera access was denied. Enable it in Settings, or use Import PDF or Photo instead."
                        showingCameraAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = "Camera access is disabled for Gemocode. Enable it in Settings, or use Import PDF or Photo instead."
            showingCameraAlert = true
        @unknown default:
            cameraAlertMessage = "Camera access isn't available. Use Import PDF or Photo instead."
            showingCameraAlert = true
        }
    }

    // MARK: - Save

    /// Stable identifier for the 90-day re-test nudge, so scheduling it
    /// again (from a later new report) replaces rather than stacks. This is
    /// the sole "new report" creation path now, so this lives here instead
    /// of `EditReportView`.
    private static let retestNudgeID = "retest.nudge"

    /// Zero manual fields: category is `.labReport` whenever any lab value
    /// was confirmed, otherwise the fallback chip selection (defaulting to
    /// `.other` if the user never picked one — never a required step that
    /// could trap the save). Title is generated from that category and
    /// today's date; `LabScanService` doesn't expose a document date to
    /// parse, so "today" is what's used.
    private func save() {
        guard canSave else { return }
        let now = Date.now
        let category = confirmedLabs.isEmpty ? (selectedCategory ?? .other) : .labReport
        let title = "\(category.displayName) — \(now.formatted(date: .abbreviated, time: .omitted))"

        let report = MedicalReport(title: title, category: category, date: now)
        modelContext.insert(report)

        for scanned in confirmedLabs {
            report.labResults.append(LabResult(
                catalogID: scanned.reference.id,
                value: scanned.value,
                unit: scanned.reference.unit,
                date: now
            ))
        }

        for draft in attachments {
            report.attachments.append(ReportAttachment(
                filename: draft.filename,
                kind: draft.kind,
                data: draft.data
            ))
        }

        if !report.labResults.isEmpty {
            scheduleRetestNudge()
        }

        Haptics.success()
        dismiss()
    }

    /// Nudges the user to re-test in ~90 days after they log a new report
    /// that includes at least one lab result. Neutral, non-urgent copy — a
    /// wellness nudge, not medical advice. Replaces any previously
    /// scheduled nudge so only the most recent lab report restarts the
    /// countdown.
    private func scheduleRetestNudge() {
        NotificationService.cancelReminder(id: Self.retestNudgeID)
        let fireDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now.addingTimeInterval(90 * 86_400)
        Task {
            if await NotificationService.requestAuthorization() {
                NotificationService.scheduleOneTime(
                    id: Self.retestNudgeID,
                    title: "Time for a Follow-Up?",
                    body: "It's been 3 months since your last lab report — re-test to see your trend.",
                    at: fireDate
                )
            }
        }
    }
}

// MARK: - Header

private struct ScanReportHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text("Scan a Report")
                .font(.title2.bold())
            Text("Photograph or import a document — Gemocode reads the lab values for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Action card

private struct ScanActionCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let category: ReportCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(category.displayName, systemImage: category.systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Glass.accentGradient) : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(Capsule().strokeBorder(Glass.bevelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Camera capture

/// Thin `UIImagePickerController` wrapper for capturing a single photo of a
/// document. `ScanReportView.presentCamera()` gates presentation on camera
/// availability and (once configured) permission, so this view only ever
/// appears when it's safe to.
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
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
        let onCapture: (Data) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
