import Foundation
import Darwin
import CleanerDomain

// No public constructor or production route. Tests must supply the Fixture's
// creation-time identity and unpredictable token, never identity from a new stat.
struct ProbeAuthorization {
    let root: URL
    let token: String
    let device: UInt64
    let inode: UInt64
    func openOwnedRoot() throws -> Int32 {
        guard root.lastPathComponent.hasPrefix("LMC-Fixture-"), UUID(uuidString: token) != nil,
              root.standardizedFileURL != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL else {
            throw CleanerError(.protected, "必须是本次持有的fixture")
        }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CleanerError(.scopeEscape, "fixture根不可打开或为链接") }
        do {
            var st = stat()
            guard fstat(fd, &st) == 0, UInt64(st.st_dev) == device, st.st_ino == inode, st.st_uid == getuid(),
                  st.st_mode & 0o777 == 0o700 else { throw CleanerError(.protected, "fixture根身份或权限变化") }
            let marker = openat(fd, ".lmc-fixture-marker", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard marker >= 0 else { throw CleanerError(.protected, "fixture marker缺失") }; defer { close(marker) }
            guard fstat(marker, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_nlink == 1, st.st_uid == getuid(), st.st_size == token.utf8.count else {
                throw CleanerError(.protected, "fixture marker不可信")
            }
            var bytes = [UInt8](repeating: 0, count: token.utf8.count)
            guard read(marker, &bytes, bytes.count) == bytes.count, Data(bytes) == Data(token.utf8) else { throw CleanerError(.protected, "fixture token不匹配") }
            return fd
        } catch { close(fd); throw error }
    }
}
