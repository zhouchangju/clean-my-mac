import Foundation
import Testing
@testable import AIAdvisorCore

/// 命令构造与执行语义：假 ProcessRunner 断言 argv 与 stdin 内容。
@Suite struct AIAnalysisRunnerTests {

    /// flag 与其值相邻出现（args 中 flag 后紧跟 value）。
    private func flagValue(_ args: [String], _ flag: String, equals value: String) -> Bool {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return false }
        return args[i + 1] == value
    }

    // MARK: - codex

    /// codex stub：模拟真实行为——把最终答案写入 `--output-last-message` 指向的文件，stdout 打噪声。
    private func codexStub(answer: String = "文件里的干净答案") -> @Sendable (FakeProcessRunner.Call) -> ProcessOutput {
        { call in
            if let i = call.arguments.firstIndex(of: "--output-last-message"), i + 1 < call.arguments.count {
                try? answer.write(toFile: call.arguments[i + 1], atomically: true, encoding: .utf8)
            }
            return ProcessOutput(stdoutText: "会话噪声…\nEVENT", stderrText: "", exitCode: 0, timedOut: false)
        }
    }

    @Test func codexArgvMatchesVerifiedHelpContract() async throws {
        let runner = FakeProcessRunner(stub: codexStub())
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [installedCodex()]), processRunner: runner)
        let result = try await analyzer.run(runtimeID: "codex", prompt: "PROMPT 正文", workDir: nil, timeout: 30)
        let call = try #require(await runner.calls.first)
        #expect(call.executable == "/fake/bin/codex")
        #expect(call.standardInput == Data("PROMPT 正文".utf8)) // prompt 走 stdin
        #expect(call.timeout == 30)
        // 固化形态：exec --sandbox read-only --skip-git-repo-check --color never --output-last-message <tmp> -
        #expect(call.arguments.first == "exec")
        #expect(flagValue(call.arguments, "--sandbox", equals: "read-only"))
        #expect(call.arguments.contains("--skip-git-repo-check"))
        #expect(flagValue(call.arguments, "--color", equals: "never"))
        #expect(call.arguments.contains("--output-last-message"))
        #expect(call.arguments.last == "-") // `-` = prompt 从 stdin 读
        #expect(!call.arguments.contains { $0 == "-C" }) // 无 workDir 时不带 -C
        #expect(result.stdoutText == "文件里的干净答案") // 文件答案优先，stdout 噪声丢弃
        #expect(result.exitCode == 0 && !result.timedOut && result.runtimeID == "codex")
    }

    @Test func codexAddsCDFlagWhenWorkDirGiven() async throws {
        let runner = FakeProcessRunner(stub: codexStub())
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [installedCodex()]), processRunner: runner)
        _ = try await analyzer.run(runtimeID: "codex", prompt: "P", workDir: URL(fileURLWithPath: "/tmp/work"), timeout: 5)
        let call = try #require(await runner.calls.first)
        #expect(flagValue(call.arguments, "-C", equals: "/tmp/work"))
        #expect(call.currentDirectory == "/tmp/work")
        #expect(call.arguments.last == "-")
    }

    @Test func codexFallsBackToStdoutWhenAnswerFileMissing() async throws {
        let runner = FakeProcessRunner(stub: { _ in
            ProcessOutput(stdoutText: "stdout 兜底答案", stderrText: "", exitCode: 0, timedOut: false)
        })
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [installedCodex()]), processRunner: runner)
        let result = try await analyzer.run(runtimeID: "codex", prompt: "P", workDir: nil, timeout: 5)
        #expect(result.stdoutText == "stdout 兜底答案")
    }

    // MARK: - opencode

    private func opencodeInstalled() -> AIRuntime {
        AIRuntime(id: "opencode", kind: .cliAgent, displayName: "OpenCode", executablePath: "/fake/bin/opencode", version: nil, canRunAnalysis: true)
    }

    @Test func opencodeArgvPassesPromptDirectly() async throws {
        let runner = FakeProcessRunner(stub: { _ in ProcessOutput(stdoutText: "ANS", stderrText: "", exitCode: 0, timedOut: false) })
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [opencodeInstalled()]), processRunner: runner)
        let result = try await analyzer.run(runtimeID: "opencode", prompt: "PROMPT", workDir: nil, timeout: 10)
        let call = try #require(await runner.calls.first)
        #expect(call.executable == "/fake/bin/opencode")
        #expect(call.arguments == ["run", "--format", "default", "PROMPT"]) // argv 直传
        #expect(call.standardInput == nil) // 无 stdin 通道
        #expect(result.stdoutText == "ANS")
    }

    @Test func opencodeTruncatesOverlongPromptAndNotesIt() async throws {
        let runner = FakeProcessRunner(stub: { _ in ProcessOutput(stdoutText: "ANS", stderrText: "", exitCode: 0, timedOut: false) })
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [opencodeInstalled()]), processRunner: runner)
        let longPrompt = String(repeating: "文", count: AIAnalysisRunner.opencodeMaxPromptBytes) // 中文 3 字节/字符 → 远超字节上限
        let result = try await analyzer.run(runtimeID: "opencode", prompt: longPrompt, workDir: nil, timeout: 10)
        let call = try #require(await runner.calls.first)
        let passedPrompt = try #require(call.arguments.last)
        #expect(passedPrompt.utf8.count <= AIAnalysisRunner.opencodeMaxPromptBytes) // macOS 单参数 256KB 安全预算
        #expect(passedPrompt.hasSuffix("文")) // UTF-8 边界修整后不留替换符
        #expect(result.stdoutText.contains("截断")) // 结果中注明
        #expect(result.stdoutText.contains("ANS"))
    }

    // MARK: - 错误路径（fail-closed，含可复现命令行）

    @Test func unknownRuntimeIDThrows() async {
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [installedCodex()]), processRunner: FakeProcessRunner(stub: { _ in fatalError("不应执行") }))
        await #expect(throws: AIRunnerError.self) { try await analyzer.run(runtimeID: "nope", prompt: "P", workDir: nil, timeout: 5) }
    }

    @Test func notInstalledRuntimeThrowsWithChineseHint() async throws {
        let missing = AIRuntime(id: "codex", kind: .cliAgent, displayName: "Codex CLI", executablePath: nil, version: nil, canRunAnalysis: false)
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [missing]), processRunner: FakeProcessRunner(stub: { _ in fatalError("不应执行") }))
        var caught: AIRunnerError? = nil
        do { _ = try await analyzer.run(runtimeID: "codex", prompt: "P", workDir: nil, timeout: 5) } catch { caught = error as? AIRunnerError }
        #expect(caught != nil, "应抛错")
        #expect(caught?.message.contains("未检测到") == true)
    }

    @Test func installedButNotAnalyzableThrows() async throws {
        let droid = AIRuntime(id: "droid", kind: .cliAgent, displayName: "Droid", executablePath: "/fake/bin/droid", version: nil, canRunAnalysis: false)
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [droid]), processRunner: FakeProcessRunner(stub: { _ in fatalError("不应执行") }))
        var caught: AIRunnerError? = nil
        do { _ = try await analyzer.run(runtimeID: "droid", prompt: "P", workDir: nil, timeout: 5) } catch { caught = error as? AIRunnerError }
        #expect(caught != nil, "应抛错")
        #expect(caught?.message.contains("暂不支持分析执行") == true)
    }

    @Test func timeoutErrorContainsCopyableCommandLine() async throws {
        let runner = FakeProcessRunner(stub: { _ in ProcessOutput(stdoutText: "", stderrText: "", exitCode: -1, timedOut: true) })
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [installedCodex()]), processRunner: runner)
        var caught: AIRunnerError? = nil
        do { _ = try await analyzer.run(runtimeID: "codex", prompt: "P", workDir: nil, timeout: 3) } catch { caught = error as? AIRunnerError }
        #expect(caught != nil, "应抛错")
        #expect(caught?.message.contains("超时") == true)
        #expect(caught?.message.contains("/fake/bin/codex exec --sandbox read-only --skip-git-repo-check --color never") == true)
    }

    @Test func nonzeroExitErrorQuotesPromptArgument() async throws {
        let runner = FakeProcessRunner(stub: { _ in ProcessOutput(stdoutText: "", stderrText: "boom", exitCode: 1, timedOut: false) })
        let analyzer = AIAnalysisRunner(detector: FakeDetector(runtimes: [opencodeInstalled()]), processRunner: runner)
        var caught: AIRunnerError? = nil
        do { _ = try await analyzer.run(runtimeID: "opencode", prompt: "带 空格 的提示", workDir: nil, timeout: 5) } catch { caught = error as? AIRunnerError }
        #expect(caught != nil, "应抛错")
        #expect(caught?.message.contains("退出码 1") == true)
        #expect(caught?.message.contains("\"带 空格 的提示\"") == true) // 空格参数加引号，可复制复现
        #expect(caught?.message.contains("boom") == true)
    }

    // MARK: - 命令行拼装纯函数

    @Test func shellDisplayQuotesOnlyWhenNeeded() {
        #expect(AIAnalysisRunner.shellDisplay(executable: "/b/codex", arguments: ["exec", "read-only"]) == "/b/codex exec read-only")
        #expect(AIAnalysisRunner.shellDisplay(executable: "/b/codex", arguments: ["a b", "plain"]) == "/b/codex \"a b\" plain")
        #expect(AIAnalysisRunner.shellDisplay(executable: "/b/codex", arguments: ["say \"hi\""]) == "/b/codex \"say \\\"hi\\\"\"")
    }

    @Test func truncateUTF8KeepsBoundary() {
        #expect(AIAnalysisRunner.truncateUTF8("abc", maxBytes: 10) == "abc")
        let truncated = AIAnalysisRunner.truncateUTF8(String(repeating: "文", count: 100), maxBytes: 10)
        #expect(truncated.utf8.count == 9) // 10 字节截到 3 个完整中文字符
        #expect(!truncated.contains("\u{FFFD}"))
    }
}
