import Testing
import Foundation
import Darwin
import CleanerDomain
import CleanerTestSupport
@testable import CleanerExecution

struct PrototypeJournalTests {
    @Test func lockDurabilityAtMostOnceAndUnknownNeverRetries() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        let j = try PrototypeJournal(authorization: authorization(f))
        do { _ = try PrototypeJournal(authorization: authorization(f)); Issue.record("second lock unexpectedly acquired") } catch let e as CleanerError { #expect(e.code == .alreadyRunning) }
        let id = UUID(); try j.schedule(id, source: "cache/selected")
        do { try j.schedule(id, source: "cache/selected"); Issue.record("duplicate unexpectedly scheduled") } catch let e as CleanerError { #expect(e.code == .invalidPlan) }
        let events = try PrototypeJournal.read(j.fileURL)
        #expect(events.count == 1)
        #expect(PrototypeJournal.recoveryDisposition(events, item: id) == .interruptedUnknown)
        var st = stat(); #expect(lstat(j.fileURL.path, &st) == 0); #expect(st.st_mode & 0o777 == 0o600)
        #expect(lstat(j.directory.path, &st) == 0); #expect(st.st_mode & 0o777 == 0o700)
    }
    @Test func truncatedJournalRejectsRecovery() throws {
        let f = try Fixture(); defer { try? f.cleanup() }; try f.verify()
        let j = try PrototypeJournal(authorization: authorization(f)); try j.schedule(UUID(), source: "selected")
        let fd = open(j.fileURL.path, O_WRONLY | O_APPEND | O_NOFOLLOW); #expect(fd >= 0); defer { close(fd) }
        #expect(write(fd, "{", 1) == 1); #expect(fsync(fd) == 0)
        do { _ = try PrototypeJournal.read(j.fileURL); Issue.record("partial journal accepted") } catch let e as CleanerError { #expect(e.code == .interruptedUnknown) }
    }
}
