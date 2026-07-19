import SwiftUI
import SwiftData
import UIKit
import ImageIO

// MARK: - Pure model

/// A single attachment surfaced in the document library, flattened out of
/// its parent `MedicalReport`. Kept as plain values (not a `@Model`
/// reference) so `DocumentLibrary`'s flattening/filtering logic is testable
/// without a live `ModelContext`. Deliberately does *not* carry the
/// attachment's raw `data` — that's an `@Attribute(.externalStorage)` blob,
/// and copying it into every item on every flatten would multiply memory
/// use for no benefit; the row's icon chip looks up the live
/// `ReportAttachment` by `id` instead (see `DocumentIconChip`). Byte size is
/// deliberately NOT carried here either, for the same reason: reading
/// `.count` touches the external-storage blob, so `DocumentRow` resolves it
/// lazily, once per visible row, via `ByteCountCache` — never eagerly for
/// every attachment while flattening.
struct DocumentItem: Identifiable, Equatable {
    let id: PersistentIdentifier
    let filename: String
    let kind: AttachmentKind
    let reportTitle: String
    let reportCategory: ReportCategory
    let reportDate: Date
}

/// A recency-grouped bucket of documents for section headers ("This Month",
/// "Earlier This Year", then one section per earlier calendar year).
struct DocumentSection: Identifiable, Equatable {
    let id: String
    let label: String
    let items: [DocumentItem]
}

// MARK: - Flattening, filtering & grouping

