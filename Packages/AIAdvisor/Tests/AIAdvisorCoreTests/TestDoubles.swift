import Foundation
import AIAdvisorCore

/// 假进程执行器：记录 argv/stdin/环境，返回可配置结果。
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Sendable {
        let executable: String
        let arguments: [String]
        let currentDirectory: String?
        let standardInput: Data?
        let environment: [String: String]?
        let timeout: TimeInterval
    }

    private actor Log {
        var items: [Call] = []
        func append(_ call: Call) { items.append(call) }
        var all: [Call] { items }
    }

    private let log = Log()
    private let stub: @Sendable (Call) -> ProcessOutput

    init(stub: @escaping @Sendable (Call) -> ProcessOutput) { self.stub = stub }

    var calls: [Call] { get async { await log.all } }

    func run(executable: String, arguments: [String], currentDirectory: String? = nil, standardInput: Data? = nil, environment: [String: String]? = nil, timeout: TimeInterval) async throws -> ProcessOutput {
        let call = Call(executable: executable, arguments: arguments, currentDirectory: currentDirectory, standardInput: standardInput, environment: environment, timeout: timeout)
        await log.append(call)
        return stub(call)
    }
}

/// 假检测器：返回固定 runtime 列表。
struct FakeDetector: RuntimeDetecting {
    let runtimes: [AIRuntime]
    func detectAll(forceRefresh: Bool) async -> [AIRuntime] { runtimes }
}

/// 测试夹具：临时目录 + 可执行脚本制造。
struct ExecutableFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lmc-air-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    /// 写入 0755 的 shell 脚本并返回绝对路径。
    func executable(name: String, script: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

/// 安装的 codex 快照（供分析器测试）。
func installedCodex(path: String = "/fake/bin/codex") -> AIRuntime {
    AIRuntime(id: "codex", kind: .cliAgent, displayName: "Codex CLI", executablePath: path, version: "codex 0.0.0-test", canRunAnalysis: true)
}
