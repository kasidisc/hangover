import Foundation

enum ResultStatus: String, Codable {
    case moved, wouldMove = "would_move", waiting, secret, error
}

struct SortResult: Codable, Equatable {
    var folder: String
    var status: ResultStatus
    var file: String
    var rule: String?
    var to: String?
    var detail: String?
}

struct FileFacts {
    var dayAdded: Date?
    var dayCreated: Date
    var modified: Date
}

protocol FileSystem {
    func contents(of url: URL) throws -> [URL]
    func isDirectory(_ url: URL) -> Bool?
    func isAppBundle(_ url: URL) -> Bool
    func isSymlink(_ url: URL) -> Bool
    func facts(_ url: URL) throws -> FileFacts
    func exists(_ url: URL) -> Bool
    func createDirectory(_ url: URL) throws
    func move(_ url: URL, to: URL) throws
}

struct RealFileSystem: FileSystem {
    private var fm: FileManager { .default }

    func contents(of url: URL) throws -> [URL] {
        try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    /// nil when macOS won't say (the sorter then leaves the item alone).
    func isDirectory(_ url: URL) -> Bool? {
        try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    }
    /// A real app has Contents/Info.plist; a plain folder that happens to end in ".app" doesn't.
    func isAppBundle(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path)
    }
    func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
    func facts(_ url: URL) throws -> FileFacts {
        let v = try url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey])
        let created = v.creationDate ?? Date()
        return FileFacts(dayAdded: v.addedToDirectoryDate, dayCreated: created, modified: v.contentModificationDate ?? created)
    }
    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
    func createDirectory(_ url: URL) throws { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
    /// moveItem refuses to replace an existing file, so a race can never overwrite anything.
    func move(_ url: URL, to: URL) throws { try fm.moveItem(at: url, to: to) }
}

/// Never overwrite: foo.png -> foo-2.png -> foo-3.png ...
func freeDestination(dir: URL, name: String, exists: (URL) -> Bool) -> URL {
    let first = dir.appendingPathComponent(name)
    if !exists(first) { return first }
    let ext = (name as NSString).pathExtension
    let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
    var n = 2
    while true {
        let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
        if !exists(candidate) { return candidate }
        n += 1
    }
}

final class Sorter {
    private let fs: FileSystem
    private let log: Logger
    private let home: URL
    private let now: () -> Date
    private let calendar: Calendar
    private let lock = NSLock()  // a scheduled run and "Sort now" never overlap

    init(fs: FileSystem, log: Logger, home: URL, now: @escaping () -> Date, calendar: Calendar) {
        self.fs = fs; self.log = log; self.home = home; self.now = now; self.calendar = calendar
    }

    func run(_ set: RuleSet, apply: Bool, trigger: String) -> [SortResult] {
        lock.lock(); defer { lock.unlock() }
        let mode = apply ? "APPLY" : "DRY RUN"
        let today = calendar.startOfDay(for: now())
        log.write("---- run start (\(mode), \(trigger)) ----")
        var all: [SortResult] = []
        for folder in set.folders where folder.enabled {
            let res = sort(folder, set.neverMove, apply: apply, today: today)
            let n = { (s: ResultStatus) in res.filter { $0.status == s }.count }
            log.write("[\(folder.name)] \(mode): \(n(.moved)) moved, \(n(.wouldMove)) would move, "
                      + "\(n(.waiting)) waiting until tomorrow, \(n(.secret)) secrets, \(n(.error)) errors")
            all += res
        }
        return all
    }

    private func sort(_ folder: WatchedFolder, _ never: NeverMove, apply: Bool, today: Date) -> [SortResult] {
        var results: [SortResult] = []
        let src = expandTilde(folder.path, home: home)
        let entries: [URL]
        do {
            entries = try fs.contents(of: src)
        } catch {
            let msg = "cannot read folder \(src.path): \(error.localizedDescription)"
            log.write("[\(folder.name)] ERROR \(msg)")
            return [SortResult(folder: folder.name, status: .error, file: src.path, rule: nil, to: nil, detail: msg)]
        }

        for url in entries {
            let name = url.lastPathComponent
            if isSkipped(name, never) || fs.isSymlink(url) { continue }
            guard let rule = firstMatchingRule(name, in: folder) else { continue }
            guard let isDir = fs.isDirectory(url) else { continue }  // unknown type: leave it alone
            if isDir && !(fileExtension(name) == "app" && rule.allowBundles == true && fs.isAppBundle(url)) {
                continue  // folders are never moved; only real .app bundles when the rule allows it
            }
            if fs.exists(src.appendingPathComponent(name + ".part")) {
                continue  // Firefox's placeholder for a download still in progress
            }
            if isSecret(name, never) {
                log.write("[\(folder.name)] SECRET left in place, file it somewhere safe by hand: \(name)")
                results.append(SortResult(folder: folder.name, status: .secret, file: name, rule: rule.name))
                continue
            }
            let facts: FileFacts
            do { facts = try fs.facts(url) } catch {
                log.write("[\(folder.name)] ERROR reading \(name): \(error.localizedDescription)")
                results.append(SortResult(folder: folder.name, status: .error, file: name, rule: rule.name,
                                          detail: error.localizedDescription))
                continue
            }
            // A download that finished after midnight was still being written today: it waits too.
            let base = folder.ageField == .added ? (facts.dayAdded ?? facts.dayCreated) : facts.dayCreated
            let day = max(base, facts.modified)
            if day >= today {
                results.append(SortResult(folder: folder.name, status: .waiting, file: name, rule: rule.name))
                continue
            }

            let destDir = expandTilde(rule.to, home: home)
            let target = freeDestination(dir: destDir, name: name, exists: fs.exists)
            if !apply {
                log.write("[\(folder.name)] WOULD MOVE (\(rule.name)) \(name) -> \(target.path)")
                results.append(SortResult(folder: folder.name, status: .wouldMove, file: name, rule: rule.name,
                                          to: target.path))
                continue
            }
            do {
                try fs.createDirectory(destDir)
                try fs.move(url, to: target)
            } catch {
                log.write("[\(folder.name)] ERROR moving \(name): \(error.localizedDescription)")
                results.append(SortResult(folder: folder.name, status: .error, file: name, rule: rule.name,
                                          to: target.path, detail: error.localizedDescription))
                continue
            }
            log.write("[\(folder.name)] MOVED (\(rule.name)) \(name) -> \(target.path)")
            results.append(SortResult(folder: folder.name, status: .moved, file: name, rule: rule.name, to: target.path))
        }
        return results
    }
}