enum DocumentLibrary {
    /// Flattens every attachment across all reports into one list, newest
    /// report first; when two attachments share a report date, filename
    /// breaks the tie so ordering is stable regardless of fetch order.
    /// Deliberately never touches `attachment.data` — that would fault
    /// every attachment's full external-storage blob into memory on every
    /// call (see `byteCount(for:)` and `ByteCountCache`, which resolve size
    /// lazily instead).
    static func items(from reports: [MedicalReport]) -> [DocumentItem] {
        reports
            .flatMap { report in
                report.attachments.map { attachment in
                    DocumentItem(
                        id: attachment.persistentModelID,
                        filename: attachment.filename,
                        kind: attachment.kind,
                        reportTitle: report.title,
                        reportCategory: report.category,
                        reportDate: report.date
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.reportDate != rhs.reportDate {
                    return lhs.reportDate > rhs.reportDate
                }
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
    }

    /// Reads an attachment's external-storage blob size. Kept as a small,
    /// separate, synchronously-testable function — never called from
    /// `items(from:)` — since touching `.data` faults the whole blob into
    /// memory and callers must only do that for an attachment that's about
    /// to be shown (see `ByteCountCache` in DocumentsView's row UI).
    static func byteCount(for attachment: ReportAttachment) -> Int {
        attachment.data.count
    }

    /// Matches `query` against filename OR report title, case- and
    /// diacritic-insensitively (`localizedStandardContains`); a
    /// whitespace-only or empty query matches everything. `category == nil`
    /// matches every category.
    static func filter(_ items: [DocumentItem], query: String, category: ReportCategory?) -> [DocumentItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            if let category, item.reportCategory != category { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return item.filename.localizedStandardContains(trimmedQuery)
                || item.reportTitle.localizedStandardContains(trimmedQuery)
        }
    }

    /// Buckets `items` into recency sections relative to `now`: the current
    /// calendar month, the remainder of the current calendar year, then one
    /// section per earlier year (most recent first). Empty buckets are
    /// omitted. Items keep their incoming relative order within a bucket —
    /// callers normally pass output from `items(from:)`, which is already
    /// newest-first, so each section reads newest-first too. Deterministic
    /// and unit-testable: `now` is a parameter, never `Date()` internally.
    static func sections(from items: [DocumentItem], now: Date, calendar: Calendar = .current) -> [DocumentSection] {
        guard let nowYear = calendar.dateComponents([.year], from: now).year else { return [] }
        let nowMonth = calendar.component(.month, from: now)

        var thisMonth: [DocumentItem] = []
        var earlierThisYear: [DocumentItem] = []
        var byYear: [Int: [DocumentItem]] = [:]
        var yearOrder: [Int] = []

        for item in items {
            let year = calendar.component(.year, from: item.reportDate)
            if year == nowYear {
                let month = calendar.component(.month, from: item.reportDate)
                if month == nowMonth {
                    thisMonth.append(item)
                } else {
                    earlierThisYear.append(item)
                }
            } else {
                if byYear[year] == nil { yearOrder.append(year) }
                byYear[year, default: []].append(item)
            }
        }

        var sections: [DocumentSection] = []
        if !thisMonth.isEmpty {
            sections.append(DocumentSection(id: "this-month", label: String(localized: "This Month"), items: thisMonth))
        }
        if !earlierThisYear.isEmpty {
            sections.append(DocumentSection(id: "earlier-this-year", label: String(localized: "Earlier This Year"), items: earlierThisYear))
        }
        for year in yearOrder.sorted(by: >) {
            sections.append(DocumentSection(id: "year-\(year)", label: String(year), items: byYear[year] ?? []))
        }
        return sections
    }

    /// Uppercased filename extension for the row's format badge (e.g.
    /// "PDF", "JPG"); falls back to "FILE" when the filename has none.
    static func fileExtension(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }

    /// Deterministic tint per report category, matching the app-wide
    /// category-tint convention introduced by the More-grid redesign: labs
    /// blue, imaging purple, prescriptions green, everything else orange.
    static func tint(for category: ReportCategory) -> Color {
        switch category {
        case .labReport: Color(red: 120 / 255, green: 190 / 255, blue: 255 / 255)
        case .imaging: Color(red: 168 / 255, green: 150 / 255, blue: 255 / 255)
        case .prescription: Color(red: 126 / 255, green: 232 / 255, blue: 176 / 255)
        case .consultation, .vaccination, .procedure, .other: Color(red: 255 / 255, green: 178 / 255, blue: 102 / 255)
        }
    }
}

// MARK: - Screen

/// A library of every photo/PDF attachment across all reports, grouped by
/// recency and filterable by category. Pushed from the More tab.
struct DocumentsView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

    @State private var searchText = ""
    @State private var selectedCategory: ReportCategory?

    /// Cached instead of recomputed from scratch — via `DocumentLibrary
    /// .items(from:)`, a full flatten + sort over every report's
    /// attachments — on every one of the call sites below (`body`'s empty
    /// check, `availableCategories`, `filteredItems`), which otherwise
    /// re-ran on every search keystroke. Rebuilt once per
    /// `.task(id: reports.count)`, not per render. `items(from:)` never
    /// reads attachment byte size (see `ByteCountCache`), so this cache
    /// build itself never faults external-storage blobs.
    @State private var allItems: [DocumentItem] = []

    /// False until the first `.task(id:)` pass has populated `allItems`.
    /// Gates both empty states below so a brief, genuinely-empty cache on
    /// first appearance renders a blank container instead of flashing
    /// "No Documents" (or, since the search-results check is also derived
    /// from the not-yet-populated cache, the "no search results" state)
    /// every time this screen is opened even when documents exist.
    @State private var hasLoaded = false

    private var availableCategories: [ReportCategory] {
        ReportCategory.allCases.filter { category in allItems.contains { $0.reportCategory == category } }
    }

    private var filteredItems: [DocumentItem] {
        DocumentLibrary.filter(allItems, query: searchText, category: selectedCategory)
    }

    private var groupedSections: [DocumentSection] {
        DocumentLibrary.sections(from: filteredItems, now: .now)
    }

    var body: some View {
        Group {
            if hasLoaded && allItems.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "folder")
                } description: {
                    Text("Attach photos or PDFs to your reports and they'll all appear here.")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        categoryChips
                        if hasLoaded && filteredItems.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .padding(.top, 40)
                        } else {
                            ForEach(groupedSections) { section in
                                sectionView(section)
                            }
                        }
                    }
                    .padding(16)
                }
                .searchable(text: $searchText, prompt: "Search documents")
            }
        }
        .ambientScreen()
        .navigationTitle("Documents")
        .task(id: reports.count) {
            allItems = DocumentLibrary.items(from: reports)
            hasLoaded = true
        }
    }

    private func sectionView(_ section: DocumentSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(section.label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 9) {
                ForEach(section.items) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        DocumentRow(item: item, resolveAttachment: attachment(matching:))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for item: DocumentItem) -> some View {
        if let attachment = attachment(matching: item.id) {
            AttachmentViewer(attachment: attachment)
        } else {
            ContentUnavailableView("Can't Preview File", systemImage: "eye.slash")
        }
    }

    /// Recovers the live `ReportAttachment` behind a `DocumentItem`'s id so
    /// the tap-through preview can reuse `AttachmentViewer` — the same
    /// full-screen image/PDF viewer `ReportDetailView` uses — instead of a
    /// second preview pipeline, and so the row's icon chip can decode the
    /// real `data` without `DocumentItem` having to carry a copy of it.
    private func attachment(matching id: PersistentIdentifier) -> ReportAttachment? {
        for report in reports {
            if let match = report.attachments.first(where: { $0.persistentModelID == id }) {
                return match
            }
        }
        return nil
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: String(localized: "All"), category: nil)
                ForEach(availableCategories) { category in
                    categoryChip(title: category.displayName, category: category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Matches `TrendsView.metricChipsRow`'s selected-chip treatment exactly
    /// (accent-gradient fill + dark ink text when selected, plain glass pill
    /// otherwise) so the chip language reads as one system across screens.
    private func categoryChip(title: String, category: ReportCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Self.selectedChipTextColor : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(Glass.accentGradient)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Capsule().strokeBorder(Glass.bevelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static let selectedChipTextColor = Color(red: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x20 / 255.0)
}

// MARK: - List row

private struct DocumentRow: View {
    let item: DocumentItem
    let resolveAttachment: (PersistentIdentifier) -> ReportAttachment?

    /// Resolved lazily on appearance via `ByteCountCache` — nil means "not
    /// resolved yet," not "zero bytes." Grid/list rows are virtualized, so
    /// only visible rows ever fault their attachment's external-storage
    /// blob, and only once per row identity (mirrors `DocumentIconChip`'s
    /// `image` state below).
    @State private var byteCount: Int?

    private var sizeText: String {
        guard let byteCount else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private var dateText: String {
        item.reportDate.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        HStack(spacing: 12) {
            DocumentIconChip(item: item, resolveAttachment: resolveAttachment)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(item.reportTitle) · \(sizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(dateText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassCard(cornerRadius: Glass.chipRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.filename), \(item.reportTitle), \(sizeText), \(item.reportDate.formatted(date: .long, time: .omitted))"
        )
        .task(id: item.id) {
            guard byteCount == nil else { return }
            // Cache-first: `attachment.data` faults the whole external-storage
            // blob, so it must only be touched on a cache miss — evaluating it
            // as a call argument would fault it even for cached ids.
            if let cached = await ByteCountCache.shared.cachedByteCount(for: item.id) {
                byteCount = cached
                return
            }
            guard let attachment = resolveAttachment(item.id) else { return }
            byteCount = await ByteCountCache.shared.byteCount(for: item.id, data: attachment.data)
        }
    }
}

// MARK: - Icon chip

/// Tinted, per-category icon chip leading each row. Image attachments show
/// a real downsampled preview (decoded once, off the main thread, via
/// ImageIO and memoized by attachment id in `ThumbnailCache` — never a
/// full-resolution `UIImage(data:)`, and never redecoded on re-scroll); PDFs
/// and anything else show a document glyph. Either way a small format badge
/// (from `DocumentLibrary.fileExtension(for:)`) overlays the bottom-trailing
/// corner. Looks up the live `ReportAttachment` by id (via
/// `resolveAttachment`) rather than `DocumentItem` carrying its own copy of
/// the raw `data`.
private struct DocumentIconChip: View {
    let item: DocumentItem
    let resolveAttachment: (PersistentIdentifier) -> ReportAttachment?

    @State private var image: UIImage?

    private let size: CGFloat = 44

    private var tint: Color { DocumentLibrary.tint(for: item.reportCategory) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)

            switch item.kind {
            case .pdf:
                Image(systemName: "doc.richtext")
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
            case .image:
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ProgressView()
                        .tint(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            Text(DocumentLibrary.fileExtension(for: item.filename))
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(tint)
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .background(.black.opacity(0.55), in: Capsule())
                .offset(x: 4, y: 4)
        }
        .accessibilityHidden(true)
        .task(id: item.id) {
            guard item.kind == .image, image == nil, let attachment = resolveAttachment(item.id) else { return }
            image = await ThumbnailCache.shared.thumbnail(for: item.id, data: attachment.data)
        }
    }
}

/// Off-main-thread, memoized thumbnail decoder shared by every row.
private actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var storage: [PersistentIdentifier: UIImage] = [:]

    /// Bounds memory for a very large document library: once the cache
    /// holds this many decoded thumbnails, half are evicted (arbitrary
    /// order — this is a decode cache, not history) to make room, rather
    /// than growing without limit for the life of the app.
    private static let capacity = 300

    func thumbnail(for id: PersistentIdentifier, data: Data) async -> UIImage? {
        if let cached = storage[id] { return cached }
        guard let decoded = Self.decode(data) else { return nil }
        if storage.count >= Self.capacity {
            for key in storage.keys.prefix(storage.count / 2) {
                storage.removeValue(forKey: key)
            }
        }
        storage[id] = decoded
        return decoded
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 120,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Off-main-thread, memoized attachment byte-size lookup shared by every
/// row — mirrors `ThumbnailCache`'s shape (including the eviction cap)
/// exactly, so an attachment's external-storage blob is only ever faulted
/// once per resolved id, not once per attachment on every document-library
/// rebuild.
private actor ByteCountCache {
    static let shared = ByteCountCache()

    private var storage: [PersistentIdentifier: Int] = [:]
    private static let capacity = 300

    /// Cache lookup that never touches the blob — callers check this first
    /// and only fault `attachment.data` on a miss.
    func cachedByteCount(for id: PersistentIdentifier) -> Int? {
        storage[id]
    }

    func byteCount(for id: PersistentIdentifier, data: Data) async -> Int {
        if let cached = storage[id] { return cached }
        if storage.count >= Self.capacity {
            for key in storage.keys.prefix(storage.count / 2) {
                storage.removeValue(forKey: key)
            }
        }
        let count = data.count
        storage[id] = count
        return count
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
}
