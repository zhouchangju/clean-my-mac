import Foundation
import Darwin

/// 子进程执行结果（stdout/stderr 全量收集）。
public struct ProcessOutput: Sendable, Equatable {
    public let stdoutText: String
    public let stderrText: String
    public let exitCode: Int32
    public let timedOut: Bool
    public init(stdoutText: String, stderrText: String, exitCode: Int32, timedOut: Bool) {
        self.stdoutText = stdoutText; self.stderrText = stderrText; self.exitCode = exitCode; self.timedOut = timedOut
    }
}

/// 进程执行抽象：launch + 收集 stdout/stderr + 超时/取消终止。默认实现基于 Foundation.Process，测试注入假实现断言 argv。
public protocol ProcessRunning: Sendable {
    /// 运行可执行文件；standardInput 写入 stdin 管道后关闭；超时或宿主 Task 取消 → SIGTERM（3s 宽限后 SIGKILL 兜底）。
    func run(executable: String, arguments: [String], currentDirectory: String?, standardInput: Data?, environment: [String: String]?, timeout: TimeInterval) async throws -> ProcessOutput
}

/// AI 分析/执行链路错误：中文 message，可直接向用户展示。
public struct AIRunnerError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Foundation.Process 默认实现。无 Timer / 无轮询：退出靠 terminationHandler，超时/取消靠任务睡眠 + 信号。
public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String], currentDirectory: String? = nil, standardInput: Data? = nil, environment: [String: String]? = nil, timeout: TimeInterval) async throws -> ProcessOutput {
        guard timeout > 0 else { throw AIRunnerError("进程超时配置非法（timeout=\(timeout) 秒），已拒绝执行") }
        let controller = PipedProcessController(
            executable: executable, arguments: arguments, currentDirectory: currentDirectory, environment: environment)
        do { try controller.launch() } catch {
            throw AIRunnerError("无法启动进程 \(executable)：\(error.localizedDescription)")
        }
        controller.beginStdin(standardInput) // 与退出等待并行，避免 stdin 管道缓冲区写满死锁
        let timeoutTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            controller.markTimedOut(); controller.signalTermination()
            try? await Task.sleep(for: .seconds(3)) // SIGTERM 宽限
            guard !Task.isCancelled else { return }
            controller.forceKill()
        }
        await withTaskCancellationHandler {
            await controller.waitExit()
        } onCancel: {
            timeoutTask.cancel()
            controller.signalTermination() // Task 取消 → SIGTERM
        }
        timeoutTask.cancel()
        await controller.finishStdin()
        return controller.collectOutput()
    }
}

/// 持有单个 Process 的 @unchecked Sendable 控制器：终止信号幂等、退出等待一次性唤醒、输出线程安全收集。
final class PipedProcessController: @unchecked Sendable {
    private let process = Process()
    private let outSink = DataSink(); private let errSink = DataSink()
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var resumed = false
    private var timedOutFlag = false
    private var signaled = false
    private var stdinTask: Task<Void, Never>?
    private let stdinWrite: FileHandle
    private let outRead: FileHandle; private let errRead: FileHandle
    private var stdinWriteClosed = false

    init(executable: String, arguments: [String], currentDirectory: String?, environment: [String: String]?) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory) }
        if let environment { process.environment = environment }
        let outPipe = Pipe(); let errPipe = Pipe(); let inPipe = Pipe()
        process.standardOutput = outPipe; process.standardError = errPipe; process.standardInput = inPipe
        stdinWrite = inPipe.fileHandleForWriting
        outRead = outPipe.fileHandleForReading; errRead = errPipe.fileHandleForReading
    }

    func launch() throws {
        outRead.readabilityHandler = { [outSink] in outSink.append($0.availableData) }
        errRead.readabilityHandler = { [errSink] in errSink.append($0.availableData) }
        process.terminationHandler = { [weak self] _ in self?.finish() }
        try process.run()
    }

    /// 启动即极快退出时的竞态兜底：退出等待只被唤醒一次。
    private func finish() {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        waiter?.resume(); waiter = nil
    }

    func waitExit() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock(); defer { lock.unlock() }
            if resumed { cont.resume(); return }
            waiter = cont
        }
    }

    func markTimedOut() { lock.lock(); timedOutFlag = true; lock.unlock() }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOutFlag }

    /// SIGTERM 至多一次。
    func signalTermination() {
        lock.lock(); defer { lock.unlock() }
        guard !signaled else { return }
        signaled = true
        if process.isRunning { process.terminate() }
    }

    /// SIGKILL 兜底（仅超时且 SIGTERM 3s 宽限后仍未退出时）。
    func forceKill() {
        lock.lock(); defer { lock.unlock() }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func beginStdin(_ data: Data?) {
        stdinTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if let data { try? self.stdinWrite.write(contentsOf: data) } // 写失败（进程提前退出）以退出码为准
            self.closeStdin()
        }
    }

    private func closeStdin() {
        lock.lock(); defer { lock.unlock() }
        guard !stdinWriteClosed else { return }
        stdinWriteClosed = true
        try? stdinWrite.close()
    }

    func finishStdin() async {
        await stdinTask?.value
        closeStdin()
    }

    /// 进程退出后调用：停读、关管道、汇总输出。
    func collectOutput() -> ProcessOutput {
        outRead.readabilityHandler = nil; errRead.readabilityHandler = nil
        try? outRead.close(); try? errRead.close()
        return ProcessOutput(stdoutText: outSink.text, stderrText: errSink.text, exitCode: process.terminationStatus, timedOut: timedOut)
    }
}

/// 线程安全输出收集器（readabilityHandler 回调并发到达，EOF 为空块）。
final class DataSink: @unchecked Sendable {
    private let lock = NSLock(); private var data = Data()
    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
