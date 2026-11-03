// Dry-run preview from the command line: prints what would move as JSON. Never moves anything.
// Build: swiftc Sources/Core/*.swift scripts/preview/main.swift -o .build/preview
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: preview <rules.json>\n".utf8))
    exit(2)
}
let set = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let log = Logger(url: FileManager.default.temporaryDirectory.appendingPathComponent("hangover-preview.log"))
let sorter = Sorter(fs: RealFileSystem(), log: log, home: FileManager.default.homeDirectoryForCurrentUser,
                    now: Date.init, calendar: .current)
let results = sorter.run(set, apply: false, trigger: "cli preview")
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try enc.encode(results), encoding: .utf8)!)
