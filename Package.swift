// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MotionSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MotionSwift", targets: ["MotionCompiler", "MotionRuntime", "MotionRender", "MotionEncode"]),
        .executable(name: "motionswift", targets: ["motionswift-cli"]),
    ],
    dependencies: [.package(url: "https://github.com/facebook/yoga.git", exact: "3.2.1")],
    targets: [
        .systemLibrary(name: "CSkia", pkgConfig: "motionswift-skia"),
        .target(name: "MotionCore"),
        .target(name: "SkiaKit", dependencies: ["CSkia", "MotionCore"], linkerSettings: [
            .linkedLibrary("c++"), .linkedFramework("CoreText"), .linkedFramework("CoreGraphics"),
            .linkedFramework("ImageIO"), .linkedFramework("CoreServices"),
        ]),
        .target(name: "MotionLayout", dependencies: ["MotionCore", .product(name: "yoga", package: "yoga")]),
        .target(name: "MotionCompiler", dependencies: ["MotionCore"]),
        .target(name: "MotionRuntime", dependencies: ["MotionCore"], resources: [.copy("Resources")]),
        .target(name: "MotionRender", dependencies: ["MotionCore", "MotionRuntime", "SkiaKit", "MotionLayout"]),
        .target(name: "MotionEncode", dependencies: ["MotionCore"]),
        .executableTarget(name: "motionswift-cli", dependencies: [
            "MotionCompiler", "MotionRuntime", "MotionRender", "MotionEncode",
        ]),
        .testTarget(name: "MotionSwiftTests", dependencies: [
            "MotionCompiler", "MotionRuntime", "MotionRender", "MotionEncode",
        ], path: "tests/Swift"),
    ]
)
