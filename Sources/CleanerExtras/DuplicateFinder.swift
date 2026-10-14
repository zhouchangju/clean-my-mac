import Foundation
import CryptoKit
import Darwin

/// 对外 JSON 约定：64 位数值用十进制字符串承载，避免 JS 消费者丢精度（与仓库 Decimal64 口径一致）。
func decodeDecimalUInt64<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> UInt64 {
    guard let s = try? c.decode(String.self, forKey: key), let v = UInt64(s) else {
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "期望十进制字符串形式的 UInt64")
    }
    return v
}

/// 重复文件报告中的一个文件。device/inode/linkCount 来自 lstat，用于硬链接标注。
public struct DuplicateFile: Sendable, Hashable, Codable {
    public let path: String
    public let size: UInt64
    public let device: UInt64
    public let inode: UInt64
    public let linkCount: UInt64
    public init(path: String, size: UInt64, device: UInt64, inode: UInt64, linkCount: UInt64) {
        self.path = path; self.size = size; self.device = device; self.inode = inode; self.linkCount = linkCount
    }
    /// 卷+inode 的对象键：同一对象的多条硬链接路径共享此键。
    public var objectKey: String { "\(device):\(inode)" }
    private enum CodingKeys: String, CodingKey { case path, size, device, inode, linkCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        size = try decodeDecimalUInt64(c, .size); device = try decodeDecimalUInt64(c, .device)
        inode = try decodeDecimalUInt64(c, .inode); linkCount = try decodeDecimalUInt64(c, .linkCount)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(String(size), forKey: .size); try c.encode(String(device), forKey: .device)
        try c.encode(String(inode), forKey: .inode); try c.encode(String(linkCount), forKey: .linkCount)
    }
}

/// 一组真重复（同尺寸、同全量 SHA-256）。浪费字节按 size×(n-1) 计；硬链接组该值为上界（见 hardLinked）。
public struct DuplicateGroup: Sendable, Hashable, Codable {
    public let size: UInt64
    public let files: [DuplicateFile]
    public init(size: UInt64, files: [DuplicateFile]) { self.size = size; self.files = files }
    /// 名义浪费 = size×(n-1)；硬链接组删其一并不释放空间，真实可释放取决于 distinctObjects。
    public var wastedBytes: UInt64 { size &* UInt64(max(files.count - 1, 0)) }
    /// 组内存在 nlink>1 的文件：删其一不释放空间，UI 必须标注，不能当普通重复误导。
    public var hardLinked: Bool { files.contains { $0.linkCount > 1 } }
    /// 去重后的文件系统对象数（同 dev+inode 计一次）。
    public var distinctObjects: Int { Set(files.map(\.objectKey)).count }
    private enum CodingKeys: String, CodingKey { case size, files, wastedBytes, hardLinked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try decodeDecimalUInt64(c, .size); files = try c.decode([DuplicateFile].self, forKey: .files)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(String(size), forKey: .size); try c.encode(files, forKey: .files)
        // 派生字段一并导出，方便外部消费者无需重算；解码时忽略。
        try c.encode(String(wastedBytes), forKey: .wastedBytes); try c.encode(hardLinked, forKey: .hardLinked)
    }
}

/// 读取/枚举失败项。fail-closed：进此表的文件永不参与判重。
public struct SkippedItem: Sendable, Hashable, Codable {
    public let path: String
    public let reason: String
    public init(path: String, reason: String) { self.path = path; self.reason = reason }
    private enum CodingKeys: String, CodingKey { case path, reason }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path); reason = try c.decode(String.self, forKey: .reason)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path); try c.encode(reason, forKey: .reason)
    }
}

