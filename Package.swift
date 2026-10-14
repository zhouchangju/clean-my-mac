// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LocalMacCleaner", platforms: [.macOS(.v14)], products: [
.library(name: "CleanerDomain", targets: ["CleanerDomain"]),
.library(name: "CleanerCore", targets: ["CleanerCore"]),
.library(name: "CleanerMacPlatform", targets: ["CleanerMacPlatform"]),
.library(name: "CleanerExecution", targets: ["CleanerExecution"]),
.library(name: "CleanerViz", targets: ["CleanerViz"]),
.library(name: "CleanerExtras", targets: ["CleanerExtras"]),
.executable(name: "lmc", targets: ["CleanerCLI"])
], dependencies: [
.package(path: "Packages/AIAdvisor"),
.package(path: "Packages/SkillAdvisor")
], targets: [
.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
.target(name: "CleanerDomain"),
.target(name: "CleanerCore", dependencies: ["CleanerDomain"]),
.target(name: "CleanerMacPlatform", dependencies: ["CleanerDomain", "CleanerCore", "CSQLite"]),
.target(name: "CleanerExecution", dependencies: ["CleanerDomain"]),
.target(name: "CleanerViz"),
.target(name: "CleanerExtras"),
.executableTarget(name: "CleanerCLI", dependencies: ["CleanerMacPlatform", "CleanerCore", .product(name: "AIAdvisorCore", package: "AIAdvisor")]),
.target(name: "CleanerTestSupport", dependencies: ["CleanerDomain"], path: "TestSupport", exclude: ["plan-vector-v1.json", "plan-vector-v1.sha256"]),
.testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore", "CleanerTestSupport"]),
.testTarget(name: "CleanerPlatformTests", dependencies: ["CleanerMacPlatform", "CleanerTestSupport"]),
.testTarget(name: "CleanerExecutionTests", dependencies: ["CleanerExecution", "CleanerMacPlatform", "CleanerTestSupport"]),
.testTarget(name: "CleanerVizTests", dependencies: ["CleanerViz"]),
.testTarget(name: "CleanerExtrasTests", dependencies: ["CleanerExtras"])
])
