import Foundation

struct AppState: Codable {
    var firstRunDone = false
    var lastRun: Date?
    var lastResults: [SortResult] = []
    var ignoredSecrets: [String] = []  // full paths the user said to stop warning about
}

/// Reads and writes rules.json and state.json in one directory (normally ~/Library/Application Support/Hangover).
final class Store {
    let dir: URL
    let home: URL
    private var rulesURL: URL { dir.appendingPathComponent("rules.json") }
    private var backupURL: URL { dir.appendingPathComponent("rules.json.bak") }
    private var stateURL: URL { dir.appendingPathComponent("state.json") }
    private let lock = NSLock()

    init(dir: URL, home: URL) {
        self.dir = dir
        self.home = home
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Loading checks everything except whether watched folders exist right now: an unplugged
    /// drive must not look like a broken rules file. (The sorter reports a missing folder per run.)
    private func decodeValid(_ url: URL) throws -> RuleSet {
        let set = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
        return try validate(set, home: home, fileExists: { _ in true })
    }

    /// Current rules. A missing file becomes the starter rules; a broken one falls back to the backup
    /// (or starter rules) and is kept as rules.json.corrupt-<time> so nothing the user wrote is lost.
    func loadRules(lastGood: RuleSet? = nil) -> (RuleSet, warning: String?) {
        lock.lock(); defer { lock.unlock() }
        if !exists(rulesURL) {
            let starter = starterRules(screenshotPrefix: screenshotNamePrefix())
            try? write(starter)
            return (starter, nil)
        }
        do {
            return (try decodeValid(rulesURL), nil)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.copyItem(at: rulesURL, to: dir.appendingPathComponent("rules.json.corrupt-\(stamp)"))
            let fallback: RuleSet
            let source: String
            if let good = lastGood {
                fallback = good
                source = "the rules it was already running with"
            } else if let bak = try? decodeValid(backupURL) {
                fallback = bak
                source = "your previous rules"
            } else {
                fallback = starterRules(screenshotPrefix: screenshotNamePrefix())
                source = "the starter rules"
            }
            try? write(fallback)
            return (fallback, "Your rules file couldn't be read (\(friendlyError(error))), so Hangover is using \(source). "
                    + "The unreadable file was kept as rules.json.corrupt-\(stamp).")
        }
    }

    private func write(_ set: RuleSet) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(set).write(to: rulesURL, options: .atomic)
    }

    /// Validates, keeps the previous file as rules.json.bak, then writes atomically.
    func saveRules(_ set: RuleSet) throws -> RuleSet {
        let clean = try validate(set, home: home, fileExists: exists)
        lock.lock(); defer { lock.unlock() }
        if exists(rulesURL) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: rulesURL, to: backupURL)
        }
        try write(clean)
        return clean
    }

    func importRules(from url: URL) throws -> RuleSet {
        let set = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
        return try saveRules(set)
    }

    func exportRules(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(loadRules().0).write(to: url, options: .atomic)
    }

    func loadState() -> AppState {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(AppState.self, from: data) else { return AppState() }
        return s
    }

    func saveState(_ s: AppState) {
        try? JSONEncoder().encode(s).write(to: stateURL, options: .atomic)
    }
}

/// Latest-run problems: every error, plus secrets the user hasn't silenced.
func problems(from results: [SortResult], ignoring: [String], folderPaths: [String: URL])
    -> (errors: [SortResult], secrets: [SortResult]) {
    let errors = results.filter { $0.status == .error }
    let secrets = results.filter { r in
        guard r.status == .secret else { return false }
        guard let dir = folderPaths[r.folder] else { return true }
        return !ignoring.contains(dir.appendingPathComponent(r.file).path)
    }
    return (errors, secrets)
}
