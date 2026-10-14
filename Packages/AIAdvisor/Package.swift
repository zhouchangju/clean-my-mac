// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AIAdvisor", platforms: [.macOS(.v14)], products: [
.library(name: "AIAdvisorCore", targets: ["AIAdvisorCore"]),
.library(name: "AIAdvisorUI", targets: ["AIAdvisorUI"])
], targets: [
.target(name: "AIAdvisorCore"),
.target(name: "AIAdvisorUI", dependencies: ["AIAdvisorCore"]),
.testTarget(name: "AIAdvisorCoreTests", dependencies: ["AIAdvisorCore"])
])
