import Foundation
import Darwin
import CleanerDomain

public struct MacFileReader: FileSystemReader {
    public init() {}
    private func failure(_ message: String) -> CleanerError {
        CleanerError(errno == EACCES || errno == EPERM ? .permissionDenied : .identityChanged, message)
    }
    private func parts(_ path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.utf8.contains(0) else { throw CleanerError(.scopeEscape, "路径越界") }
        let result = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if path.isEmpty { return [] }
        guard result.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw CleanerError(.scopeEscape, "非法路径段") }
        return result
    }
    private func rootFD(_ path: String) throws -> Int32 {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw CleanerError(.invalidInput, "必须选择绝对目录路径") }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("无法打开文件系统根") }
        do {
            for segment in path.split(separator: "/") {
                guard segment != "..", segment != "." else { throw CleanerError(.scopeEscape, "非法根路径") }
                let next = openat(fd, String(segment), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw failure("目录不可读或包含符号链接") }
                close(fd); fd = next
            }
            return fd
        } catch { close(fd); throw error }
    }
    private func makeIdentity(_ s: stat, chain: [AncestorIdentity]) -> FileIdentity {
        let kind: FileKind
        switch s.st_mode & S_IFMT { case S_IFREG: kind = .regular; case S_IFDIR: kind = .directory; case S_IFLNK: kind = .symlink; default: kind = .other }
        return FileIdentity(volumeID: String(s.st_dev), device: UInt64(UInt32(bitPattern: s.st_dev)), inode: s.st_ino, kind: kind, size: UInt64(max(0, s.st_size)), mtimeNs: String(Int64(s.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(s.st_mtimespec.tv_nsec)), ctimeNs: String(Int64(s.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(s.st_ctimespec.tv_nsec)), linkCount: UInt64(s.st_nlink), ownerUID: UInt64(s.st_uid), parentChain: chain)
    }
    public func scope(path: String) throws -> ScanScope {
        var original = stat()
        guard lstat(path, &original) == 0, original.st_mode & S_IFMT == S_IFDIR else { throw CleanerError(.invalidInput, "扫描根必须是实际目录，不能是链接") }
        guard let resolved = realpath(path, nil) else { throw failure("无法解析扫描根") }
        let canonical = String(cString: resolved); free(resolved)
        let fd = try rootFD(canonical); defer { close(fd) }
        var s = stat(); guard fstat(fd, &s) == 0, s.st_dev == original.st_dev, s.st_ino == original.st_ino else { throw CleanerError(.identityChanged, "解析时根身份改变") }
        return ScanScope(rootPath: canonical, rootIdentity: makeIdentity(s, chain: []))
    }

    public func identity(scope: ScanScope, relativePath: String) throws -> FileIdentity { try metadata(scope: scope, relativePath: relativePath).identity }
    public func metadata(scope: ScanScope, relativePath: String) throws -> (identity: FileIdentity, allocated: UInt64) {
        let segments = try parts(relativePath)
        var fd = try rootFD(scope.rootPath); defer { close(fd) }
        var root = stat(); guard fstat(fd, &root) == 0, makeIdentity(root, chain: []).sameObject(as: scope.rootIdentity) else { throw CleanerError(.identityChanged, "扫描根身份已改变") }
        var chain: [AncestorIdentity] = []
        if segments.isEmpty { return (makeIdentity(root, chain: []), UInt64(max(0, root.st_blocks)) * 512) }
        chain.append(AncestorIdentity(relativePath: "", device: UInt64(UInt32(bitPattern: root.st_dev)), inode: root.st_ino))
        var accumulated = ""
        for segment in segments.dropLast() {
            let next = openat(fd, segment, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw failure("祖先目录不可读或包含链接") }
            var s = stat(); guard fstat(next, &s) == 0 else { close(next); throw failure("祖先身份不可读") }
            guard s.st_dev == root.st_dev else { close(next); throw CleanerError(.unsupportedVolume, "扫描停止于跨卷边界") }
            close(fd); fd = next; accumulated = accumulated.isEmpty ? segment : accumulated + "/" + segment
            chain.append(AncestorIdentity(relativePath: accumulated, device: UInt64(UInt32(bitPattern: s.st_dev)), inode: s.st_ino))
        }
        var s = stat(); guard fstatat(fd, segments.last!, &s, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("文件元数据不可读") }
        guard s.st_dev == root.st_dev else { throw CleanerError(.unsupportedVolume, "扫描停止于跨卷边界") }
        return (makeIdentity(s, chain: chain), UInt64(max(0, s.st_blocks)) * 512)
    }
    /// Only stats each ancestor's .git marker. Never opens its contents or follows it.
    public func repositoryAncestor(scope: ScanScope) throws -> Bool {
        guard scope.rootPath.hasPrefix("/"), !scope.rootPath.utf8.contains(0) else { throw CleanerError(.scopeEscape,"非法扫描根") }
        let components = scope.rootPath.split(separator:"/").map(String.init)
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw CleanerError(.scopeEscape,"非法祖先路径") }
        var fd = open("/",O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("祖先根不可读") }
        defer { close(fd) }
        var found = false
        for component in components {
            var marker = stat()
            if fstatat(fd,".git",&marker,AT_SYMLINK_NOFOLLOW) == 0 { found = true }
            else if errno != ENOENT { throw failure("无法核实祖先代码仓库标记") }
            let next = openat(fd,component,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw failure("祖先目录不可读或已改变") }
            close(fd); fd = next
        }
        var root = stat()
        guard fstat(fd,&root) == 0, makeIdentity(root,chain:[]).sameObject(as:scope.rootIdentity) else { throw CleanerError(.identityChanged,"扫描根祖先链已改变") }
        return found
    }
    public func isRepository(scope: ScanScope, relativePath: String) throws -> Bool {
        try directory(scope:scope,relativePath:relativePath).hasRepositoryMarker()
    }
    public func directory(scope: ScanScope, relativePath: String) throws -> DirectoryCursor {
        let expected = try identity(scope: scope, relativePath: relativePath)
        guard expected.kind == .directory else { throw CleanerError(.invalidInput, "不是目录") }
        var fd = try rootFD(scope.rootPath)
        do {
            for segment in try parts(relativePath) {
                let next = openat(fd, segment, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw failure("目录不可读") }
                close(fd); fd = next
                var s = stat(); guard fstat(fd, &s) == 0, UInt64(UInt32(bitPattern: s.st_dev)) == scope.rootIdentity.device.value else { throw CleanerError(.unsupportedVolume, "跨卷目录") }
            }
            var s = stat(); guard fstat(fd, &s) == 0, makeIdentity(s, chain: []).sameObject(as: expected) else { throw CleanerError(.identityChanged, "目录身份变化") }
            guard let dir = fdopendir(fd) else { throw failure("无法枚举目录") }
            return DirectoryCursor(dir)
        } catch { close(fd); throw error }
    }
}

/// A single directory descriptor; callers consume one name at a time with bounded buffering.
public final class DirectoryCursor: @unchecked Sendable {
    private let directory: UnsafeMutablePointer<DIR>
    fileprivate init(_ directory: UnsafeMutablePointer<DIR>) { self.directory = directory }
    deinit { closedir(directory) }
    fileprivate func hasRepositoryMarker() throws -> Bool {
        var s = stat()
        if fstatat(dirfd(directory), ".git", &s, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        if errno == ENOENT { return false }
        throw CleanerError(.permissionDenied,"无法核实代码仓库标记")
    }
    public func next() throws -> String? {
        errno = 0
        while let ent = readdir(directory) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { return name }
            errno = 0
        }
        guard errno == 0 else { throw CleanerError(.permissionDenied, "目录枚举不完整") }
        return nil
    }
}
