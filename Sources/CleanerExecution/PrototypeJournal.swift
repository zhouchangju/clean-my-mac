import Foundation
import Darwin
import CleanerDomain

// Internal fixture prototype. No production permission is conferred by a journal.
final class PrototypeJournal {
    struct Event: Codable, Equatable {
        let itemID: UUID
        let phase: String
        let source: String
        let stagedName: String?
        let trashPath: String?
    }
    let directory: URL
    let fileURL: URL
    private let lockFD: Int32
    private let journalFD: Int32
    private let directoryFD: Int32
    private(set) var scheduled = Set<UUID>()
    init(authorization: ProbeAuthorization, transactionID: UUID = UUID()) throws {
        let ownedTestRoot = authorization.root
        let rootFD = try authorization.openOwnedRoot()
        defer { close(rootFD) }
        lockFD = openat(rootFD, ".lmc-execution-lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw CleanerError(.insufficientJournalSpace, "锁文件不可建立") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); throw CleanerError(.alreadyRunning, "已有事务持锁") }
        let name = ".lmc-journal-" + transactionID.uuidString
        guard mkdirat(rootFD, name, 0o700) == 0 else { close(lockFD); throw CleanerError(.invalidPlan, "事务已存在，不重复调度") }
        directory = ownedTestRoot.appendingPathComponent(name)
        directoryFD = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { close(lockFD); throw CleanerError(.insufficientJournalSpace, "journal目录不可打开") }
        journalFD = openat(directoryFD, "events.jsonl", O_CREAT | O_EXCL | O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard journalFD >= 0 else { close(lockFD); close(directoryFD); throw CleanerError(.insufficientJournalSpace, "journal文件不可建立") }
        fileURL = directory.appendingPathComponent("events.jsonl")
        guard fsync(journalFD) == 0, fsync(directoryFD) == 0, fsync(rootFD) == 0 else {
            close(lockFD); close(journalFD); close(directoryFD); throw CleanerError(.insufficientJournalSpace, "journal创建刷盘失败")
        }
    }
    deinit { close(journalFD); close(directoryFD); flock(lockFD, LOCK_UN); close(lockFD) }
    func append(_ event: Event) throws {
        var data = try JSONEncoder().encode(event); data.append(10)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(journalFD, raw.baseAddress!.advanced(by: offset), raw.count-offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw CleanerError(.insufficientJournalSpace, "journal写入失败；停止变更") }
                offset += n
            }
        }
        guard fsync(journalFD) == 0 else { throw CleanerError(.insufficientJournalSpace, "journal刷盘失败；停止变更") }
    }
    func schedule(_ id: UUID, source: String) throws {
        guard !scheduled.contains(id) else { throw CleanerError(.invalidPlan, "同项不会再次调度") }
        try append(Event(itemID: id, phase: "intent", source: source, stagedName: nil, trashPath: nil))
        scheduled.insert(id)
    }
    static func read(_ url: URL) throws -> [Event] {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CleanerError(.interruptedUnknown, "journal不可读") }
        defer { close(fd) }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0, errno == EINTR { continue }
            guard n >= 0 else { throw CleanerError(.interruptedUnknown, "journal读取失败") }
            if n == 0 { break }; data.append(contentsOf: buffer.prefix(n))
            guard data.count <= 16 * 1024 * 1024 else { throw CleanerError(.interruptedUnknown, "journal超过原型上限") }
        }
        guard data.isEmpty || data.last == 10 else { throw CleanerError(.interruptedUnknown, "journal尾部不完整；不得重删") }
        return try data.split(separator: 10).map { try JSONDecoder().decode(Event.self, from: Data($0)) }
    }
    static func recoveryDisposition(_ events: [Event], item: UUID) -> ItemState {
        guard let last = events.last(where: { $0.itemID == item }) else { return .interruptedUnknown }
        switch last.phase {
        case "purged": return .purged
        case "trashed": return .trashed
        case "restored": return .restored
        case "staged": return .staged
        default: return .interruptedUnknown // Intent alone is never a retry instruction.
        }
    }
}
