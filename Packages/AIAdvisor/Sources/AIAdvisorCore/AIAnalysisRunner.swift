import Foundation

/// 一次 AI 分析的产物。stdoutText 为展示用回答正文。
public struct AIAnalysisResult: Sendable, Codable, Equatable {
    public let runtimeID: String
    public let stdoutText: String
    public let exitCode: Int32
    public let duration: TimeInterval
    public let timedOut: Bool
    public init(runtimeID: String, stdoutText: String, exitCode: Int32, duration: TimeInterval, timedOut: Bool) {
        self.runtimeID = runtimeID; self.stdoutText = stdoutText; self.exitCode = exitCode
        self.duration = duration; self.timedOut = timedOut
    }
}

/// 分析执行协议（注入 ProcessRunning 便于测试）。
public protocol AnalysisRunning: Sendable {
    /// 以所选 runtime 非交互执行 prompt；timeout 缺省 180 秒；Task 取消 → SIGTERM 子进程。
    func run(runtimeID: String, prompt: String, workDir: URL?, timeout: TimeInterval?) async throws -> AIAnalysisResult
}

/// 默认实现：命令构造集中一处（codex/opencode 形态以 2026-10-14 `--help` 实测固化，便于漂移维护）。
public struct AIAnalysisRunner: AnalysisRunning {
    /// 默认分析超时（秒）。
    public static let defaultTimeout: TimeInterval = 180
    /// opencode 走 argv 直传，macOS 单参数上限 256KB，取安全预算。
    public static let opencodeMaxPromptBytes = 100_000

    private let detector: any RuntimeDetecting
    private let processRunner: any ProcessRunning

    public init(detector: any RuntimeDetecting = RuntimeDetector(), processRunner: any ProcessRunning = FoundationProcessRunner()) {
        self.detector = detector; self.processRunner = processRunner
    }

    public func run(runtimeID: String, prompt: String, workDir: URL? = nil, timeout: TimeInterval? = nil) async throws -> AIAnalysisResult {
        let effectiveTimeout = timeout ?? Self.defaultTimeout
        let runtimes = await detector.detectAll()
        guard let spec = AIRuntimeCatalog.spec(id: runtimeID) else { throw AIRunnerError("未受支持的 runtime id：\(runtimeID)（可用：\(AIRuntimeCatalog.ids.joined(separator: "、"))）") }
        guard let runtime = runtimes.first(where: { $0.id == runtimeID }), let executable = runtime.executablePath else {
            throw AIRunnerError("未检测到 \(spec.displayName)（\(spec.commandName)），请先安装并确认其位于 PATH 或常见安装目录")
        }
        guard runtime.canRunAnalysis else { throw AIRunnerError("\(spec.displayName) 已检测到，但暂不支持分析执行（当前仅 Codex CLI / OpenCode）") }
        switch runtimeID {
        case "codex": return try await runCodex(executable: executable, prompt: prompt, workDir: workDir, timeout: effectiveTimeout)
        case "opencode": return try await runOpenCode(executable: executable, prompt: prompt, workDir: workDir, timeout: effectiveTimeout)
        default: throw AIRunnerError("\(spec.displayName) 的分析命令构造尚未实现")
        }
    }

    /// codex（实测 `codex exec --help`）：`exec --sandbox read-only --skip-git-repo-check --color never -o <tmp> [-C dir] -`，
    /// prompt 走 stdin；答案优先取 `--output-last-message` 文件（stdout 噪声丢弃）。
    private func runCodex(executable: String, prompt: String, workDir: URL?, timeout: TimeInterval) async throws -> AIAnalysisResult {
        let answerURL = FileManager.default.temporaryDirectory.appendingPathComponent("lmc-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: answerURL) }
        let arguments = Self.codexArguments(answerPath: answerURL.path, workDirPath: workDir?.path)
        let display = Self.shellDisplay(executable: executable, arguments: arguments)
        let start = ContinuousClock.now
        let output = try await processRunner.run(
            executable: executable, arguments: arguments, currentDirectory: workDir?.path,
            standardInput: Data(prompt.utf8), environment: nil, timeout: timeout)
        let duration = TimeInterval(start.duration(to: .now).components.seconds)
        try Self.assertSuccess(output: output, timeout: timeout, display: display, displayName: "Codex CLI")
        let answerText = (try? String(contentsOf: answerURL, encoding: .utf8)) ?? ""
        return AIAnalysisResult(
            runtimeID: "codex", stdoutText: answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output.stdoutText : answerText,
            exitCode: output.exitCode, duration: duration, timedOut: output.timedOut)
    }

    /// codex exec 参数（不含可执行文件本身）；`-` 表示 prompt 从 stdin 读入。
    static func codexArguments(answerPath: String, workDirPath: String?) -> [String] {
        var args = ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "--color", "never", "--output-last-message", answerPath]
        if let workDirPath { args += ["-C", workDirPath] }
        args.append("-")
        return args
    }

