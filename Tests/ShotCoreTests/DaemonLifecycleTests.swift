@preconcurrency import CoreGraphics
@preconcurrency import ImageIO
import XCTest
@testable import ShotCore

@MainActor
final class DaemonLifecycleTests: XCTestCase {
    func testFirstEnrollmentBaselinesHistoryAndTrustedRestartRecoversDowntimeCapture() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        let watch = home.appending(path: "Screenshots", directoryHint: .isDirectory)
        let output = home.appending(path: "Output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try writePNG(to: watch.appending(path: "historical.png"))

        var configuration = ShotdConfiguration()
        configuration.watch.directory = watch.path
        configuration.output.directory = output.path
        configuration.background = .init(type: .solid, color: "#17191F")
        configuration.image.format = .png
        configuration.image.compression = .lossless
        configuration.clipboard.image = .disabled
        configuration.clipboard.video = .disabled
        try await ConfigLoader(paths: paths).write(configuration)

        let firstRun = Daemon(paths: paths)
        try await firstRun.start()
        defer { Task { await firstRun.stop() } }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(containsOutput(named: "historical", in: output))

        try writePNG(to: watch.appending(path: "live.png"))
        try await waitForOutput(named: "live", in: output)
        await firstRun.stop()

        try writePNG(to: watch.appending(path: "downtime.png"))
        let secondRun = Daemon(paths: paths)
        try await secondRun.start()
        defer { Task { await secondRun.stop() } }
        try await waitForOutput(named: "downtime", in: output)
        await secondRun.stop()

        XCTAssertFalse(containsOutput(named: "historical", in: output))
    }

    private func waitForOutput(named name: String, in directory: URL) async throws {
        for _ in 0..<100 {
            if containsOutput(named: name, in: directory) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for output named \(name)")
    }

    private func containsOutput(named name: String, in directory: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.lastPathComponent.hasPrefix("\(name)-") && $0.pathExtension == "png" }
    }

    private func writePNG(to url: URL) throws {
        guard let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ShotdError.processing("Unable to create a PNG test image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ShotdError.processing("Unable to write a PNG test image.")
        }
    }
}
