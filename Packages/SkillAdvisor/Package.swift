// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SkillAdvisor", platforms: [.macOS(.v14)], products: [
.library(name: "SkillAdvisorCore", targets: ["SkillAdvisorCore"]),
.library(name: "SkillAdvisorUI", targets: ["SkillAdvisorUI"])
], targets: [
.target(name: "SkillAdvisorCore"),
.target(name: "SkillAdvisorUI", dependencies: ["SkillAdvisorCore"]),
.testTarget(name: "SkillAdvisorCoreTests", dependencies: ["SkillAdvisorCore"],
    resources: [.copy("Fixtures")])
])
