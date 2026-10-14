import Foundation
import Testing
@testable import CleanerExtras

/// 真实临时夹具：创建真文件/硬链接/符号链接/无权限项；cleanup 先恢复权限再删除。
final class DupFixture {
    let root: URL
    private var denied: [URL] = []
    init() throws {
        // 用 finder 同款 realpath 规范化（/var→/private/var），夹具路径才能与报告逐字比较。
        let base = DuplicateFinder.canonicalPath(FileManager.default.temporaryDirectory.path)
        root = URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("lmc-dup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    /// 可复现的填充模式：按 seed 生成，便于构造“同尺寸不同内容”。
    func pattern(_ count: Int, seed: UInt8) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: Int(seed) &* 131 &+ $0 &* 7) })
    }
    @discardableResult func file(_ relative: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
    @discardableResult func dir(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func deny(_ url: URL) throws { try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path); denied.append(url) }
    func cleanup() {
        for url in denied { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        try? FileManager.default.removeItem(at: root)
    }
}

/// 小阈值配置：minBytes=16 让 1000B 夹具可被收集；headBytes=256 与 chunkBytes=128 迫使全量哈希走多块。
private let testConfig = DuplicateFinder.Config(minBytes: 16, headBytes: 256, chunkBytes: 128)

@Test func funnelSeparatesSizeHeadAndFullContent() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    let base1 = fx.pattern(1000, seed: 1), base2 = fx.pattern(1000, seed: 2), base3 = fx.pattern(1000, seed: 3)
    let a1 = try fx.file("a/A1.bin", base1), a2 = try fx.file("b/deep/A2.bin", base1)        // 真重复
    var tailDiff = base2; tailDiff[600] ^= 0xff
    try fx.file("B1.bin", base2); try fx.file("B2.bin", tailDiff)                           // 同尺寸、同头 256B、第 600B 不同 → 必须被全量哈希分开
    var headDiff = base3; headDiff[0] ^= 0xff
    try fx.file("C1.bin", base3); try fx.file("C2.bin", headDiff)                           // 同尺寸、头部即不同 → 第三段淘汰
    try fx.file("D.bin", fx.pattern(999, seed: 4))                                          // 唯一尺寸 → 第二段淘汰
    try fx.file("tiny1", Data(repeating: 9, count: 8)); try fx.file("tiny2", Data(repeating: 9, count: 8)) // < minBytes 不扫

    let report = await DuplicateFinder(config: testConfig).scan(root: fx.root)
    #expect(report.groups.count == 1)
    #expect(report.groups.first?.files.map(\.path) == [a1.path, a2.path].sorted())
    #expect(report.groups.first?.size == 1000)
    #expect(report.groups.first?.wastedBytes == 1000)
    #expect(report.groups.first?.hardLinked == false)
    #expect(report.wastedBytesTotal == 1000)
    #expect(report.scannedFiles == 7)
    #expect(report.scannedBytes == 1000 * 6 + 999)
    #expect(report.skipped.isEmpty)
    #expect(!report.incomplete)
    #expect(report.minBytes == 16)
    #expect(report.rootPath == fx.root.path) // 报告根与文件路径同为规范化形式
}

@Test func unreadableFilesAreSkippedAndNeverJudgedDuplicate() async throws {
    guard geteuid() != 0 else { return } // root 无视权限位，本用例不成立
    let fx = try DupFixture(); defer { fx.cleanup() }
    let same = fx.pattern(1000, seed: 7)
    let p1 = try fx.file("P1.bin", same); try fx.file("P2.bin", same); let p3 = try fx.file("P3.bin", same)
    try fx.deny(p1); try fx.deny(p3) // 两个不可读 + 一个可读：内容相同也不得成组（未读到哈希永不判重）
    let deniedDir = try fx.dir("locked"); try fx.file("locked/x.bin", same); try fx.deny(deniedDir)

    let report = await DuplicateFinder(config: testConfig).scan(root: fx.root)
    #expect(report.groups.isEmpty)
    #expect(report.skipped.contains { $0.path == p1.path && $0.reason.hasPrefix("头部读取失败") })
    #expect(report.skipped.contains { $0.path == p3.path && $0.reason.hasPrefix("头部读取失败") })
    #expect(report.skipped.contains { $0.path == deniedDir.path && $0.reason.hasPrefix("枚举失败") })
    #expect(report.scannedFiles == 3) // 三个文件都被收集（lstat 可读），只是内容读取失败
    #expect(!report.incomplete)       // 单项失败不等于整体取消；但必须在 skipped 暴露
}

