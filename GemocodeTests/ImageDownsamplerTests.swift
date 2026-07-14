import XCTest
import UIKit
import ImageIO
@testable import Gemocode

/// Coverage for `ImageDownsampler.downsampledJPEG` — the ImageIO-based
/// re-encode applied to camera/library/file-import attachments before
/// they're stored, so full-resolution photos of lab reports don't bloat
/// SwiftData's external storage. No `ModelContainer` needed: this is pure
/// `Data` in, `Data` out, mirroring `AIReportPDFExporterTests`'s
/// no-container pattern.
final class ImageDownsamplerTests: XCTestCase {

    /// Renders a solid-fill JPEG at the given pixel size — large enough
    /// (4000×3000) to stand in for an uncompressed camera capture, or small
    /// enough (400×300) to stand in for something already well under the
    /// downsample target.
    private func makeJPEG(width: Int, height: Int) throws -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 10, y: 10, width: width / 3, height: height / 3))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 1.0))
    }

    /// Long edge in pixels of a decodable image `Data`, via the same ImageIO
    /// properties path `ImageDownsampler` itself uses — avoids materializing
    /// a full `UIImage` just to measure it.
    private func longEdge(of data: Data) throws -> CGFloat {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue)
        let height = try XCTUnwrap((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue)
        return CGFloat(max(width, height))
    }

    func testLargeImageIsDownsampledAndDecodable() throws {
        let original = try makeJPEG(width: 4000, height: 3000)

        let result = try XCTUnwrap(ImageDownsampler.downsampledJPEG(from: original, maxPixelSize: 2200))

        // Decodable.
        let decodedEdge = try longEdge(of: result)
        XCTAssertLessThanOrEqual(decodedEdge, 2200)

        // Smaller than the original — the whole point of downsampling.
        XCTAssertLessThan(result.count, original.count)
    }

    func testSmallImagePassesThroughUnchanged() throws {
        let original = try makeJPEG(width: 400, height: 300)
        let originalEdge = try longEdge(of: original)

        let result = try XCTUnwrap(ImageDownsampler.downsampledJPEG(from: original, maxPixelSize: 2200))

        // Already within bounds: decoded dimensions must be unchanged,
        // regardless of whether the original bytes or a re-encode came back.
        let resultEdge = try longEdge(of: result)
        XCTAssertEqual(resultEdge, originalEdge)
    }

    func testGarbageDataReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        XCTAssertNil(ImageDownsampler.downsampledJPEG(from: garbage))
    }
}
