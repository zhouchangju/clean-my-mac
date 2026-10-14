import Foundation

/// ADR-10 resource budget, shared by every composition root. These are not cleanup permissions.
public enum IndexResourcePolicy {
    public static let defaultMaxBytes:UInt64 = 1024 * 1024 * 1024
    public static let defaultMinimumAvailableBytes:UInt64 = 1024 * 1024 * 1024
    public static func availableBytes(blocks:UInt64,blockSize:UInt64) throws -> UInt64 {
        guard blockSize>0 else { throw CleanerError(.quotaExceeded,"无法确认文件系统块大小，索引写入已停止") }
        let product=blocks.multipliedReportingOverflow(by:blockSize)
        guard !product.overflow else { throw CleanerError(.quotaExceeded,"文件系统余量乘法溢出，索引写入已停止") }
        return product.partialValue
    }
}