    /// opencode（实测 `opencode run --help`）：`run --format default <prompt>` argv 直传，无 stdin 通道，
    /// 超长上下文按字节截断并在回答中注明。
    private func runOpenCode(executable: String, prompt: String, workDir: URL?, timeout: TimeInterval) async throws -> AIAnalysisResult {
        var truncated = false
        var effectivePrompt = prompt
        if prompt.utf8.count > Self.opencodeMaxPromptBytes {
            effectivePrompt = Self.truncateUTF8(prompt, maxBytes: Self.opencodeMaxPromptBytes); truncated = true
        }
        let arguments = Self.opencodeArguments(prompt: effectivePrompt)
        let display = Self.shellDisplay(executable: executable, arguments: arguments)
        let start = ContinuousClock.now
        let output = try await processRunner.run(
            executable: executable, arguments: arguments, currentDirectory: workDir?.path,
            standardInput: nil, environment: nil, timeout: timeout)
        let duration = TimeInterval(start.duration(to: .now).components.seconds)
        try Self.assertSuccess(output: output, timeout: timeout, display: display, displayName: "OpenCode")
        let note = "（注意：上下文超出单次执行上限，已截断至约 \(Self.opencodeMaxPromptBytes / 1000)K 字符后执行）"
        return AIAnalysisResult(
            runtimeID: "opencode", stdoutText: truncated ? note + "\n\n" + output.stdoutText : output.stdoutText,
            exitCode: output.exitCode, duration: duration, timedOut: output.timedOut)
    }

    /// opencode run 参数（不含可执行文件本身）。
    static func opencodeArguments(prompt: String) -> [String] { ["run", "--format", "default", prompt] }

    /// 失败统一抛错：中文 message + 可手动复制的完整命令行。
    static func assertSuccess(output: ProcessOutput, timeout: TimeInterval, display: String, displayName: String) throws {
        if output.timedOut { throw AIRunnerError("\(displayName) 分析超时（\(Int(timeout)) 秒）已终止。可手动复现命令：\n\(display)") }
        if output.exitCode != 0 {
            let stderrTail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderrTail.isEmpty ? "" : "\n进程输出（stderr）：\n\(String(stderrTail.suffix(2000)))"
            throw AIRunnerError("\(displayName) 分析失败（退出码 \(output.exitCode)）。可手动复现命令：\n\(display)\(detail)")
        }
    }

    /// 供错误信息展示的完整命令行（含空格/引号的参数加引号，可直接复制到终端复现）。
    static func shellDisplay(executable: String, arguments: [String]) -> String {
        func quote(_ arg: String) -> String {
            guard arg.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else { return arg }
            return "\"" + arg.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return ([executable] + arguments).map(quote).joined(separator: " ")
    }

    /// 按字节截断并修整尾部不完整 UTF-8 序列（边界破缺至多污染末尾一个字符，去之）。
    static func truncateUTF8(_ text: String, maxBytes: Int) -> String {
        let data = Data(text.utf8)
        guard data.count > maxBytes else { return text }
        var truncated = String(decoding: data.prefix(maxBytes), as: UTF8.self)
        if truncated.hasSuffix("\u{FFFD}") { truncated.removeLast() }
        return truncated
    }
}
