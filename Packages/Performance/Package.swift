// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Performance",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerformanceDomain", targets: ["PerformanceDomain"]),
        .library(name: "PerformanceCore", targets: ["PerformanceCore"]),
        .library(name: "PerformanceMacPlatform", targets: ["PerformanceMacPlatform"]),
        .library(name: "PerformanceUI", targets: ["PerformanceUI"]),
        .executable(name: "performance-preview", targets: ["PerformancePreview"])
    ],
    targets: [
        .target(name: "PerformanceDomain"),
        .target(name: "PerformanceCore", dependencies: ["PerformanceDomain"]),
        .target(name: "PerformanceMacPlatform", dependencies: ["PerformanceDomain"]),
        .target(name: "PerformanceUI", dependencies: ["PerformanceDomain", "PerformanceCore", "PerformanceMacPlatform"]),
        .executableTarget(name: "PerformancePreview", dependencies: ["PerformanceUI", "PerformanceDomain", "PerformanceCore", "PerformanceMacPlatform"]),
        .testTarget(name: "PerformanceCoreTests", dependencies: ["PerformanceDomain", "PerformanceCore"]),
        .testTarget(name: "PerformancePlatformTests", dependencies: ["PerformanceMacPlatform", "PerformanceCore"])
    ]
)
