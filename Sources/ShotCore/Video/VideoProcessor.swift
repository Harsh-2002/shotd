@preconcurrency import AVFoundation
@preconcurrency import AudioToolbox
@preconcurrency import CoreGraphics
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import VideoToolbox

public struct ProcessedVideo: Sendable {
    public let outputURL: URL
    public let format: OutputFormat

    public init(outputURL: URL, format: OutputFormat) {
        self.outputURL = outputURL
        self.format = format
    }
}

// CGImage is immutable after creation; this wrapper transfers it from AppKit rendering to the video queue.
private struct VideoRenderPlan: @unchecked Sendable {
    let canvas: Canvas
    let background: CGImage
}

public final class VideoProcessor: Sendable {
    private let paths: ApplicationPaths

    public init(paths: ApplicationPaths) {
        self.paths = paths
    }

    public func process(sourceURL: URL, configuration: ShotdConfiguration) async throws -> ProcessedVideo {
        let info = try await MediaInspector.inspectVideo(at: sourceURL)
        let format = OutputFormat.video(for: configuration.video.format)
        let output = OutputManager(directory: paths.expandUserPath(configuration.output.directory).standardizedFileURL)
        try output.prepareDirectory()
        let destination = output.destination(for: sourceURL, format: format)
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let plan = try await MainActor.run { try Self.renderPlan(info: info, configuration: configuration, paths: paths) }
        do {
            try await encode(sourceURL: sourceURL, info: info, plan: plan, configuration: configuration, temporaryURL: temporary)
            try AtomicWriter.replaceFile(at: temporary, with: destination)
            if configuration.clipboard.video == .url {
                await MainActor.run { ClipboardService.publishVideo(outputURL: destination) }
            }
            return ProcessedVideo(outputURL: destination, format: format)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    @MainActor
    private static func renderPlan(info: VideoMediaInfo, configuration: ShotdConfiguration, paths: ApplicationPaths) throws -> VideoRenderPlan {
        // Reserve the largest configured frame around the source so the finished H.264 canvas stays within hardware limits.
        let h264SourceLimit = 4_096 - Int((configuration.layout.maximumPadding * 2).rounded(.up))
        let maximumDimension = configuration.video.codec == .h264 ? min(configuration.image.maximumDimension, h264SourceLimit) : configuration.image.maximumDimension
        let canvas = try LayoutEngine.canvas(for: info.dimensions, configuration: configuration.layout, maximumDimension: maximumDimension)
        let resolver = BackgroundResolver(paths: paths)
        let background = try resolver.resolve(configuration.background, sourceDimensions: info.dimensions)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: canvas.outputDimensions.width, height: canvas.outputDimensions.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw ShotdError.processing("Unable to create the video background canvas.")
        }
        background.draw(in: context, rect: CGRect(x: 0, y: 0, width: canvas.outputDimensions.width, height: canvas.outputDimensions.height))
        guard let image = context.makeImage() else { throw ShotdError.processing("Unable to finalize the video background canvas.") }
        return VideoRenderPlan(canvas: canvas, background: image)
    }

    private func encode(sourceURL: URL, info: VideoMediaInfo, plan: VideoRenderPlan, configuration: ShotdConfiguration, temporaryURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw ShotdError.processing("No video track found in \(sourceURL.lastPathComponent).") }
        let codec: AVVideoCodecType = configuration.video.codec == .h264 ? .h264 : .hevc

        let reader = try AVAssetReader(asset: asset)
        let videoComposition = try await orientedVideoComposition(track: track, dimensions: info.dimensions)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOutput.videoComposition = videoComposition
        guard reader.canAdd(videoOutput) else { throw ShotdError.processing("Unable to read the source video track.") }
        reader.add(videoOutput)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioOutput = configuration.video.preserveAudio && !audioTracks.isEmpty ? AVAssetReaderTrackOutput(track: audioTracks[0], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM
        ]) : nil
        if let audioOutput, reader.canAdd(audioOutput) { reader.add(audioOutput) }

        let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: configuration.video.format == .mp4 ? .mp4 : .mov)
        let dimensions = plan.canvas.outputDimensions
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height,
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(2_000_000, dimensions.width * dimensions.height * 5)]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: dimensions.width,
            kCVPixelBufferHeightKey as String: dimensions.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(videoInput) else { throw ShotdError.processing("Unable to write the output video track.") }
        writer.add(videoInput)

        let audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw ShotdError.processing("Unable to write the output audio track.") }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        guard reader.startReading() else {
            throw ShotdError.processing("Unable to start video reading: \(String(describing: reader.error))")
        }
        guard writer.startWriting() else {
            throw ShotdError.processing("Unable to start video writing: \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)
        if let audioOutput, let audioInput {
            while let sample = audioOutput.copyNextSampleBuffer() {
                try await waitUntilReady(audioInput, writer: writer)
                guard audioInput.append(sample) else { throw ShotdError.processing("Unable to append output audio.") }
            }
            audioInput.markAsFinished()
        }
        while let sample = videoOutput.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else {
                throw ShotdError.processing("Unable to obtain video frame buffers.")
            }
            var outputBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess, let outputBuffer else {
                throw ShotdError.processing("Unable to allocate an output video frame.")
            }
            try render(frame: buffer, into: outputBuffer, plan: plan)
            try await waitUntilReady(videoInput, writer: writer)
            guard adaptor.append(outputBuffer, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample)) else {
                throw ShotdError.processing("Unable to append an output video frame.")
            }
        }
        videoInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? ShotdError.processing("Video writer did not complete.")
        }
    }

    private func orientedVideoComposition(track: AVAssetTrack, dimensions: MediaDimensions) async throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let nominalRate = try await track.load(.nominalFrameRate)
        composition.frameDuration = nominalRate > 0 ? CMTime(value: 1, timescale: Int32(nominalRate.rounded())) : CMTime(value: 1, timescale: 30)
        let duration = try await track.load(.timeRange).duration
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(try await track.load(.preferredTransform), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }

    private func render(frame: CVPixelBuffer, into output: CVPixelBuffer, plan: VideoRenderPlan) throws {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(frame, .readOnly)
        }
        let sourceWidth = CVPixelBufferGetWidth(frame)
        let sourceHeight = CVPixelBufferGetHeight(frame)
        let outputWidth = CVPixelBufferGetWidth(output)
        let outputHeight = CVPixelBufferGetHeight(output)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let sourceContext = CGContext(data: CVPixelBufferGetBaseAddress(frame), width: sourceWidth, height: sourceHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(frame), space: colorSpace, bitmapInfo: bitmapInfo),
              let sourceImage = sourceContext.makeImage(),
              let outputContext = CGContext(data: CVPixelBufferGetBaseAddress(output), width: outputWidth, height: outputHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(output), space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw ShotdError.processing("Unable to render an output video frame.")
        }
        outputContext.draw(plan.background, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        outputContext.interpolationQuality = .high
        outputContext.draw(sourceImage, in: CGRect(x: CGFloat(plan.canvas.insets.left), y: CGFloat(plan.canvas.insets.bottom), width: CGFloat(plan.canvas.sourceDimensions.width), height: CGFloat(plan.canvas.sourceDimensions.height)))
    }

    private func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed || writer.status == .cancelled {
                throw writer.error ?? ShotdError.processing("Video writer stopped accepting media data.")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
