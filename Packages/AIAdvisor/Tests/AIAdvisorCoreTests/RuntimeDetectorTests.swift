import Foundation
import Testing
@testable import AIAdvisorCore

/// 检测逻辑：伪造 PATH 分量与假可执行脚本验证探测与版本解析。
@Suite struct RuntimeDetectorTests {

    @Test func detectsThroughPathComponentAndParsesFirstLine() async throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        let scriptPath = try fixture.executable(name: "codex", script: "#!/bin/sh\necho 'codex 0.1.2-test'\necho 'second line'")
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"])
        let runtimes = await detector.detectAll()
        let codex = try #require(runtimes.first { $0.id == "codex" })
        #expect(codex.executablePath == scriptPath)
        #expect(codex.version == "codex 0.1.2-test") // 只取首行
        #expect(codex.isInstalled && codex.canRunAnalysis)
        #expect(runtimes.map(\.id) == AIRuntimeCatalog.ids) // 展示顺序 = 目录顺序
    }

    @Test func truncatesVersionTo60Characters() async throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        _ = try fixture.executable(name: "codex", script: "#!/bin/sh\necho \"\(String(repeating: "v", count: 100))\"")
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"])
        let runtimes = await detector.detectAll(forceRefresh: true)
        #expect(runtimes.first { $0.id == "codex" }?.version?.count == 60)
    }

    @Test func missingRuntimeYieldsNilPathAndNoAnalysis() async throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"])
        let runtimes = await detector.detectAll(forceRefresh: true)
        // 只断言可注入的 HOME 相对安装位；ollama 的 /opt/homebrew/bin 是绝对路径，随宿主机实况浮动
        for runtime in runtimes where runtime.id != "ollama" {
            #expect(runtime.executablePath == nil)
            #expect(runtime.version == nil)
            #expect(!runtime.canRunAnalysis)
        }
    }

    @Test func versionProbeFailureIsNotDetectionFailure() async throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        _ = try fixture.executable(name: "codex", script: "#!/bin/sh\nexit 1")
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"])
        let runtimes = await detector.detectAll(forceRefresh: true)
        let codex = try #require(runtimes.first { $0.id == "codex" })
        #expect(codex.executablePath != nil && codex.version == nil) // 版本失败 → nil，不否定安装
    }

    @Test func versionPrefersLineContainingDigitsOverWarningLine() async throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        // 模拟 ollama：stdout 空，stderr 首行为连接告警、版本在后
        _ = try fixture.executable(name: "codex", script: "#!/bin/sh\necho 'Warning: could not connect to a running Ollama instance' >&2\necho 'Warning: client version is 0.32.15' >&2")
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"])
        let runtimes = await detector.detectAll(forceRefresh: true)
        #expect(runtimes.first { $0.id == "codex" }?.version == "Warning: client version is 0.32.15")
    }

    @Test func findsKnownInstallLocationBeyondPATH() async throws {
        let home = try ExecutableFixture(); defer { home.cleanup() }
        let path = try ExecutableFixture(); defer { path.cleanup() }
        let scriptPath = try home.executable(name: "opencode", script: "#!/bin/sh\necho 'opencode 1.2.3'")
        try FileManager.default.createDirectory(atPath: home.root.appendingPathComponent(".local/bin").path, withIntermediateDirectories: true)
        // opencode 实际装在 ~/.opencode/bin：模拟该已知安装位（PATH 里没有）
        try FileManager.default.createDirectory(atPath: home.root.appendingPathComponent(".opencode/bin").path, withIntermediateDirectories: true)
        let knownPath = home.root.appendingPathComponent(".opencode/bin/opencode").path
        try "#!/bin/sh\necho 'opencode 9.9.9'".write(toFile: knownPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: knownPath)
        _ = scriptPath
        let detector = RuntimeDetector(environment: ["PATH": path.root.path, "HOME": home.root.path])
        let runtimes = await detector.detectAll(forceRefresh: true)
        let opencode = try #require(runtimes.first { $0.id == "opencode" })
        #expect(opencode.executablePath == knownPath)
        #expect(opencode.version == "opencode 9.9.9")
    }

    @Test func directoryWithExecutableBitIsNotAnExecutableFile() throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        let dir = fixture.root.appendingPathComponent("codex") // 目录 + 0755，不算可执行文件
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"])
        let spec = try #require(AIRuntimeCatalog.spec(id: "codex"))
        #expect(detector.searchExecutable(spec: spec) == nil)
    }

    @Test func cachesVersionProbesFor60SecondsAndForceRefreshBypasses() async throws {
        let fixture = try ExecutableFixture(); defer { fixture.cleanup() }
        _ = try fixture.executable(name: "codex", script: "#!/bin/sh\necho 'codex 7.7.7'")
        // 假执行器只对 fixture 内的脚本计数，避免宿主机 /opt/homebrew 等绝对安装位干扰
        let runner = FakeProcessRunner(stub: { _ in ProcessOutput(stdoutText: "codex 7.7.7", stderrText: "", exitCode: 0, timedOut: false) })
        let detector = RuntimeDetector(environment: ["PATH": fixture.root.path, "HOME": "/nonexistent"], processRunner: runner)
        func fixtureProbes() async -> Int { await runner.calls.filter { $0.executable.hasPrefix(fixture.root.path) }.count }
        _ = await detector.detectAll()          // 首次：探测一次
        _ = await detector.detectAll()          // 缓存命中：不再探测
        #expect(await fixtureProbes() == 1)
        _ = await detector.detectAll(forceRefresh: true)
        #expect(await fixtureProbes() == 2)
    }
}
