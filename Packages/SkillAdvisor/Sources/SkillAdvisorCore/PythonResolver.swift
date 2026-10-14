import Foundation

/// Python 解释器解析：Guardian 脚本使用 PEP 604 类型语法（如 `str | None`），
/// 需 Python ≥ 3.10；系统 /usr/bin/python3（3.9）会运行时报错，故按
/// PATH 分量 + 常见安装位探测，最后才回退系统解释器。
public enum PythonResolver {
  public static let systemFallback = "/usr/bin/python3"

  /// 返回第一个存在的 python3 绝对路径；PATH 顺序优先（与终端行为一致）。
  public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                             fileManager: FileManager = .default) -> String {
    var candidates: [String] = []
    let pathEnv = environment["PATH"] ?? ""
    candidates += pathEnv.split(separator: ":").map { "\($0)/python3" }
    candidates += ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", systemFallback]
    return candidates.first { fileManager.isExecutableFile(atPath: $0) } ?? systemFallback
  }
}
