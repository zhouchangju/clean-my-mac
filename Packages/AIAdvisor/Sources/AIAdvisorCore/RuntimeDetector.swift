import Foundation

/// Runtime 检测协议（fail-open 于版本、fail-closed 于路径：探测不到即 executablePath=nil）。
public protocol RuntimeDetecting: Sendable {
    /// 检测全部受支持 runtime；结果缓存 60 秒，forceRefresh=true 时强制重探。
    func detectAll(forceRefresh: Bool) async -> [AIRuntime]
}

extension RuntimeDetecting {
    public func detectAll() async -> [AIRuntime] { await detectAll(forceRefresh: false) }
}

/// 默认实现：不依赖 shell which，直接解析 PATH 分量 + 已知安装位做可执行文件探测，再 `<cmd> --version`（5s 超时）。
public struct RuntimeDetector: RuntimeDetecting {
    /// 检测结果缓存时长。
    public static let cacheTTL: TimeInterval = 60
    /// 版本探测超时。
    public static let versionProbeTimeout: TimeInterval = 5
    /// 版本字符串截断上限。
    public static let versionMaxLength = 60

    private let environment: [String: String]
    private let processRunner: any ProcessRunning
    private let cache = DetectionCache()

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, processRunner: any ProcessRunning = FoundationProcessRunner()) {
        self.environment = environment
        self.processRunner = processRunner
    }

    public func detectAll(forceRefresh: Bool = false) async -> [AIRuntime] {
        if !forceRefresh, let cached = await cache.load(ttl: Self.cacheTTL) { return cached }
        var results: [AIRuntime] = []
        for spec in AIRuntimeCatalog.all {
            let path = searchExecutable(spec: spec)
            var version: String? = nil
            if let path { version = await probeVersion(executablePath: path) } // 版本失败不算检测失败
            results.append(AIRuntime(
                id: spec.id, kind: spec.kind, displayName: spec.displayName,
                executablePath: path, version: version,
                canRunAnalysis: spec.analyzable && path != nil))
        }
        await cache.store(results)
        return results
    }

    /// 依序探测 PATH 分量 + spec 已知安装位（~ 按 HOME 展开），返回首个可执行普通文件的绝对路径。
    func searchExecutable(spec: AIRuntimeCatalog.Spec) -> String? {
        for directory in searchDirectories(spec: spec) where Self.isExecutableFile(atPath: directory + "/" + spec.commandName) {
            return directory + "/" + spec.commandName
        }
        return nil
    }

    private func searchDirectories(spec: AIRuntimeCatalog.Spec) -> [String] {
        var ordered: [String] = []
        if let pathValue = environment["PATH"] {
            for component in pathValue.split(separator: ":", omittingEmptySubsequences: true) { ordered.append(String(component)) }
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        for extra in spec.extraSearchPaths {
            let expanded = extra.hasPrefix("~") ? home + extra.dropFirst() : extra
            ordered.append(expanded)
        }
        var seen = Set<String>(); return ordered.filter { seen.insert($0).inserted }
    }

    /// 可执行普通文件（目录不算；符号链接由 stat 自动跟随解析）。
    static func isExecutableFile(atPath path: String) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        return fm.isExecutableFile(atPath: path)
    }

    /// 运行 `<cmd> --version`，取 stdout（为空取 stderr）首个含数字的行（无则首个非空行），截断到 60 字符；任何失败返回 nil。
    /// 含数字优先：避开 ollama 这类首行打连接告警（"Warning: could not connect…"）而版本在后续行的情况。
    func probeVersion(executablePath: String) async -> String? {
        guard let output = try? await processRunner.run(
            executable: executablePath, arguments: ["--version"], currentDirectory: nil,
            standardInput: nil, environment: nil, timeout: Self.versionProbeTimeout) else { return nil }
        let raw = output.stdoutText.isEmpty ? output.stderrText : output.stdoutText
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let picked = lines.first { $0.contains(where: \.isNumber) } ?? lines.first
        return picked.map { String($0.prefix(Self.versionMaxLength)) }
    }
}

/// 实例级检测结果缓存（60 秒 TTL，无后台刷新）。
private actor DetectionCache {
    private var entries: [AIRuntime]?
    private var stamp: Date?
    func load(ttl: TimeInterval) -> [AIRuntime]? {
        guard let entries, let stamp, Date().timeIntervalSince(stamp) < ttl else { return nil }
        return entries
    }
    func store(_ value: [AIRuntime]) { entries = value; stamp = Date() }
}
