import Foundation
import Testing
import CleanerDomain
import CleanerCore
import CleanerMacPlatform
import CleanerTestSupport

@Test func newAncestorRepositoryInvalidatesOldPlan() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    _ = try fixture.sparse("src/large", size: 536870912)
    let state = try Fixture(); defer { try? state.cleanup() }
    let reader = MacFileReader(); let scope = try reader.scope(path: fixture.root.appendingPathComponent("src").path)
    let store = try SQLiteScanStore(url: state.root.appendingPathComponent("index.sqlite"))
    let run = try await ScanCoordinator(store: store, rules: RuleEngine()).scan(scope: scope)
    let entry = try #require(try await store.page(scanID: run.id, offset: 0, limit: 100).first { $0.relativePath == "large" })
    var selection = Selection(scanID: run.id); try selection.set(entry, selected: true)
    let plan = try Planner.make(run: run, entries: [entry], selection: selection, action: .trash, ignoreRevision: 0)
    _ = try fixture.file(".git", contents: Data("gitdir: unrelated".utf8))
    #expect(throws: CleanerError.self) { try MacPreflight().validate(plan: plan, run: run, selectionRevision: selection.revision, ignoreRevision: 0) }
    #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("src/large").path))
}
