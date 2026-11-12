// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Xcode does not inherit the shell's PKG_CONFIG_PATH. Resolve the locally built
// archive relative to this manifest so both Xcode and SwiftPM can link it.
let nativeLibraryPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("native/target/release").path

let package = Package(
    name: "MotionSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MotionSwift", targets: [
            "MotionCompiler", "MotionRuntime", "MotionRender", "MotionEncode", "MotionSwiftUI",
        ]),
        .library(name: "MotionSwiftUI", targets: ["MotionSwiftUI"]),
        .executable(name: "motionswift", targets: ["motionswift-cli"]),
        .executable(name: "motionswift-showcase", targets: ["motionswift-showcase"]),
    ],
    dependencies: [.package(url: "https://github.com/facebook/yoga.git", exact: "3.2.1")],
    targets: [
        .systemLibrary(name: "CSkia"),
        .target(name: "MotionCore"),
        .target(name: "SkiaKit", dependencies: ["CSkia", "MotionCore"], linkerSettings: [
            .unsafeFlags(["-L", nativeLibraryPath]),
            .linkedLibrary("c++"), .linkedFramework("CoreText"), .linkedFramework("CoreGraphics"),
            .linkedFramework("ImageIO"), .linkedFramework("CoreServices"),
            .linkedFramework("Metal"), .linkedFramework("QuartzCore"), .linkedFramework("Foundation"),
        ]),
        .target(name: "MotionLayout", dependencies: ["MotionCore", .product(name: "yoga", package: "yoga")]),
        .target(name: "MotionCompiler", dependencies: ["MotionCore"], resources: [.copy("Resources")]),
        .target(name: "MotionRuntime", dependencies: ["MotionCore"], resources: [.copy("Resources")]),
        .target(name: "MotionRender", dependencies: ["MotionCore", "MotionRuntime", "SkiaKit", "MotionLayout"]),
        .target(name: "MotionEncode", dependencies: ["MotionCore"]),
        .target(name: "MotionSwiftUI", dependencies: [
            "MotionCore", "MotionCompiler", "MotionRuntime", "MotionRender", "SkiaKit",
        ]),
        .executableTarget(name: "motionswift-showcase", dependencies: [
            "MotionCore", "MotionRender", "MotionEncode", "MotionSwiftUI",
        ], path: "Examples/MotionShowcase"),
        .executableTarget(name: "motionswift-cli", dependencies: [
            "MotionCompiler", "MotionRuntime", "MotionRender", "MotionEncode",
        ]),
        .testTarget(name: "MotionSwiftTests", dependencies: [
            "MotionCompiler", "MotionRuntime", "MotionRender", "MotionEncode", "MotionSwiftUI",
        ], path: "tests/Swift"),
        .testTarget(name: "MotionShowcaseTests", dependencies: [
            "motionswift-showcase", "MotionSwiftUI", "MotionCore",
        ], path: "tests/Showcase"),
    ]
)
