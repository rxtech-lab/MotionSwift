// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Updated by release preparation after signing and packaging the native binary.
let nativeReleaseTag = "v1.1.1"
let nativeReleaseChecksum = "31f3aafaf5fb6fd4de33e16fa8fd5533f579411d03336e20fa84b90246cf7016"
let localNative = "native/MotionSwiftNative.xcframework"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let nativeReleaseURL = "https://github.com/rxtech-lab/MotionSwift/releases/download/\(nativeReleaseTag)/"
  + "MotionSwiftNative-\(nativeReleaseTag).xcframework.zip"
let nativeTarget: Target = FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(localNative).path)
  ? .binaryTarget(name: "MotionSwiftNative", path: localNative)
  : .binaryTarget(name: "MotionSwiftNative",
                  url: nativeReleaseURL,
                  checksum: nativeReleaseChecksum)

/// Targets that spawn native tools (tsgo, esbuild, ffmpeg) exist only on macOS. iOS and iPadOS
/// compile with the portable JavaScriptCore compiler and the precompiled vendor graph.
let macOnly = TargetDependencyCondition.when(platforms: [.macOS])

let package = Package(
  name: "MotionSwift",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "MotionSwift", targets: [
      "MotionPortable", "MotionRuntime", "MotionRender", "MotionEncode", "MotionSwiftUI", "MotionEditor",
    ]),
    // macOS only: bundles native tsgo/esbuild executables (~31 MB) and spawns them.
    .library(name: "MotionCompiler", targets: ["MotionCompiler"]),
    .library(name: "MotionSwiftUI", targets: ["MotionSwiftUI"]),
    .library(name: "MotionEditor", targets: ["MotionEditor"]),
    .executable(name: "motionswift", targets: ["motionswift-cli"]),
    .executable(name: "motionswift-showcase", targets: ["motionswift-showcase"]),
  ],
  dependencies: [
    .package(url: "https://github.com/facebook/yoga.git", exact: "3.2.2"),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
  ],
  targets: [
    .systemLibrary(name: "CSkia"),
    // Local development uses `make native`; clean consumers download the signed release artifact.
    nativeTarget,
    .target(name: "MotionCore"),
    .target(name: "SkiaKit", dependencies: ["CSkia", "MotionCore", "MotionSwiftNative"], linkerSettings: [
      .linkedLibrary("c++"), .linkedFramework("CoreText"), .linkedFramework("CoreGraphics"),
      .linkedFramework("ImageIO"), .linkedFramework("CoreServices", .when(platforms: [.macOS])),
      .linkedFramework("UIKit", .when(platforms: [.iOS])),
      .linkedFramework("Metal"), .linkedFramework("QuartzCore"), .linkedFramework("Foundation"),
    ]),
    .target(name: "MotionLayout", dependencies: ["MotionCore", "SkiaKit", .product(name: "yoga", package: "yoga")]),
    // iOS bundles reserve a top-level "Resources" directory, so portable targets use "JavaScript".
    .target(name: "MotionPortable", dependencies: ["MotionCore"], resources: [.copy("JavaScript")]),
    .target(name: "MotionCompiler", dependencies: ["MotionCore", "MotionPortable"], resources: [.copy("Resources")]),
    .target(name: "MotionRuntime", dependencies: ["MotionCore"], resources: [.copy("JavaScript")]),
    .target(name: "MotionRender", dependencies: ["MotionCore", "MotionRuntime", "SkiaKit", "MotionLayout"]),
    .target(name: "MotionEncode", dependencies: ["MotionCore"]),
    .target(name: "MotionSwiftUI", dependencies: [
      "MotionCore", "MotionPortable", .target(name: "MotionCompiler", condition: macOnly), "MotionRuntime",
      "MotionRender", "SkiaKit",
    ]),
    .target(name: "MotionEditor", dependencies: [
      "MotionCore", "MotionPortable", "MotionRender", "MotionSwiftUI",
    ]),
    .executableTarget(
      name: "motionswift-showcase",
      dependencies: [
        "MotionCore", "MotionRender", "MotionEncode", "MotionSwiftUI", "MotionEditor", "MotionPortable",
        .product(name: "Sparkle", package: "Sparkle", condition: macOnly),
      ],
      path: "Examples/MotionShowcase",
      resources: [
        .copy("Media"), .copy("Designs"), .copy("Railway"), .copy("MapStudio"), .copy("Film"),
        .copy("OpenSource"),
      ],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"],
                     .when(platforms: [.macOS])),
      ]),
    .executableTarget(name: "motionswift-cli", dependencies: [
      "MotionCompiler", "MotionPortable", "MotionRuntime", "MotionRender", "MotionEncode",
    ]),
    .testTarget(name: "MotionSwiftTests", dependencies: [
      "MotionCompiler", "MotionPortable", "MotionRuntime", "MotionRender", "MotionEncode", "MotionSwiftUI",
      "MotionEditor",
    ], path: "tests/Swift"),
    .testTarget(name: "MotionShowcaseTests", dependencies: [
      "motionswift-showcase", "MotionSwiftUI", "MotionCore", "MotionEditor",
    ], path: "tests/Showcase"),
  ]
)
