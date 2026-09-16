@preconcurrency import CoreGraphics
@preconcurrency import ImageIO
import XCTest
@testable import ShotCore

@MainActor
final class ImagePipelineTests: XCTestCase {
    func testRotatedJPEGIsDecodedAndInspectedAtOrientedDimensions() throws {
        let url = try writeJPEG(width: 2, height: 3, orientation: .right)
        defer { try? FileManager.default.removeItem(at: url) }

        let inspected = try XCTUnwrap(MediaInspector.inspectImage(at: url))
        let decoded = try ImageDecoder.decode(at: url)
        var configuration = ShotdConfiguration()
        configuration.background = .init(type: .solid, color: "#000000")
        let rendered = try ImageRenderer.render(
            source: decoded,
            media: inspected,
            configuration: configuration,
            background: .solid(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        )

        XCTAssertEqual(inspected.dimensions, try MediaDimensions(width: 3, height: 2))
        XCTAssertEqual(decoded.width, 3)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(rendered.width, 83)
        XCTAssertEqual(rendered.height, 82)
    }

    func testDefaultCompressionUsesJPEGAndHEICWhenAvailable() throws {
        let image = try testImage()
        let registry = EncoderRegistry()
        XCTAssertNil(ShotdConfiguration().image.compression)

        var jpeg = ImageConfiguration(format: .jpeg)
        XCTAssertEqual(try registry.encode(image, configuration: jpeg).format.fileExtension, "jpg")

        if registry.codecs().first(where: { $0.format == .heic })?.available == true {
            jpeg.format = .heic
            XCTAssertEqual(try registry.encode(image, configuration: jpeg).format.fileExtension, "heic")
        }
    }

    func testExplicitLosslessJPEGFallsBackToPNG() throws {
        var configuration = ImageConfiguration(format: .jpeg)
        configuration.compression = .lossless
        let encoded = try EncoderRegistry().encode(try testImage(), configuration: configuration)
        XCTAssertEqual(encoded.format.fileExtension, "png")
    }

    func testPreserveTIFFProducesTIFFBytes() throws {
        var configuration = ImageConfiguration(format: .preserve)
        configuration.compression = nil
        let encoded = try EncoderRegistry().encode(try testImage(), configuration: configuration, sourceTypeIdentifier: "public.tiff")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(encoded.data as CFData, nil))

        XCTAssertEqual(encoded.format.fileExtension, "tif")
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.tiff")
    }

    private func writeJPEG(width: Int, height: Int, orientation: CGImagePropertyOrientation) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "shotd-orientation-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw ShotdError.processing("Unable to create JPEG test destination.")
        }
        CGImageDestinationAddImage(destination, try testImage(width: width, height: height), [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ShotdError.processing("Unable to create JPEG test image.")
        }
        return url
    }

    private func testImage(width: Int = 2, height: Int = 2) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ShotdError.processing("Unable to create test image.")
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw ShotdError.processing("Unable to create test CGImage.")
        }
        return image
    }
}
