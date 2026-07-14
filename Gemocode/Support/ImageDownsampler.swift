import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Image downsampling
//
// Report attachments captured from the camera or picked from the photo
// library arrive at full sensor resolution (often 12+ MP) even though the
// only consumers — the on-screen thumbnail, the OCR pass, and the attachment
// viewer — never need more than a couple thousand pixels on the long edge.
// Storing the original blindly multiplies SwiftData's external-storage
// footprint (and backup size) for no visible benefit. `downsampledJPEG`
// re-encodes at a bounded size using ImageIO's thumbnail pipeline, which
// decodes progressively and never materializes the full-resolution bitmap
// in memory — the same technique `DocumentsView`'s `ThumbnailCache` uses,
// just with a much larger target so scanned lab-report text stays legible
// to both the user and `LabScanService`'s OCR pass.

enum ImageDownsampler {
    /// Re-encodes `data` as JPEG with its long edge capped at `maxPixelSize`,
    /// decoding via ImageIO's thumbnail pipeline (never a full-resolution
    /// `UIImage(data:)`). Returns `nil` when `data` isn't a decodable image.
    ///
    /// Never inflates: if the source is already at or under `maxPixelSize`
    /// on its long edge, the re-encode is only kept when it's smaller than
    /// the original — otherwise the original `data` is returned unchanged.
    static func downsampledJPEG(
        from data: Data,
        maxPixelSize: CGFloat = 2200,
        compressionQuality: CGFloat = 0.8
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        guard let encoded = encode(cgImage, compressionQuality: compressionQuality) else { return nil }

        // Determine whether the source was already within bounds so we never
        // hand back a re-encode that's larger than what we started with.
        let sourceLongEdge = longEdge(of: source)
        let alreadyWithinBounds = sourceLongEdge.map { $0 <= maxPixelSize } ?? false
        if alreadyWithinBounds && encoded.count >= data.count {
            return data
        }
        return encoded
    }

    private static func longEdge(of source: CGImageSource) -> CGFloat? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return nil }
        return CGFloat(max(width, height))
    }

    private static func encode(_ cgImage: CGImage, compressionQuality: CGFloat) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: compressionQuality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
