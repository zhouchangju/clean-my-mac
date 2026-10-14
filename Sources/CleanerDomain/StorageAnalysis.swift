import Foundation

public enum StorageScanPreset: String, CaseIterable, Sendable, Identifiable {
    case internalDisk, home, downloads, custom
    public var id: String { rawValue }
    public var title: String { switch self { case .internalDisk: "内置存储"; case .home: "我的文件"; case .downloads: "下载文件夹"; case .custom: "自选目录" } }
    public var explanation: String { switch self { case .internalDisk: "扫描内置启动盘的数据卷；保护项仅计量，权限缺口单独列出"; case .home: "查看当前用户目录的空间分布"; case .downloads: "集中审阅下载内容，保留需要的文件"; case .custom: "选择一个目录深入分析" } }
}
public enum StorageCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case cache, developer, downloads, media, documents, applications, other
    public var id: String { rawValue }
    public var title: String { switch self { case .cache: "缓存与临时产物"; case .developer: "开发文件"; case .downloads: "下载内容"; case .media: "图像与影音"; case .documents: "文档与资料"; case .applications: "应用与支持文件"; case .other: "其他文件" } }
    public var symbol: String { switch self { case .cache: "archivebox"; case .developer: "hammer"; case .downloads: "arrow.down.circle"; case .media: "photo.on.rectangle"; case .documents: "doc.text"; case .applications: "app.badge"; case .other: "folder" } }
}
public enum StorageSort: String, CaseIterable, Sendable { case allocated, logical, modified }
public struct VolumeSnapshot: Sendable {
    public let name: String
    public let path: String
    public let capacityBytes: UInt64?
    public let availableBytes: UInt64?
    public let isInternal: Bool?
    public init(name: String, path: String, capacityBytes: UInt64?, availableBytes: UInt64?, isInternal: Bool?) {
        self.name = name; self.path = path; self.capacityBytes = capacityBytes; self.availableBytes = availableBytes; self.isInternal = isInternal
    }
}
public struct CategorySummary: Sendable, Identifiable {
    public var id: String { category.id }
    public let category: StorageCategory
    public let allocatedBytes: UInt64
    public let logicalBytes: UInt64
    public let fileCount: UInt64
    public init(category: StorageCategory, allocatedBytes: UInt64, logicalBytes: UInt64, fileCount: UInt64) { self.category = category; self.allocatedBytes = allocatedBytes; self.logicalBytes = logicalBytes; self.fileCount = fileCount }
}
public struct StorageDashboard: Sendable {
    public let summary: ScanSummary
    public let categories: [CategorySummary]
    public let topFolders: [Entry]
    public let largeFileCount: UInt64
    public let previewCandidateCount: UInt64
    public let previewCandidateBytes: UInt64
    public let issues: [Entry]
    public init(summary: ScanSummary, categories: [CategorySummary], topFolders: [Entry], largeFileCount: UInt64, previewCandidateCount: UInt64, previewCandidateBytes: UInt64, issues: [Entry]) {
        self.summary = summary; self.categories = categories; self.topFolders = topFolders; self.largeFileCount = largeFileCount; self.previewCandidateCount = previewCandidateCount; self.previewCandidateBytes = previewCandidateBytes; self.issues = issues
    }
}
