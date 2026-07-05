import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct LabResultDraft: Identifiable {
    let id = UUID()
    var catalogID: String?
    var customName: String = ""
    var unit: String = ""
    var valueText: String = ""
    var lowText: String = ""
    var highText: String = ""

    var displayName: String {
        if let catalogID, let reference = LabCatalog.reference(for: catalogID) {
            return reference.name
        }
        return customName
    }

    var value: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }

    var customLow: Double? {
        Double(lowText.replacingOccurrences(of: ",", with: "."))
    }

    var customHigh: Double? {
        Double(highText.replacingOccurrences(of: ",", with: "."))
    }
}

struct AttachmentDraft: Identifiable {
    let id = UUID()
    let filename: String
    let kind: AttachmentKind
    let data: Data
}

struct AddReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existingReport: MedicalReport?

    @State private var title: String
    @State private var category: ReportCategory
    @State private var date: Date
    @State private var provider: String
    @State private var facility: String
    @State private var notes: String

    @State private var labDrafts: [LabResultDraft] = []
    @State private var attachments: [AttachmentDraft] = []
    @State private var removedLabResults: [LabResult] = []
    @State private var removedAttachments: [ReportAttachment] = []

    @State private var showingLabEntry = false
    @State private var showingFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isScanning = false
    @State private var scannedValues: [ScannedLabValue] = []
    @State private var showingScanResults = false

    init(report: MedicalReport? = nil) {
        existingReport = report
        _title = State(initialValue: report?.title ?? "")
        _category = State(initialValue: report?.category ?? .labReport)
        _date = State(initialValue: report?.date ?? .now)
        _provider = State(initialValue: report?.provider ?? "")
        _facility = State(initialValue: report?.facility ?? "")
        _notes = State(initialValue: report?.notes ?? "")
    }

    private var isEditing: Bool { existingReport != nil }

    /// Existing lab results minus the ones marked for removal in this edit session.
    private var remainingLabResults: [LabResult] {
        guard let existingReport else { return [] }
        return existingReport.labResults
            .filter { result in !removedLabResults.contains(where: { $0 === result }) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var remainingAttachments: [ReportAttachment] {
        guard let existingReport else { return [] }
        return existingReport.attachments.filter { attachment in
            !removedAttachments.contains(where: { $0 === attachment })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Report") {
                    TextField("Title (e.g. Annual Blood Panel)", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(ReportCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Doctor / Provider", text: $provider)
                    TextField("Facility", text: $facility)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section("Lab Results") {
                    ForEach(remainingLabResults) { result in
                        HStack {
                            Text(result.displayName)
                            Spacer()
                            Text("\(result.value.compactFormatted) \(result.unit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        removedLabResults.append(contentsOf: offsets.map { remainingLabResults[$0] })
                    }
                    ForEach(labDrafts) { draft in
                        HStack {
                            Text(draft.displayName)
                            Spacer()
                            Text("\(draft.valueText) \(draft.unit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { labDrafts.remove(atOffsets: $0) }
                    Button {
                        showingLabEntry = true
                    } label: {
                        Label("Add Lab Result", systemImage: "plus.circle.fill")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section("Attachments") {
                    ForEach(remainingAttachments) { attachment in
                        Label(
                            attachment.filename,
                            systemImage: attachment.kind == .pdf ? "doc.richtext" : "photo"
                        )
                    }
                    .onDelete { offsets in
                        removedAttachments.append(contentsOf: offsets.map { remainingAttachments[$0] })
                    }
                    ForEach(attachments) { attachment in
                        Label(
                            attachment.filename,
                            systemImage: attachment.kind == .pdf ? "doc.richtext" : "photo"
                        )
                    }
                    .onDelete { attachments.remove(atOffsets: $0) }
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Add Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Add PDF", systemImage: "doc.badge.plus")
                    }
                    if !attachments.isEmpty || !remainingAttachments.isEmpty {
                        Button {
                            scanAttachments()
                        } label: {
                            if isScanning {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Scanning…")
                                }
                            } else {
                                Label("Scan for Lab Values", systemImage: "doc.text.viewfinder")
                            }
                        }
                        .disabled(isScanning)
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle(isEditing ? "Edit Report" : "New Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingLabEntry) {
                LabEntrySheet { labDrafts.append($0) }
            }
            .sheet(isPresented: $showingScanResults) {
                ScannedResultsSheet(values: scannedValues) { selected in
                    for scanned in selected {
                        var draft = LabResultDraft()
                        draft.catalogID = scanned.reference.id
                        draft.unit = scanned.reference.unit
                        draft.valueText = scanned.value.compactFormatted
                        labDrafts.append(draft)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true,
                onCompletion: handleFileImport
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                attachments.append(AttachmentDraft(
                    filename: "Photo \(attachments.count + 1)",
                    kind: .image,
                    data: data
                ))
            }
        }
        photoItems = []
    }

    private func scanAttachments() {
        isScanning = true
        let inputs = remainingAttachments.map { (kind: $0.kind, data: $0.data) }
            + attachments.map { (kind: $0.kind, data: $0.data) }
        let existingKeys = Set(labDrafts.compactMap { $0.catalogID?.lowercased() })
            .union(remainingLabResults.compactMap { $0.catalogID?.lowercased() })
        Task {
            let found = await LabScanService.scan(attachments: inputs)
                .filter { !existingKeys.contains($0.reference.id.lowercased()) }
            scannedValues = found
            isScanning = false
            showingScanResults = true
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
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
            }
        }
    }

    private func save() {
        let report: MedicalReport
        if let existingReport {
            report = existingReport
            report.title = title.trimmingCharacters(in: .whitespaces)
            report.category = category
            report.date = date
            report.provider = provider.trimmingCharacters(in: .whitespaces)
            report.facility = facility.trimmingCharacters(in: .whitespaces)
            report.notes = notes
            for result in removedLabResults {
                modelContext.delete(result)
            }
            for attachment in removedAttachments {
                modelContext.delete(attachment)
            }
            // Keep lab result dates aligned with the (possibly changed) report date.
            for result in remainingLabResults {
                result.date = date
            }
        } else {
            report = MedicalReport(
                title: title.trimmingCharacters(in: .whitespaces),
                category: category,
                date: date,
                provider: provider.trimmingCharacters(in: .whitespaces),
                facility: facility.trimmingCharacters(in: .whitespaces),
                notes: notes
            )
            modelContext.insert(report)
        }

        for draft in labDrafts {
            guard let value = draft.value else { continue }
            let result = LabResult(
                catalogID: draft.catalogID,
                customName: draft.catalogID == nil ? draft.customName : nil,
                value: value,
                unit: draft.unit,
                customLow: draft.catalogID == nil ? draft.customLow : nil,
                customHigh: draft.catalogID == nil ? draft.customHigh : nil,
                date: date
            )
            report.labResults.append(result)
        }

        for draft in attachments {
            report.attachments.append(ReportAttachment(
                filename: draft.filename,
                kind: draft.kind,
                data: draft.data
            ))
        }

        dismiss()
    }
}

// MARK: - Lab entry sheet

struct LabEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (LabResultDraft) -> Void

    @State private var searchText = ""
    @State private var selectedReference: LabReference?
    @State private var isCustom = false
    @State private var customName = ""
    @State private var customUnit = ""
    @State private var lowText = ""
    @State private var highText = ""
    @State private var valueText = ""

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }

    private var canAdd: Bool {
        guard parsedValue != nil else { return false }
        if selectedReference != nil { return true }
        return isCustom && !customName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let reference = selectedReference {
                    Section("Test") {
                        LabeledContent("Test", value: reference.name)
                        LabeledContent("Unit", value: reference.unit)
                        if let range = reference.referenceRange(for: nil) {
                            LabeledContent(
                                "Typical Range",
                                value: "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(reference.unit)"
                            )
                        }
                        Button("Choose a Different Test") {
                            selectedReference = nil
                            valueText = ""
                        }
                    }
                    .listRowBackground(GlassRowBackground())
                    .listRowSeparator(.hidden)
                    valueSection
                } else if isCustom {
                    Section("Custom Test") {
                        TextField("Test name", text: $customName)
                        TextField("Unit (e.g. mg/dL)", text: $customUnit)
                        TextField("Reference low (optional)", text: $lowText)
                            .keyboardType(.decimalPad)
                        TextField("Reference high (optional)", text: $highText)
                            .keyboardType(.decimalPad)
                        Button("Back to Catalog") { isCustom = false }
                    }
                    .listRowBackground(GlassRowBackground())
                    .listRowSeparator(.hidden)
                    valueSection
                } else {
                    Section {
                        Button {
                            isCustom = true
                        } label: {
                            Label("Custom Test…", systemImage: "plus.circle")
                        }
                    }
                    .listRowBackground(GlassRowBackground())
                    .listRowSeparator(.hidden)
                    ForEach(LabCategory.allCases) { category in
                        let tests = filteredTests(in: category)
                        if !tests.isEmpty {
                            Section(category.displayName) {
                                ForEach(tests) { reference in
                                    Button {
                                        selectedReference = reference
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(reference.name)
                                                .foregroundStyle(.primary)
                                            Text("\(reference.shortName) · \(reference.unit)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(GlassRowBackground())
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .ambientScreen()
            .searchable(text: $searchText, prompt: "Search tests")
            .navigationTitle("Add Lab Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(!canAdd)
                }
            }
        }
    }

    private var valueSection: some View {
        Section("Result") {
            TextField("Value", text: $valueText)
                .keyboardType(.decimalPad)
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparator(.hidden)
    }

    private func filteredTests(in category: LabCategory) -> [LabReference] {
        let tests = LabCatalog.tests(in: category)
        guard !searchText.isEmpty else { return tests }
        let matches = LabCatalog.search(searchText)
        return tests.filter { test in matches.contains(test) }
    }

    private func add() {
        var draft = LabResultDraft()
        if let reference = selectedReference {
            draft.catalogID = reference.id
            draft.unit = reference.unit
        } else {
            draft.customName = customName.trimmingCharacters(in: .whitespaces)
            draft.unit = customUnit.trimmingCharacters(in: .whitespaces)
            draft.lowText = lowText
            draft.highText = highText
        }
        draft.valueText = valueText
        onAdd(draft)
        dismiss()
    }
}
