import Foundation
import Darwin
import CleanerDomain
import CleanerCore
import CleanerMacPlatform
import AIAdvisorCore

@main struct CLI {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2) }
    }
    static func value(_ flag: String, args: [String]) throws -> String {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, !args[i + 1].hasPrefix("--") else { throw CleanerError(.invalidInput, "缺少参数 \(flag)") }; return args[i + 1]
    }
    static func optionalValue(_ flag: String, args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, !args[i + 1].hasPrefix("--") else { return nil }; return args[i + 1]
    }
    static func stateURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalMacCleaner", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); return base
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { throw CleanerError(.invalidInput, "用法：lmc scan --root <目录> --json；plan --scan <UUID> --selection <UUID,...> --action trash|purge；inspect-receipt <文件>") }
        switch command {
        case "scan":
            let path = try value("--root", args: args)
            let scope = try MacFileReader().scope(path: path)
            let store = try SQLiteScanStore(url: try stateURL().appendingPathComponent("index.sqlite"))
            let coordinator = ScanCoordinator(store: store, rules: RuleEngine())
            let run = try await coordinator.scan(scope: scope) { _ in }
            FileHandle.standardOutput.write(try Codec.encoder().encode(run)); print("")
        case "plan":
            // Only plans constructed from the private local scan index are accepted.
            let scanString = try value("--scan", args: args)
            guard let scanID = UUID(uuidString: scanString), let action = CleanupAction(rawValue: try value("--action", args: args)) else { throw CleanerError(.invalidInput, "scan/action非法") }
            let ids = try value("--selection", args: args).split(separator: ",").map { part -> UUID in
                guard let id = UUID(uuidString: String(part)) else { throw CleanerError(.invalidInput, "selection非法") }; return id
            }
            let store = try SQLiteScanStore(url: try stateURL().appendingPathComponent("index.sqlite"))
            guard let run = try await store.run(id: scanID) else { throw CleanerError(.invalidInput, "找不到扫描") }
            let entries = try await store.entries(scanID: scanID, ids: Set(ids))
            var selection = Selection(scanID: scanID)
            for e in entries { try selection.set(e, selected: true) }
            guard selection.ids.count == Set(ids).count else { throw CleanerError(.invalidInput, "找不到选择项") }
            let plan = try Planner.make(run: run, entries: entries, selection: selection, action: action, ignoreRevision: 0)
            FileHandle.standardOutput.write(try Codec.encoder().encode(plan)); print("")
        case "inspect-receipt":
            guard args.count == 2 else { throw CleanerError(.invalidInput, "需指定本地收据") }
            let transaction = try Codec.decoder().decode(Transaction.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            FileHandle.standardOutput.write(try Codec.encoder().encode(transaction)); print("")
        case "air":
            switch args.count > 1 ? args[1] : "" {
            case "list":
                let runtimes = await RuntimeDetector().detectAll()
                FileHandle.standardOutput.write(try Codec.encoder().encode(runtimes)); print("")
            case "default":
                let rest = Array(args.dropFirst(2))
                if let id = rest.first {
                    guard AIRuntimeCatalog.spec(id: id) != nil else { throw CleanerError(.invalidInput, "未知的 runtime id：\(id)（可用：\(AIRuntimeCatalog.ids.joined(separator: "、"))）") }
                    guard RuntimePreferences.writeDefault(id) else { throw CleanerError(.invalidInput, "写入默认 runtime 失败") }
                }
                FileHandle.standardOutput.write(try Codec.encoder().encode(RuntimePreferences.readDefault())); print("")
            case "analyze":
                let rest = Array(args.dropFirst(2))
                let runtimeID = try value("--runtime", args: rest)
                var timeout: TimeInterval? = nil
                if let raw = optionalValue("--timeout", args: rest) {
                    guard let seconds = TimeInterval(raw), seconds > 0 else { throw CleanerError(.invalidInput, "--timeout 需为正整数秒") }
                    timeout = seconds
                }
                let context: String
                if let path = optionalValue("--context-file", args: rest) {
                    context = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
                } else if isatty(0) == 0 { // stdin 为管道/重定向时读取
                    context = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                } else { throw CleanerError(.invalidInput, "缺少分析上下文：请用 --context-file <路径> 或通过 stdin 管道传入") }
                guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CleanerError(.invalidInput, "分析上下文为空") }
                let result = try await AIAnalysisRunner().run(runtimeID: runtimeID, prompt: context, workDir: nil, timeout: timeout)
                FileHandle.standardOutput.write(Data(result.stdoutText.utf8)); print("")
            default: throw CleanerError(.invalidInput, "用法：lmc air list；air default [<id>]；air analyze --runtime <id> [--context-file <路径>] [--timeout <秒>]")
            }
        default: throw CleanerError(.invalidInput, "不支持的命令；生产CLI没有执行或删除入口")
        }
    }
}
