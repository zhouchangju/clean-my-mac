import Foundation
import Darwin
import CleanerDomain

public final class Fixture: @unchecked Sendable {
    public let root: URL
    public let token = UUID().uuidString
    private let inode: UInt64
    private let device: UInt64
    public var rootDevice: UInt64 { device }
    public var rootInode: UInt64 { inode }
    public init() throws {
        let temporary = FileManager.default.temporaryDirectory.path
        guard let resolved = realpath(temporary, nil) else { throw CleanerError(.invalidInput, "无法定位临时目录") }
        let canonical = String(cString: resolved); free(resolved)
        root = URL(fileURLWithPath: canonical).appendingPathComponent("LMC-Fixture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var st = stat(); guard lstat(root.path, &st) == 0 else { throw CleanerError(.invalidInput, "fixture stat失败") }
        inode = st.st_ino; device = UInt64(st.st_dev)
        try Data(token.utf8).write(to: root.appendingPathComponent(".lmc-fixture-marker"))
    }
    public func file(_ path: String, contents: Data = Data("fixture".utf8)) throws -> URL {
        guard valid(path) else { throw CleanerError(.scopeEscape, "fixture path非法") }
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try contents.write(to: url); return url
    }
    public func sparse(_ path: String, size: Int64) throws -> URL {
        let url = try file(path, contents: Data()); let fd = open(url.path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw CleanerError(.permissionDenied, "sparse open失败") }; defer { close(fd) }
        guard ftruncate(fd, size) == 0 else { throw CleanerError(.invalidInput, "sparse truncate失败") }; return url
    }
    public func verify() throws {
        var st = stat()
        guard root.lastPathComponent.hasPrefix("LMC-Fixture-"), lstat(root.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_ino == inode, UInt64(st.st_dev) == device,
              try Data(contentsOf: root.appendingPathComponent(".lmc-fixture-marker")) == Data(token.utf8) else { throw CleanerError(.protected, "非持有的fixture，拒绝操作") }
    }
    public func cleanup() throws { try verify(); try FileManager.default.removeItem(at: root) }
    private func valid(_ path: String) -> Bool { !path.hasPrefix("/") && !path.split(separator: "/").contains("..") }
    public func populateBoundaries() throws {
        _ = try file("plain.bin", contents: Data(repeating: 65, count: 4096))
        _ = try sparse("large.sparse", size: 512 * 1024 * 1024)
        _ = try file(".ssh/private-sentinel", contents: Data("must-not-read".utf8))
        _ = try file("project/.git/config", contents: Data("protected-code".utf8))
        try FileManager.default.linkItem(at: root.appendingPathComponent("plain.bin"), to: root.appendingPathComponent("hardlink.bin"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside-link").path, withDestinationPath: "/outside-LMC-sentinel-do-not-resolve")
        _ = try file("denied/child.bin")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent("denied").path)
    }
    public static let expectedBoundaryPaths = Set(["plain.bin", "large.sparse", ".ssh", "project", "project/.git", "hardlink.bin", "outside-link", "denied", ".lmc-fixture-marker"])
}
