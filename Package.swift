// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shotd",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shotd", targets: ["shotd"]),
        .library(name: "ShotCore", targets: ["ShotCore"])
    ],
    targets: [
        .executableTarget(
            name: "shotd",
            dependencies: ["ShotCore"]
        ),
        .target(
            name: "ShotCore",
            dependencies: ["CShotCodecs"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Security"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .target(
            name: "CShotCodecs",
            path: "Sources/CShotCodecs",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../CodecKit/WebP/src"),
                .headerSearchPath("../../CodecKit/AVIF/include")
            ],
            linkerSettings: [
                .unsafeFlags(["-LCodecKit/build-webp", "-LCodecKit/build-avif", "-lwebp", "-lsharpyuv", "-lavif"])
            ]
        ),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"])
    ]
)
