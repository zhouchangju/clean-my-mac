import Foundation
import Darwin
import CleanerDomain

// Internal experiment only. Production ExecutionGate never calls this type.
final class AnchoredProbe {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let mtime: timespec
        let ctime: timespec
        static func == (a: Self, b: Self) -> Bool {
            a.device == b.device && a.inode == b.inode && a.size == b.size &&
            a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec &&
            a.ctime.tv_sec == b.ctime.tv_sec && a.ctime.tv_nsec == b.ctime.tv_nsec
        }
        func sameObject(_ other: Self) -> Bool { device == other.device && inode == other.inode }
    }
    struct Snapshot {
        let path: String
        let identity: Identity
        let ancestors: [Identity]
    }
    struct Staged {
        let snapshot: Snapshot
        let name: String
        let identity: Identity
    }
    let root: URL
    private let rootFD: Int32
    private let stageFD: Int32
    let stageName: String
    init(authorization: ProbeAuthorization) throws {
        root = authorization.root
        rootFD = try authorization.openOwnedRoot()
        stageName = ".lmc-stage-" + UUID().uuidString
        guard mkdirat(rootFD, stageName, 0o700) == 0 else { close(rootFD); throw CleanerError(.permissionDenied, "创建隔离目录失败") }
        stageFD = openat(rootFD, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stageFD >= 0 else { close(rootFD); throw CleanerError(.permissionDenied, "隔离目录打开失败") }
        var a = stat(); var b = stat()
        guard fstat(rootFD, &a) == 0, fstat(stageFD, &b) == 0, a.st_dev == b.st_dev,
              b.st_uid == getuid(), b.st_mode & 0o777 == 0o700 else {
            close(rootFD); close(stageFD); throw CleanerError(.unsupportedVolume, "隔离目录必须同卷且私有")
        }
    }
    deinit { close(rootFD); close(stageFD) }
    private func parts(_ path: String) throws -> [String] {
        let p = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !p.isEmpty, p.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }), !p[0].hasPrefix(".lmc-") else { throw CleanerError(.scopeEscape, "非法相对路径") }
        return p
    }
    private func value(_ st: stat) -> Identity { Identity(device: st.st_dev, inode: st.st_ino, size: st.st_size, mtime: st.st_mtimespec, ctime: st.st_ctimespec) }
    private func parent(_ path: String) throws -> (Int32, String, [Identity]) {
        let p = try parts(path)
        var fd = dup(rootFD); var chain: [Identity] = []
        do {
            var st = stat(); guard fstat(fd, &st) == 0 else { throw CleanerError(.identityChanged, "根身份不可读") }; let device = st.st_dev; chain.append(value(st))
            for segment in p.dropLast() {
                let next = openat(fd, segment, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw CleanerError(.scopeEscape, "祖先目录不可定位或已变成链接") }
                close(fd); fd = next
                guard fstat(fd, &st) == 0, st.st_dev == device else { throw CleanerError(.unsupportedVolume, "跨卷祖先禁止") }; chain.append(value(st))
            }
            return (fd, p.last!, chain)
        } catch { close(fd); throw error }
    }
    private func leaf(_ fd: Int32, _ name: String) throws -> Identity {
        var st = stat()
        guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { throw CleanerError(.identityChanged, "叶子不可读取") }
        guard st.st_mode & S_IFMT == S_IFREG, st.st_nlink == 1, st.st_uid == getuid() else { throw CleanerError(.protected, "仅允许本人单硬链接普通文件") }
        return value(st)
    }
    func snapshot(_ path: String) throws -> Snapshot {
        let (fd, name, chain) = try parent(path); defer { close(fd) }
        return Snapshot(path: path, identity: try leaf(fd, name), ancestors: chain)
    }
    private func chainMatches(_ a: [Identity], _ b: [Identity]) -> Bool { a.count == b.count && zip(a,b).allSatisfy { $0.sameObject($1) } }
    func stage(_ expected: Snapshot, afterPrecheck: () throws -> Void = {}, afterMove: () throws -> Void = {}) throws -> Staged {
        let (fd, name, chain) = try parent(expected.path); defer { close(fd) }
        guard chainMatches(chain, expected.ancestors), try leaf(fd,name) == expected.identity else { throw CleanerError(.identityChanged, "预检身份变化") }
        try afterPrecheck()
        let (checkFD, _, newChain) = try parent(expected.path); close(checkFD)
        guard chainMatches(newChain, expected.ancestors), try leaf(fd,name) == expected.identity else { throw CleanerError(.identityChanged, "移动前身份变化") }
        let stageLeaf = UUID().uuidString
        guard renameatx_np(fd, name, stageFD, stageLeaf, UInt32(RENAME_EXCL)) == 0 else { throw CleanerError(.identityChanged, "无覆盖隔离移动失败") }
        try afterMove()
        let actual = try leaf(stageFD, stageLeaf)
        guard actual.sameObject(expected.identity), actual.size == expected.identity.size,
              actual.mtime.tv_sec == expected.identity.mtime.tv_sec, actual.mtime.tv_nsec == expected.identity.mtime.tv_nsec else {
            throw CleanerError(.stagingMismatch, "隔离后身份错配；保留隔离对象，禁止永久处理")
        }
        return Staged(snapshot: expected, name: stageLeaf, identity: actual)
    }
    func restore(_ staged: Staged) throws {
        guard try leaf(stageFD, staged.name).sameObject(staged.identity) else { throw CleanerError(.stagingMismatch, "恢复对象身份不符") }
        let (fd, name, chain) = try parent(staged.snapshot.path); defer { close(fd) }
        guard chainMatches(chain, staged.snapshot.ancestors) else { throw CleanerError(.restoreConflict, "原祖先已变化") }
        guard renameatx_np(stageFD, staged.name, fd, name, UInt32(RENAME_EXCL)) == 0 else { throw CleanerError(.restoreConflict, "原路径占用；隔离对象保留") }
    }
    // Fixture prototype only; this is deliberately absent from the public API.
    func purge(_ staged: Staged) throws {
        guard try leaf(stageFD, staged.name) == staged.identity else { throw CleanerError(.stagingMismatch, "永久动作前对象变化") }
        guard unlinkat(stageFD, staged.name, 0) == 0 else { throw CleanerError(.permissionDenied, "固定隔离叶子移除失败") }
    }
    struct TrashReceipt {
        let staged: Staged
        let returnedURL: URL
        let identity: Identity
    }
    func trash(_ staged: Staged, journal: PrototypeJournal, itemID: UUID) throws -> TrashReceipt {
        // Read-only capability preflight. EPERM must be discovered BEFORE moving
        // anything into inaccessible system Trash; no permissions are requested.
        let trashDirectory = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: stagingURL, create: false)
        let probeFD = open(trashDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard probeFD >= 0 else { throw CleanerError(.permissionDenied, "系统Trash不可验证；动作未开始 errno=" + String(errno)) }
        close(probeFD)

        guard try leaf(stageFD, staged.name) == staged.identity else { throw CleanerError(.stagingMismatch, "Trash前对象变化") }
        // API requires a URL; this path-based step is an explicit unresolved
        // same-user adversary boundary, so production execution stays disabled.
        var returned: NSURL?
        try FileManager.default.trashItem(at: stagingURL.appendingPathComponent(staged.name), resultingItemURL: &returned)
        guard let returned else {
            try journal.append(.init(itemID: itemID, phase: "trashUnknown", source: staged.snapshot.path, stagedName: staged.name, trashPath: nil))
            throw CleanerError(.interruptedUnknown, "系统未返回Trash位置；不得重复执行")
        }
        // Persist the system receipt BEFORE any validation that may throw.
        try journal.append(.init(itemID: itemID, phase: "trashReturnedUnknown", source: staged.snapshot.path, stagedName: staged.name, trashPath: returned.filePathURL?.path ?? returned.absoluteString))
        guard let url = returned.filePathURL else { throw CleanerError(.interruptedUnknown, "系统Trash引用URL未能转成路径URL：" + returned.absoluteString!) }
        let fd = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CleanerError(.interruptedUnknown, "Trash返回父目录不可定位：" + url.path + " errno=" + String(errno)) }
        defer { close(fd) }
        let actual = try leaf(fd, url.lastPathComponent)
        guard actual.sameObject(staged.identity), actual.size == staged.identity.size else { throw CleanerError(.stagingMismatch, "Trash返回对象错配；停止") }
        return TrashReceipt(staged: staged, returnedURL: url, identity: actual)
    }
    func restoreTrash(_ receipt: TrashReceipt) throws {
        let trashFD = open(receipt.returnedURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard trashFD >= 0 else { throw CleanerError(.restoreConflict, "Trash目录不可读取") }
        defer { close(trashFD) }
        guard try leaf(trashFD, receipt.returnedURL.lastPathComponent) == receipt.identity else { throw CleanerError(.stagingMismatch, "Trash对象变化；不自动恢复") }
        let (fd, name, chain) = try parent(receipt.staged.snapshot.path); defer { close(fd) }
        guard chainMatches(chain, receipt.staged.snapshot.ancestors) else { throw CleanerError(.restoreConflict, "原祖先身份变化") }
        guard renameatx_np(trashFD, receipt.returnedURL.lastPathComponent, fd, name, UInt32(RENAME_EXCL)) == 0 else { throw CleanerError(.restoreConflict, "原位置占用或跨卷；不覆盖") }
    }
    var stagingURL: URL { root.appendingPathComponent(stageName) }
}
