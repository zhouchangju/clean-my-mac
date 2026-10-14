import Foundation

/// 一次外部命令执行的只读结果；timedOut=true 表示按预算中止（SIGTERM，绝不 SIGKILL）。
public struct CommandResult: Sendable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String
  public let timedOut: Bool
  /// 进程未能启动（可执行文件缺失等）；fail-closed 展示用。
  public let launchError: String?

  public init(exitCode: Int32, stdout: String = "", stderr: String = "", timedOut: Bool = false, launchError: String? = nil) {
    self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr
    self.timedOut = timedOut; self.launchError = launchError
  }
  public var succeeded: Bool { exitCode == 0 && !timedOut && launchError == nil }
}

/// 进程执行统一入口：生产实现用 Foundation.Process，测试注入假实现断言 argv。
public protocol CommandRunning: Sendable {
  /// 运行 `executable arguments...`，超过 timeout 秒按失败处理（SIGTERM 后回收）。
  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult
}

/// 默认实现：Foundation.Process + 超时 SIGTERM。任务取消同样转发为 SIGTERM。
public struct ProcessCommandRunner: CommandRunning {
  public init() {}

  public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
    // Process/Pipe 均非 Sendable，整体限制在单个 detached 任务内创建、使用与回收。
    let work = Task.detached(priority: .utility) { () -> CommandResult in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      let outPipe = Pipe(), errPipe = Pipe()
      process.standardOutput = outPipe; process.standardError = errPipe
      do { try process.run() } catch { return CommandResult(exitCode: 127, stderr: "launch failed: \(error.localizedDescription)", launchError: error.localizedDescription) }
      // 跨取消边界持有 Process 的唯一通道：未检查包装（仅调用 terminate）。
      let guardBox = ProcessGuard(process)
      return await withTaskCancellationHandler {
        // 先排干管道再等待退出，避免管道缓冲区写满导致死锁。
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
          exitCode: process.terminationStatus,
          stdout: String(decoding: outData, as: UTF8.self),
          stderr: String(decoding: errData, as: UTF8.self),
          timedOut: guardBox.fired)
      } onCancel: {
        guardBox.terminate() // 安全红线：只 SIGTERM，绝不 SIGKILL
      }
    }
    return await withTaskGroup(of: CommandResult?.self) { group in
      group.addTask { await work.value }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
        return nil // 超时哨兵：先于进程完成即视为超时
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      if let finished = first { return finished }
      work.cancel() // 触发 SIGTERM；随后取回（可能含部分输出的）最终结果
      return await work.value
    }
  }
}

/// 取消/超时边界上的 SIGTERM 桥；fired 标记是否由我方发起终止。
final class ProcessGuard: @unchecked Sendable {
  private let lock = NSLock()
  private let process: Process
  private var _fired = false
  init(_ process: Process) { self.process = process }
  var fired: Bool { lock.lock(); defer { lock.unlock() }; return _fired }
  func terminate() {
    lock.lock(); defer { lock.unlock() }
    _fired = true
    if process.isRunning { process.terminate() }
  }
}
