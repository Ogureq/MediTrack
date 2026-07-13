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
/// use for no benefit; the grid thumbnail looks up the live
/// `ReportAttachment` by `id` instead (see `DocumentThumbnail`).
struct DocumentItem: Identifiable, Equatable {
    let id: PersistentIdentifier
    let filename: String
    let kind: AttachmentKind
    let reportTitle: String
    let reportCategory: ReportCategory
    let reportDate: Date
}

// MARK: - Flattening & filtering

enum DocumentLibrary {
    /// Flattens every attachment across all reports into one list, newest
    /// report first; when two attachments share a report date, filename
    /// breaks the tie so ordering is stable regardless of fetch order.
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
}

// MARK: - Screen

/// A library of every photo/PDF attachment across all reports, in one
/// searchable, filterable grid. Pushed from the More tab.
struct DocumentsView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

    @State private var searchText = ""
    @State private var selectedCategory: ReportCategory?

    /// Cached instead of recomputed from scratch — via `DocumentLibrary
    /// .items(from:)`, a full flatten over every report's attachments — on
    /// every one of the 3 call sites below (`body`'s empty check,
    /// `availableCategories`, `filteredItems`), which otherwise re-ran on
    /// every search keystroke.
    @State private var allItems: [DocumentItem] = []

    private var availableCategories: [ReportCategory] {
        ReportCategory.allCases.filter { category in allItems.contains { $0.reportCategory == category } }
    }

    private var filteredItems: [DocumentItem] {
        DocumentLibrary.filter(allItems, query: searchText, category: selectedCategory)
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "folder")
                } description: {
                    Text("Attach photos or PDFs to your reports and they'll all appear here.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        categoryChips
                        if filteredItems.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(filteredItems) { item in
                                    NavigationLink {
                                        destination(for: item)
                                    } label: {
                                        DocumentCard(item: item, resolveAttachment: attachment(matching:))
                                    }
                                    .buttonStyle(.plain)
                                }
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
    /// second preview pipeline, and so the grid thumbnail can decode the
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
                categoryChip(title: "All", category: nil)
                ForEach(availableCategories) { category in
                    categoryChip(title: category.displayName, category: category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(title: String, category: ReportCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Grid card

private struct DocumentCard: View {
    let item: DocumentItem
    let resolveAttachment: (PersistentIdentifier) -> ReportAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DocumentThumbnail(item: item, resolveAttachment: resolveAttachment)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.reportTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.reportDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: Glass.chipRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.filename), \(item.reportTitle), \(item.reportDate.formatted(date: .long, time: .omitted)), \(item.kind == .pdf ? "PDF document" : "photo")"
        )
    }
}

// MARK: - Thumbnail

/// Downsampled preview for a document card. Image attachments are decoded
/// once, off the main thread, via ImageIO (never a full-resolution
/// `UIImage(data:)`) and memoized by attachment id so re-scrolling the grid
/// never redecodes; PDFs render a static doc icon since a full PDF render
/// isn't needed for a small grid tile. Looks up the live `ReportAttachment`
/// by id (via `resolveAttachment`) rather than `DocumentItem` carrying its
/// own copy of the raw `data`.
private struct DocumentThumbnail: View {
    let item: DocumentItem
    let resolveAttachment: (PersistentIdentifier) -> ReportAttachment?

    @State private var image: UIImage?

    private let height: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
            switch item.kind {
            case .pdf:
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28))
                    .foregroundStyle(Glass.accentGradient)
            case .image:
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Glass.bevelStroke, lineWidth: 1)
        )
        .accessibilityHidden(true)
        .task(id: item.id) {
            guard item.kind == .image, image == nil, let attachment = resolveAttachment(item.id) else { return }
            image = await ThumbnailCache.shared.thumbnail(for: item.id, data: attachment.data)
        }
    }
}

/// Off-main-thread, memoized thumbnail decoder shared by every grid cell.
private actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var storage: [PersistentIdentifier: UIImage] = [:]

    func thumbnail(for id: PersistentIdentifier, data: Data) async -> UIImage? {
        if let cached = storage[id] { return cached }
        guard let decoded = Self.decode(data) else { return nil }
        storage[id] = decoded
        return decoded
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
}