@Test func hardLinkGroupsAreAnnotated() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    let same = fx.pattern(1000, seed: 3)
    let h1 = try fx.file("H1.bin", same)
    let h2 = fx.root.appendingPathComponent("sub/H2.bin")
    try FileManager.default.createDirectory(at: h2.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.linkItem(at: h1, to: h2)                       // 同 inode 第二条路径
    let h3 = try fx.file("H3.bin", same)                                    // 真实副本

    let report = await DuplicateFinder(config: testConfig).scan(root: fx.root)
    #expect(report.groups.count == 1)
    let g = try #require(report.groups.first)
    #expect(g.files.count == 3)
    #expect(g.hardLinked)
    #expect(g.distinctObjects == 2)                                         // 两个真实对象：{H1,H2} 与 H3
    #expect(g.wastedBytes == 2000)                                          // 名义值 size×(n-1)，UI 须配合 hardLinked 标注
    let byPath = Dictionary(uniqueKeysWithValues: g.files.map { ($0.path, $0) })
    #expect(byPath[h1.path]?.linkCount == 2); #expect(byPath[h2.path]?.linkCount == 2); #expect(byPath[h3.path]?.linkCount == 1)
    #expect(byPath[h1.path]?.objectKey == byPath[h2.path]?.objectKey)
    #expect(byPath[h1.path]?.objectKey != byPath[h3.path]?.objectKey)
}

@Test func symlinksAndRepositoryInternalsAreNotCollected() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    let same = fx.pattern(1000, seed: 4)
    let real = try fx.file("R.bin", same)
    try FileManager.default.createSymbolicLink(at: fx.root.appendingPathComponent("S.bin"), withDestinationURL: real) // 文件符号链接
    try FileManager.default.createSymbolicLink(at: fx.root.appendingPathComponent("loop"), withDestinationURL: fx.root) // 目录符号链接环
    try fx.file(".git/objects/aa", same); try fx.file(".git/objects/bb", same)                   // 仓库内部不判重
    try fx.file("proj/.svn/pristine/x", same); try fx.file("proj/.svn/pristine/y", same)

    let report = await DuplicateFinder(config: testConfig).scan(root: fx.root)
    #expect(report.groups.isEmpty)
    #expect(report.scannedFiles == 1)     // 仅 R.bin；符号链接与 .git/.svn 后代全部不收集
    #expect(report.scannedBytes == 1000)
    #expect(report.skipped.isEmpty)
    #expect(!report.incomplete)
}

@Test func progressStreamReportsPhasesInOrderAndFinalGroupCount() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    let same = fx.pattern(1000, seed: 5)
    try fx.file("X1.bin", same); try fx.file("X2.bin", same)
    let (stream, task) = await DuplicateFinder(config: testConfig).scanStreaming(root: fx.root)
    var phases: [DuplicateProgress.Phase] = []
    var last: DuplicateProgress?
    for await p in stream { if phases.last != p.phase { phases.append(p.phase) }; last = p }
    let report = await task.value
    #expect(phases == [.enumerating, .hashing, .hashConfirming])   // 阶段切换事件不受节流吞掉
    #expect(last?.phase == .hashConfirming)
    #expect(last?.completedGroups == 1)
    #expect(last?.currentPath == nil)                               // 收尾事件
    #expect(last?.phaseTotalBytes == 2000)                          // 全量阶段总量 = 两个 1000B 文件
    #expect(last?.scannedBytes == 2000)
    #expect(report.groups.count == 1)
}

@Test func cancellationReturnsPartialIncompleteReportAndFinishesStream() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    for i in 0..<1200 {
        var d = Data(repeating: 0, count: 32); d[0] = UInt8(i & 0xff); d[1] = UInt8((i >> 8) & 0xff)
        try fx.file("many/f\(i).bin", d)                              // 内容互异：不会成组，只用来拉长枚举
    }
    let (stream, task) = await DuplicateFinder(config: testConfig).scanStreaming(root: fx.root)
    task.cancel()                                                     // 立即取消：1200 次 lstat 远长于这一行的耗时
    var events = 0
    for await _ in stream { events += 1 }                             // 流必须正常收尾，不能悬挂
    let report = await task.value
    #expect(report.incomplete)
    #expect(report.groups.isEmpty)
    #expect(report.scannedFiles < 1200)
    #expect(events >= 1)                                              // 至少有收尾事件
}

