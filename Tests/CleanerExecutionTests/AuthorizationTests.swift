import Testing
import Foundation
import CleanerDomain
import CleanerTestSupport
@testable import CleanerExecution

func authorization(_ f: Fixture) -> ProbeAuthorization {
    ProbeAuthorization(root: f.root, token: f.token, device: f.rootDevice, inode: f.rootInode)
}
struct AuthorizationTests {
    @Test func wrongTokenIdentityAndUnownedRootsRejected() throws {
        let f = try Fixture(); defer { try? f.cleanup() }
        let a = authorization(f)
        for bad in [ProbeAuthorization(root: a.root, token: UUID().uuidString, device: a.device, inode: a.inode),
                    ProbeAuthorization(root: a.root, token: a.token, device: a.device, inode: a.inode + 1),
                    ProbeAuthorization(root: FileManager.default.temporaryDirectory, token: a.token, device: a.device, inode: a.inode)] {
            do { _ = try AnchoredProbe(authorization: bad); Issue.record("unowned root accepted") } catch { }
            do { _ = try PrototypeJournal(authorization: bad); Issue.record("unowned journal root accepted") } catch { }
        }
        let moved = f.root.deletingLastPathComponent().appendingPathComponent("LMC-Fixture-" + UUID().uuidString)
        try FileManager.default.moveItem(at: f.root, to: moved)
        defer { try? FileManager.default.removeItem(at: f.root); try? FileManager.default.moveItem(at: moved, to: f.root) }
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(a.token.utf8).write(to: f.root.appendingPathComponent(".lmc-fixture-marker"))
        do { _ = try AnchoredProbe(authorization: a); Issue.record("replacement root accepted") } catch { }
    }
}
