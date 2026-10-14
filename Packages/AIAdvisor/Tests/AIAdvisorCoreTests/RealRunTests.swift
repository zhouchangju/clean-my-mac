import Foundation
import Testing
import AIAdvisorCore

/// 真实运行（opt-in，沿用 LMC_BENCHMARK 模式）：LMC_REAL_RUN=1 时真跑 codex analyze 一次。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LMC_REAL_RUN"] == "1")) struct RealRunTests {

    @Test func realDetectionFindsLocalRuntimes() async throws {
        let runtimes = await RuntimeDetector().detectAll()
        let installed = runtimes.filter(\.isInstalled)
        #expect(installed.count >= 3, "本机应至少检测到 3 个 runtime，实际：\(installed.map(\.id))")
        let codex = try #require(runtimes.first { $0.id == "codex" && $0.isInstalled })
        #expect(codex.version?.contains("0.16") == true, "codex 版本应为 0.162.x，实际 \(codex.version ?? "nil")")
    }

    @Test func realCodexAnalyzeAnswersSimpleQuestion() async throws {
        let result = try await AIAnalysisRunner().run(
            runtimeID: "codex", prompt: "用一句话回答：1+1=?", workDir: nil, timeout: 120)
        #expect(result.exitCode == 0)
        #expect(!result.timedOut)
        #expect(result.stdoutText.contains("2"))
        print("LMC_REAL_RUN codex answer=\(result.stdoutText.prefix(100)) duration=\(result.duration)")
    }
}
