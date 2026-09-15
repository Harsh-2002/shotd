import CShotCodecs
@preconcurrency import CoreGraphics
import Foundation

@MainActor
enum BundledCodecs {
    static func avifLosslessRoundTripIsExact() -> Bool {
        let source = PixelBuffer(
            bytes: [0, 0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 255, 17, 129, 241, 255],
            width: 2,
            height: 2,
            bytesPerRow: 8
        )
        do {
            var output: UnsafeMutablePointer<UInt8>?
            var outputSize = 0
            let encoded = source.bytes.withUnsafeBytes { bytes in
                shotd_avif_encode_rgba(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 2, 2, 8, 1, 100, &output, &outputSize)
            }
            let data = try takeOutput(output, size: outputSize, succeeded: encoded, format: "AVIF")
            let decoded = try decodeAVIF(data)
            return decoded == source
        } catch {
            return false
        }
    }
    static func encodeWebP(_ image: CGImage, lossless: Bool, quality: Int) throws -> Data {
        let pixels = try rgbaPixels(image)
        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let succeeded = pixels.bytes.withUnsafeBytes { bytes in
            shotd_webp_encode_rgba(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(pixels.width), Int32(pixels.height), Int32(pixels.bytesPerRow), lossless ? 1 : 0, Float(quality), &output, &outputSize)
        }
        return try takeOutput(output, size: outputSize, succeeded: succeeded, format: "WebP")
    }

    static func encodeAVIF(_ image: CGImage, lossless: Bool, quality: Int) throws -> Data {
        let pixels = try rgbaPixels(image)
        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let succeeded = pixels.bytes.withUnsafeBytes { bytes in
            shotd_avif_encode_rgba(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(pixels.width), Int32(pixels.height), Int32(pixels.bytesPerRow), lossless ? 1 : 0, Int32(quality), &output, &outputSize)
        }
        return try takeOutput(output, size: outputSize, succeeded: succeeded, format: "AVIF")
    }

    static func decodeWebP(_ data: Data) throws -> PixelBuffer {
        var output: UnsafeMutablePointer<UInt8>?
        var width: Int32 = 0
        var height: Int32 = 0
        let succeeded = data.withUnsafeBytes { bytes in
            shotd_webp_decode_rgba(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &output, &width, &height)
        }
        return try takePixels(output, width: Int(width), height: Int(height), succeeded: succeeded, format: "WebP")
    }

    static func decodeAVIF(_ data: Data) throws -> PixelBuffer {
        var output: UnsafeMutablePointer<UInt8>?
        var width: Int32 = 0
        var height: Int32 = 0
        let succeeded = data.withUnsafeBytes { bytes in
            shotd_avif_decode_rgba(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &output, &width, &height)
        }
        return try takePixels(output, width: Int(width), height: Int(height), succeeded: succeeded, format: "AVIF")
    }

    private static func rgbaPixels(_ image: CGImage) throws -> PixelBuffer {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ShotdError.processing("Unable to normalize pixels for codec encoding.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelBuffer(bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    private static func takeOutput(_ output: UnsafeMutablePointer<UInt8>?, size: Int, succeeded: Int32, format: String) throws -> Data {
        guard succeeded != 0, let output, size > 0 else { throw ShotdError.processing("Bundled \(format) encoding failed.") }
        defer { shotd_codec_free(output) }
        return Data(bytes: output, count: size)
    }

    private static func takePixels(_ output: UnsafeMutablePointer<UInt8>?, width: Int, height: Int, succeeded: Int32, format: String) throws -> PixelBuffer {
        guard succeeded != 0, let output, width > 0, height > 0 else { throw ShotdError.processing("Bundled \(format) decoding failed.") }
        defer { shotd_codec_free(output) }
        return PixelBuffer(bytes: Array(UnsafeBufferPointer(start: output, count: width * height * 4)), width: width, height: height, bytesPerRow: width * 4)
    }
}

struct PixelBuffer: Sendable, Equatable {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

@MainActor
struct BundledWebPEncoder: ImageEncoding {
    let availability = CodecAvailability(format: .webp, available: true, lossless: true, backend: .bundledWebP)

    func encode(_ image: CGImage, configuration: ImageConfiguration) throws -> EncodedImage {
        let lossless = configuration.compression != .lossy
        return EncodedImage(data: try BundledCodecs.encodeWebP(image, lossless: lossless, quality: configuration.quality ?? 90), format: .image(for: .webp)!)
    }
}

@MainActor
struct BundledAVIFEncoder: ImageEncoding {
    let availability: CodecAvailability

    init(losslessVerified: Bool) {
        self.availability = CodecAvailability(format: .avif, available: true, lossless: losslessVerified, backend: .bundledAVIF)
    }

    func encode(_ image: CGImage, configuration: ImageConfiguration) throws -> EncodedImage {
        let lossless = configuration.compression != .lossy
        return EncodedImage(data: try BundledCodecs.encodeAVIF(image, lossless: lossless, quality: configuration.quality ?? 85), format: .image(for: .avif)!)
    }
}
