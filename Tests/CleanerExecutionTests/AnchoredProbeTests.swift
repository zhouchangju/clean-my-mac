import Testing
import Foundation
import Darwin
import CryptoKit
import CleanerDomain
import CleanerTestSupport
@testable import CleanerExecution

private func digest(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
private func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }

struct AnchoredProbeTests {
    @Test func fixedLeafStageRestoreAndNoExpansion() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        let old = try f.file("cache/selected", contents: Data("selected-original".utf8)); let expected = try digest(old)
        let p = try AnchoredProbe(authorization: authorization(f)); let s = try p.snapshot("cache/selected")
        let staged = try p.stage(s, afterPrecheck: { _ = try f.file("cache/new", contents: Data("new-preserved".utf8)) })
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(try digest(p.stagingURL.appendingPathComponent(staged.name)) == expected)
        try p.restore(staged)
        #expect(try digest(old) == expected)
        #expect(try String(contentsOf: f.root.appendingPathComponent("cache/new"), encoding: .utf8) == "new-preserved")
    }
    @Test func leafReplacementRejectedWithoutTouchingReplacement() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        let old = try f.file("cache/selected"); let p = try AnchoredProbe(authorization: authorization(f)); let s = try p.snapshot("cache/selected")
        #expect(rejects { _ = try p.stage(s, afterPrecheck: {
            try FileManager.default.moveItem(at: old, to: f.root.appendingPathComponent("cache/original"))
            _ = try f.file("cache/selected", contents: Data("replacement".utf8))
        }) })
        #expect(try String(contentsOf: old, encoding: .utf8) == "replacement")
        #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("cache/original").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: p.stagingURL.path).isEmpty)
    }
    @Test func parentExchangeRejectedAndSentinelPreserved() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        _ = try f.file("cache/selected"); let sentinel = try f.file("outside/sentinel", contents: Data("never-change".utf8)); let hash = try digest(sentinel)
        let p = try AnchoredProbe(authorization: authorization(f)); let s = try p.snapshot("cache/selected")
        #expect(rejects { _ = try p.stage(s, afterPrecheck: {
            try FileManager.default.moveItem(at: f.root.appendingPathComponent("cache"), to: f.root.appendingPathComponent("old-cache"))
            try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("cache"), withDestinationURL: f.root.appendingPathComponent("outside"))
        }) })
        #expect(try digest(sentinel) == hash)
        #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("old-cache/selected").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: p.stagingURL.path).isEmpty)
    }
    @Test func postMoveMismatchRetainedAndNeverPurged() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        _ = try f.file("selected"); let p = try AnchoredProbe(authorization: authorization(f)); let s = try p.snapshot("selected")
        #expect(rejects { _ = try p.stage(s, afterMove: {
            let names = try FileManager.default.contentsOfDirectory(atPath: p.stagingURL.path)
            try Data("changed-size-after-stage".utf8).write(to: p.stagingURL.appendingPathComponent(names[0]))
        }) })
        let names = try FileManager.default.contentsOfDirectory(atPath: p.stagingURL.path)
        #expect(names.count == 1)
        #expect(try String(contentsOf: p.stagingURL.appendingPathComponent(names[0]), encoding: .utf8) == "changed-size-after-stage")
    }
    @Test func restoreNeverOverwritesAndPurgeOnlyStagedLeaf() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        let old = try f.file("selected"); _ = try f.file("unselected", contents: Data("preserve".utf8))
        let p = try AnchoredProbe(authorization: authorization(f)); let staged = try p.stage(p.snapshot("selected"))
        _ = try f.file("selected", contents: Data("occupied".utf8))
        #expect(rejects { try p.restore(staged) })
        #expect(try String(contentsOf: old, encoding: .utf8) == "occupied")
        try p.purge(staged)
        #expect(try String(contentsOf: f.root.appendingPathComponent("unselected"), encoding: .utf8) == "preserve")
        #expect(try FileManager.default.contentsOfDirectory(atPath: p.stagingURL.path).isEmpty)
    }
    @Test func unsafeKindsAndScopeRejected() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        let original = try f.file("original"); try FileManager.default.linkItem(at: original, to: f.root.appendingPathComponent("hard"))
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("link"), withDestinationURL: original)
        let p = try AnchoredProbe(authorization: authorization(f))
        #expect(rejects { _ = try p.snapshot("hard") }); #expect(rejects { _ = try p.snapshot("link") })
        #expect(rejects { _ = try p.snapshot("../original") }); #expect(rejects { _ = try p.snapshot("/original") })
        #expect(rejects { _ = try AnchoredProbe(authorization: ProbeAuthorization(root: f.root.appendingPathComponent("link"), token: f.token, device: f.rootDevice, inode: f.rootInode)) })
        #expect(rejects { _ = try AnchoredProbe(authorization: ProbeAuthorization(root: FileManager.default.homeDirectoryForCurrentUser, token: f.token, device: f.rootDevice, inode: f.rootInode)) })
    }
}