/// 漏斗产出的完整报告。只读分析结果：不含任何动作语义。
public struct DuplicateReport: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let rootPath: String
    public let minBytes: UInt64
    public let scannedFiles: UInt64
    /// 枚举阶段收集（≥minBytes 的普通文件）的总字节。
    public let scannedBytes: UInt64
    public let groups: [DuplicateGroup]
    public let skipped: [SkippedItem]
    /// 取消或根枚举失败导致结果不完整。
    public let incomplete: Bool
    public let startedAt: Date
    public let finishedAt: Date
    public var wastedBytesTotal: UInt64 { groups.reduce(0) { $0 &+ $1.wastedBytes } }
    public init(schemaVersion: Int = 1, rootPath: String, minBytes: UInt64, scannedFiles: UInt64, scannedBytes: UInt64,
                groups: [DuplicateGroup], skipped: [SkippedItem], incomplete: Bool, startedAt: Date, finishedAt: Date) {
        self.schemaVersion = schemaVersion; self.rootPath = rootPath; self.minBytes = minBytes
        self.scannedFiles = scannedFiles; self.scannedBytes = scannedBytes; self.groups = groups
        self.skipped = skipped; self.incomplete = incomplete; self.startedAt = startedAt; self.finishedAt = finishedAt
    }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, rootPath, minBytes, scannedFiles, scannedBytes, groups, skipped, incomplete, startedAt, finishedAt, wastedBytesTotal
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); rootPath = try c.decode(String.self, forKey: .rootPath)
        minBytes = try decodeDecimalUInt64(c, .minBytes)
        scannedFiles = try decodeDecimalUInt64(c, .scannedFiles); scannedBytes = try decodeDecimalUInt64(c, .scannedBytes)
        groups = try c.decode([DuplicateGroup].self, forKey: .groups); skipped = try c.decode([SkippedItem].self, forKey: .skipped)
        incomplete = try c.decode(Bool.self, forKey: .incomplete)
        startedAt = try c.decode(Date.self, forKey: .startedAt); finishedAt = try c.decode(Date.self, forKey: .finishedAt)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(rootPath, forKey: .rootPath)
        try c.encode(String(minBytes), forKey: .minBytes)
        try c.encode(String(scannedFiles), forKey: .scannedFiles); try c.encode(String(scannedBytes), forKey: .scannedBytes)
        try c.encode(groups, forKey: .groups); try c.encode(skipped, forKey: .skipped)
        try c.encode(incomplete, forKey: .incomplete)
        try c.encode(startedAt, forKey: .startedAt); try c.encode(finishedAt, forKey: .finishedAt)
        try c.encode(String(wastedBytesTotal), forKey: .wastedBytesTotal) // 派生合计，解码时忽略
    }
}

/// 进度事件。scannedBytes 的含义随阶段变化：枚举=已收集文件总字节；头部哈希/全量确认=已实际读取字节。
public struct DuplicateProgress: Sendable, Equatable {
    public enum Phase: String, Sendable { case enumerating, hashing, hashConfirming }
    public let phase: Phase
    public let scannedBytes: UInt64
    /// 当前阶段已知总量（枚举阶段未知为 nil）；UI 可据此画确定性进度条。
    public let phaseTotalBytes: UInt64?
    public let currentPath: String?
    /// hashConfirming=已确认的真重复组数；hashing=头部哈希后的存活组数（随后续淘汰递减）。
    public let completedGroups: Int
    public init(phase: Phase, scannedBytes: UInt64, phaseTotalBytes: UInt64?, currentPath: String?, completedGroups: Int) {
        self.phase = phase; self.scannedBytes = scannedBytes; self.phaseTotalBytes = phaseTotalBytes
        self.currentPath = currentPath; self.completedGroups = completedGroups
    }
}

