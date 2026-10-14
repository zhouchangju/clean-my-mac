import Testing
import Foundation
import CryptoKit
import CleanerTestSupport
import CleanerDomain
@testable import CleanerExecution

struct PrototypeTrashTests {
    @Test func systemTrashReturnedURLAndReceiptRestore() throws {
        let f = try Fixture(); var cleanupAllowed = true; defer { if cleanupAllowed { try? f.cleanup() } }; try f.verify()
        let payload = Data("owned-trash-probe-unique-".utf8) + Data(UUID().uuidString.utf8)
        let original = try f.file("cache/unique-" + UUID().uuidString, contents: payload)
        let expected = SHA256.hash(data: payload)
        let relative = "cache/" + original.lastPathComponent
        let p = try AnchoredProbe(authorization: authorization(f))
        let j = try PrototypeJournal(authorization: authorization(f)); let id = UUID()
        try j.schedule(id, source: relative)
        let staged = try p.stage(p.snapshot(relative))
        try j.append(.init(itemID: id, phase: "staged", source: relative, stagedName: staged.name, trashPath: nil))
        try j.append(.init(itemID: id, phase: "trashIntent", source: relative, stagedName: staged.name, trashPath: nil))
        cleanupAllowed = false
        let receipt: AnchoredProbe.TrashReceipt
        do {
            receipt = try p.trash(staged, journal: j, itemID: id)
        } catch let error as CleanerDomain.CleanerError where error.code == .permissionDenied {
            // The system Trash capability probe failed BEFORE trashItem.
            #expect(SHA256.hash(data: try Data(contentsOf: p.stagingURL.appendingPathComponent(staged.name))) == expected)
            try p.restore(staged)
            cleanupAllowed = true
            print("BLOCKED systemTrashReturnedURLAndReceiptRestore: " + error.description + "; fixture stage restored; no system Trash write")
            return
        }
        // From this point every exit attempts only receipt-driven restore of our item.
        defer { try? p.restoreTrash(receipt) }
        try j.append(.init(itemID: id, phase: "trashed", source: relative, stagedName: staged.name, trashPath: receipt.returnedURL.path))
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(SHA256.hash(data: try Data(contentsOf: receipt.returnedURL)) == expected)
        try p.restoreTrash(receipt)
        cleanupAllowed = true
        try j.append(.init(itemID: id, phase: "restored", source: relative, stagedName: staged.name, trashPath: receipt.returnedURL.path))
        #expect(SHA256.hash(data: try Data(contentsOf: original)) == expected)
        #expect(!FileManager.default.fileExists(atPath: receipt.returnedURL.path))
        #expect(PrototypeJournal.recoveryDisposition(try PrototypeJournal.read(j.fileURL), item: id) == .restored)
    }
}
