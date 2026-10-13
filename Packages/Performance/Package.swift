// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Performance",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerformanceDomain", targets: ["PerformanceDomain"]),
        .library(name: "PerformanceCore", targets: ["PerformanceCore"]),
        .library(name: "PerformanceMacPlatform", targets: ["PerformanceMacPlatform"])
    ],
    targets: [
        .target(name: "PerformanceDomain"),
        .target(name: "PerformanceCore", dependencies: ["PerformanceDomain"]),
        .target(name: "PerformanceMacPlatform", dependencies: ["PerformanceDomain"]),
        .testTarget(name: "PerformanceCoreTests", dependencies: ["PerformanceDomain", "PerformanceCore"]),
        .testTarget(name: "PerformancePlatformTests", dependencies: ["PerformanceMacPlatform"])
    ]
)