/// 三段漏斗重复文件扫描（清洁室实现公开算法思想：尺寸分桶→头部哈希→全量哈希）。
/// actor 只做入口与配置；重活在独立任务上跑，进度经 AsyncStream 推送，Task 取消即停并返回部分结果。
/// 只读红线：本类型没有任何删除/移动 API；读取失败的文件记入 skipped，绝不判重（fail-closed）。
public actor DuplicateFinder {
    /// 默认只关心 ≥1 MiB 的文件：小文件重复也省不出多少空间，却会显著放大哈希量。
    public static let defaultMinBytes: UInt64 = 1 << 20

    public struct Config: Sendable {
        public var minBytes: UInt64
        /// 头部哈希长度：64 KiB 足以让同尺寸不同内容的绝大多数文件在第二段分道。
        public var headBytes: Int
        /// 全量哈希流式块大小。
        public var chunkBytes: Int
        /// 命中任一路径段即不收集（不深入 .git/.svn 的内容判重）。
        public var skipAncestors: Set<String>
        public init(minBytes: UInt64 = DuplicateFinder.defaultMinBytes, headBytes: Int = 64 * 1024,
                    chunkBytes: Int = 1 << 20, skipAncestors: Set<String> = [".git", ".svn"]) {
            self.minBytes = minBytes; self.headBytes = headBytes; self.chunkBytes = chunkBytes; self.skipAncestors = skipAncestors
        }
    }

    private let config: Config
    public init(config: Config = Config()) { self.config = config }

    /// 一次性扫描，无进度回调（测试/脚本用）。
    public func scan(root: URL) async -> DuplicateReport {
        await Self.run(root: root, config: config, yield: nil)
    }

    /// 带进度的扫描。返回进度流与可取消任务；取消后任务照常返回已累计的部分结果（incomplete=true）。
    public func scanStreaming(root: URL) -> (stream: AsyncStream<DuplicateProgress>, task: Task<DuplicateReport, Never>) {
        let (stream, continuation) = AsyncStream.makeStream(of: DuplicateProgress.self, bufferingPolicy: .unbounded)
        let cfg = config
        let task = Task.detached(priority: .utility) {
            let report = await Self.run(root: root, config: cfg) { continuation.yield($0) }
            continuation.finish()
            return report
        }
        return (stream, task)
    }

    // MARK: - 漏斗主体（静态纯过程）

    struct FileInfo: Sendable { let path: String; let size: UInt64; let device: UInt64; let inode: UInt64; let linkCount: UInt64 }
    struct SizeHeadKey: Hashable { let size: UInt64; let head: [UInt8] }
    struct FullKey: Hashable { let size: UInt64; let full: [UInt8] }

    static func run(root rawRoot: URL, config: Config, yield: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateReport {
        // 规范化根路径：enumerator 产出的是 realpath 形式（/var→/private/var），统一口径避免报告内两种写法混用。
        // 注意 URL.resolvingSymlinksInPath() 会刻意去掉 /private 前缀，与 enumerator 不一致，故用 realpath(3)。
        let root = URL(fileURLWithPath: Self.canonicalPath(rawRoot.path), isDirectory: true)
        let startedAt = Date()
        let skipLog = SkipLog()
        let clock = ContinuousClock()
        var lastEmit = clock.now - .seconds(1) // 回拨 1s：首条进度立即可见
        var lastPhase: DuplicateProgress.Phase?
        var collected: [FileInfo] = []
        var scannedBytes: UInt64 = 0
        var incomplete = false

        // 进度节流：阶段切换与 force 必发；其余每 100ms 至多一条，避免 UI 洪泛。
        func emit(_ p: DuplicateProgress, force: Bool = false) {
            guard let yield else { return }
            if force || p.phase != lastPhase || clock.now - lastEmit >= .milliseconds(100) {
                lastEmit = clock.now; lastPhase = p.phase; yield(p)
            }
        }

        // 阶段 1：枚举。options=[] 保持默认：不跳隐藏文件、深入包内；实测 enumerator 不会跟随符号链接目录。
        // 符号链接条目本身仍会被产出，下面用 lstat 过滤；跳过 .git/.svn 祖先。
        let fm = FileManager.default
        // 根目录前置校验：不存在/非目录/不可读都明确记录并标注 incomplete，不让空结果伪装成“没有重复”。
        var rootIsDirectory: ObjCBool = false
        let rootUsable = fm.fileExists(atPath: root.path, isDirectory: &rootIsDirectory) && rootIsDirectory.boolValue && fm.isReadableFile(atPath: root.path)
        if !rootUsable { skipLog.add(SkippedItem(path: root.path, reason: "扫描根不存在、不是目录或不可读")); incomplete = true }
        let enumerator = rootUsable ? fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { url, error in
            skipLog.add(SkippedItem(path: url.path, reason: "枚举失败：\(error.localizedDescription)"))
            return true // 记录后继续，不让单个不可读目录终止整体分析
        }) : nil
        if rootUsable && enumerator == nil {
            skipLog.add(SkippedItem(path: root.path, reason: "无法枚举扫描根"))
            incomplete = true
        }
        while let item = enumerator?.nextObject() {
            guard let url = item as? URL else { continue }
            if Task.isCancelled { incomplete = true; break }
            var st = stat()
            guard lstat(url.path, &st) == 0 else {
                skipLog.add(SkippedItem(path: url.path, reason: "lstat 失败：\(String(cString: strerror(errno)))"))
                continue
            }
            let kind = st.st_mode & S_IFMT
            if kind == S_IFLNK { continue } // 符号链接不收集（不跟随、不判重）
            if kind != S_IFREG { continue } // 只收普通文件；目录由 enumerator 自行深入
            let segments = url.path.split(separator: "/")
            if segments.contains(where: { config.skipAncestors.contains(String($0)) }) { continue }
            let size = UInt64(clamping: st.st_size)
            guard size >= config.minBytes else { continue }
            collected.append(FileInfo(path: url.path, size: size, device: UInt64(st.st_dev), inode: UInt64(st.st_ino), linkCount: UInt64(st.st_nlink)))
            scannedBytes &+= size
            emit(DuplicateProgress(phase: .enumerating, scannedBytes: scannedBytes, phaseTotalBytes: nil, currentPath: url.path, completedGroups: 0))
            if collected.count % 256 == 0 { await Task.yield() }
        }
        emit(DuplicateProgress(phase: .enumerating, scannedBytes: scannedBytes, phaseTotalBytes: nil, currentPath: nil, completedGroups: 0), force: true)

        // 阶段 2：尺寸分桶，单件桶淘汰。
        var bySize: [UInt64: [FileInfo]] = [:]
        for f in collected { bySize[f.size, default: []].append(f) }
        let sizeSurvivors = bySize.values.filter { $0.count > 1 }
            .sorted { ($0.map(\.path).min() ?? "") < ($1.map(\.path).min() ?? "") } // 桶间确定性

        // 阶段 3：桶内头部 SHA-256，(size, headHash) 分桶，单件淘汰。
        var byHead: [SizeHeadKey: [FileInfo]] = [:]
        var headBytesRead: UInt64 = 0
        let headTotal: UInt64 = sizeSurvivors.reduce(0) { sum, bucket in sum &+ bucket.reduce(0) { $0 &+ min($1.size, UInt64(config.headBytes)) } }
        headPhase: for bucket in sizeSurvivors {
            for f in bucket.sorted(by: { $0.path < $1.path }) {
                if Task.isCancelled { incomplete = true; break headPhase }
                do {
                    let head = try Self.readHead(f.path, headBytes: config.headBytes)
                    headBytesRead &+= UInt64(head.count)
                    byHead[SizeHeadKey(size: f.size, head: Array(SHA256.hash(data: head))), default: []].append(f)
                } catch {
                    // 权限拒绝等读取失败：记录并跳过，未读到内容的文件永不判重。
                    skipLog.add(SkippedItem(path: f.path, reason: "头部读取失败：\(error.localizedDescription)"))
                }
                emit(DuplicateProgress(phase: .hashing, scannedBytes: headBytesRead, phaseTotalBytes: headTotal, currentPath: f.path, completedGroups: 0))
            }
        }
        let headSurvivors = byHead.values.filter { $0.count > 1 }
            .sorted { ($0.map(\.path).min() ?? "") < ($1.map(\.path).min() ?? "") }

        // 阶段 4：残组全量流式 SHA-256（1 MiB 块）；同 (size, fullHash) 即真重复组。
        var byFull: [FullKey: [FileInfo]] = [:]
        var fullBytesRead: UInt64 = 0
        var confirmedGroups = 0
        let fullTotal: UInt64 = headSurvivors.reduce(0) { $0 &+ $1.reduce(0) { $0 &+ $1.size } }
        for bucket in headSurvivors {
            for f in bucket.sorted(by: { $0.path < $1.path }) {
                if Task.isCancelled { incomplete = true; break }
                do {
                    let digest = try Self.hashFull(f.path, chunkBytes: config.chunkBytes) { read in
                        fullBytesRead &+= UInt64(read)
                        emit(DuplicateProgress(phase: .hashConfirming, scannedBytes: fullBytesRead, phaseTotalBytes: fullTotal, currentPath: f.path, completedGroups: confirmedGroups))
                    }
                    byFull[FullKey(size: f.size, full: Array(digest)), default: []].append(f)
                } catch {
                    skipLog.add(SkippedItem(path: f.path, reason: "全量读取失败：\(error.localizedDescription)"))
                }
            }
            confirmedGroups = byFull.values.filter { $0.count > 1 }.count
        }

        let groups: [DuplicateGroup] = byFull.values.filter { $0.count > 1 }
            .map { files in DuplicateGroup(size: files[0].size, files: files.sorted { $0.path < $1.path }.map { DuplicateFile(path: $0.path, size: $0.size, device: $0.device, inode: $0.inode, linkCount: $0.linkCount) }) }
            // 浪费字节降序，并列按首路径：报告确定性排序。
            .sorted { $0.wastedBytes == $1.wastedBytes ? $0.files[0].path < $1.files[0].path : $0.wastedBytes > $1.wastedBytes }
        // 收尾事件：携带最终组数，UI 据此结束进度显示。
        emit(DuplicateProgress(phase: .hashConfirming, scannedBytes: fullBytesRead, phaseTotalBytes: fullTotal, currentPath: nil, completedGroups: groups.count), force: true)

        return DuplicateReport(rootPath: root.path, minBytes: config.minBytes,
                               scannedFiles: UInt64(collected.count), scannedBytes: scannedBytes,
                               groups: groups, skipped: skipLog.snapshot().sorted { $0.path < $1.path },
                               incomplete: incomplete, startedAt: startedAt, finishedAt: Date())
    }

    /// realpath(3)：完整解析符号链接与 /private 前缀；失败（如路径不存在）时原样返回，由后续根校验兜底。
    static func canonicalPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        guard realpath(path, &buffer) != nil else { return path }
        return String(cString: buffer)
    }

    static func readHead(_ path: String, headBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        return try handle.read(upToCount: headBytes) ?? Data()
    }

    static func hashFull(_ path: String, chunkBytes: Int, onChunk: (Int) -> Void) throws -> [UInt8] {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkBytes), !chunk.isEmpty {
            hasher.update(data: chunk)
            onChunk(chunk.count)
        }
        return Array(hasher.finalize())
    }
}

/// 枚举 errorHandler 是跨任务边界的 @Sendable 闭包，用锁保护跳过清单的追加与快照。
final class SkipLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SkippedItem] = []
    func add(_ item: SkippedItem) { lock.lock(); items.append(item); lock.unlock() }
    func snapshot() -> [SkippedItem] { lock.lock(); defer { lock.unlock() }; return items }
}