@Test func missingOrUnreadableRootIsReportedIncomplete() async throws {
    let missing = await DuplicateFinder(config: testConfig).scan(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
    #expect(missing.incomplete)
    #expect(missing.groups.isEmpty && missing.scannedFiles == 0)
    #expect(missing.skipped.first?.reason.contains("扫描根") == true)
    // 根是普通文件而非目录
    let fx = try DupFixture(); defer { fx.cleanup() }
    let file = try fx.file("plain.bin", fx.pattern(100, seed: 1))
    let notDir = await DuplicateFinder(config: testConfig).scan(root: file)
    #expect(notDir.incomplete && notDir.groups.isEmpty)
}

@Test func reportEncodesSixtyFourBitValuesAsDecimalStringsAndRoundTrips() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    let same = fx.pattern(1000, seed: 6)
    try fx.file("J1.bin", same); try fx.file("J2.bin", same)
    let report = await DuplicateFinder(config: testConfig).scan(root: fx.root)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(report)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["scannedBytes"] as? String == "2000")
    #expect(obj["wastedBytesTotal"] as? String == "1000")
    #expect(obj["minBytes"] as? String == "16")
    let groups = try #require(obj["groups"] as? [[String: Any]])
    #expect(groups.first?["size"] as? String == "1000")
    #expect(groups.first?["wastedBytes"] as? String == "1000")
    #expect(groups.first?["hardLinked"] as? Bool == false)
    let files = try #require(groups.first?["files"] as? [[String: Any]])
    #expect(files.first?["inode"] is String); #expect(files.first?["device"] is String); #expect(files.first?["linkCount"] as? String == "1")

    let decoded = try JSONDecoder().decode(DuplicateReport.self, from: data)
    #expect(decoded.groups == report.groups)
    #expect(decoded.skipped == report.skipped)
    #expect(decoded.scannedFiles == report.scannedFiles && decoded.scannedBytes == report.scannedBytes)
    #expect(decoded.rootPath == report.rootPath && decoded.minBytes == report.minBytes && decoded.incomplete == report.incomplete)
    // 数值型（非字符串）字段必须被拒绝：解码 fail-closed
    var tampered = obj; tampered["scannedBytes"] = 2000
    #expect(throws: (any Error).self) { try JSONDecoder().decode(DuplicateReport.self, from: JSONSerialization.data(withJSONObject: tampered)) }
}

@Test func groupsAreSortedByWastedBytesDescending() async throws {
    let fx = try DupFixture(); defer { fx.cleanup() }
    let small = fx.pattern(600, seed: 8), big = fx.pattern(900, seed: 9)
    try fx.file("s1", small); try fx.file("s2", small); try fx.file("s3", small)   // 浪费 1200
    try fx.file("b1", big); try fx.file("b2", big)                                 // 浪费 900
    let report = await DuplicateFinder(config: testConfig).scan(root: fx.root)
    #expect(report.groups.map(\.wastedBytes) == [1200, 900])
    #expect(report.groups.map(\.files.count) == [3, 2])
    #expect(report.wastedBytesTotal == 2100)
}

/// opt-in 真机冒烟：LMC_DUP_REAL_ROOT=<目录> 时用默认配置（1 MiB 阈值）扫描并打印摘要；默认跳过，不影响 CI 时长。
@Test func realRootSmokeWhenOptedIn() async throws {
    guard let root = ProcessInfo.processInfo.environment["LMC_DUP_REAL_ROOT"], !root.isEmpty else { return }
    let clock = ContinuousClock(); let started = clock.now
    let report = await DuplicateFinder().scan(root: URL(fileURLWithPath: root, isDirectory: true))
    let elapsed = clock.now - started
    print("[LMC_DUP_REAL_ROOT] root=\(report.rootPath) files=\(report.scannedFiles) bytes=\(report.scannedBytes) groups=\(report.groups.count) wasted=\(report.wastedBytesTotal) skipped=\(report.skipped.count) incomplete=\(report.incomplete) hardLinkedGroups=\(report.groups.filter(\.hardLinked).count) elapsed=\(elapsed)")
    for g in report.groups.prefix(5) { print("  group size=\(g.size) n=\(g.files.count) wasted=\(g.wastedBytes) hardLinked=\(g.hardLinked) first=\(g.files[0].path)") }
    #expect(!report.incomplete)
    // 不变量：每组 ≥2 文件、组内尺寸一致、浪费合计可对账。
    #expect(report.groups.allSatisfy { g in g.files.count >= 2 && g.files.allSatisfy { $0.size == g.size } })
    #expect(report.wastedBytesTotal == report.groups.reduce(0) { $0 + $1.wastedBytes })
}
