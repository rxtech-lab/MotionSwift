// swift-tools-version: 6.0
import PackageDescription

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
    .package(url: "https://github.com/facebook/yoga.git", exact: "3.2.1"),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
  ],
  targets: [
    .systemLibrary(name: "CSkia"),
    // Built by `make native` (macOS) or `make native-ios` (adds iOS device and simulator slices).
    .binaryTarget(name: "MotionSwiftNative", path: "native/MotionSwiftNative.xcframework"),
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
    .executableTarget(name: "motionswift-showcase", dependencies: [
      "MotionCore", "MotionRender", "MotionEncode", "MotionSwiftUI", "MotionEditor", "MotionPortable",
      .product(name: "Sparkle", package: "Sparkle", condition: macOnly),
    ], path: "Examples/MotionShowcase", resources: [.copy("Media"), .copy("Designs"), .copy("Railway"), .copy("MapStudio"), .copy("Film")],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"],
        .when(platforms: [.macOS]))]),
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
