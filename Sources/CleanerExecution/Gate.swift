import CleanerDomain

/// This gate cannot be opened by a preference, imported plan, or launch argument.
public enum ExecutionGate {
    public static let enabled = false
    public static let blockers = ["AC-09：至少两条真实规则准入尚未通过", "AC-15/17：竞态与进程中断恢复须独立验证", "AC-25：原生执行与恢复全链尚未验证"]
    public static func requireEnabled() throws { throw CleanerError(.executionDisabled, blockers.joined(separator: "；")) }
}
