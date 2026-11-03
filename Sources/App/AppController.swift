import AppKit
import ServiceManagement

/// Owns the engine, the saved state and the hourly schedule. The menu bar and the panel both talk to this.
///
/// Threading: every sort and preview runs on `queue`; `state` is only read or changed on the main thread.
final class AppController {
    let store: Store
    let logger: Logger
    /// Serial queue for all sorting work (hourly timer, wake, menu, panel).
    let queue = DispatchQueue(label: "hangover.sort")
    private let sorter: Sorter
    private let previewSorter: Sorter
    private var timer: Timer?
    private(set) var state: AppState
    private let rulesLock = NSLock()
    private var lastGood: RuleSet?
    private var warning: String?
    var onChange: (() -> Void)?

    init(supportDir: URL, logURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        store = Store(dir: supportDir, home: home)
        logger = Logger(url: logURL)
        sorter = Sorter(fs: RealFileSystem(), log: logger, home: home, now: Date.init, calendar: .current)
        previewSorter = Sorter(fs: RealFileSystem(), log: Logger(url: URL(fileURLWithPath: "/dev/null")),
                               home: home, now: Date.init, calendar: .current)
        state = store.loadState()
        _ = rules
    }

    /// Current rules, re-read from disk so hand edits apply. A broken file falls back to the rules the
    /// app was already running with, and the warning stays visible until the next successful save.
    var rules: RuleSet {
        rulesLock.lock(); defer { rulesLock.unlock() }
        let (set, w) = store.loadRules(lastGood: lastGood)
        if let w = w { warning = w }
        lastGood = set
        return set
    }

    var loadWarning: String? {
        rulesLock.lock(); defer { rulesLock.unlock() }
        return warning
    }

    func folderPaths() -> [String: URL] {
        var out: [String: URL] = [:]
        for f in rules.folders { out[f.name] = expandTilde(f.path, home: store.home) }
        return out
    }

    func problemsNow() -> (errors: [SortResult], secrets: [SortResult]) {
        problems(from: state.lastResults, ignoring: state.ignoredSecrets, folderPaths: folderPaths())
    }

    func status() -> (lastRun: Date?, errorCount: Int, secretCount: Int, autoSort: Bool) {
        let p = problemsNow()
        return (state.lastRun, p.errors.count, p.secrets.count, rules.autoSort)
    }

    /// Runs one sort on the calling thread (call it on `queue`, or on main before the app starts).
    @discardableResult
    func sortNow(trigger: String = "manual") -> [SortResult] {
        let results = sorter.run(rules, apply: true, trigger: trigger)
        let commit = {
            self.state.lastRun = Date()
            self.state.lastResults = results
            self.store.saveState(self.state)
            self.onChange?()
        }
        if Thread.isMainThread { commit() } else { DispatchQueue.main.sync(execute: commit) }
        return results
    }

    func preview() -> [SortResult] {
        previewSorter.run(rules, apply: false, trigger: "preview")
    }

    /// Scheduled runs check auto-sort at run time, so a hand edit that turns it off is respected.
    func runInBackground(trigger: String, onlyIfAutoSort: Bool = false) {
        queue.async {
            if onlyIfAutoSort && !self.rules.autoSort { return }
            self.sortNow(trigger: trigger)
        }
    }

    func saveRules(_ set: RuleSet) throws -> RuleSet {
        let saved = try store.saveRules(set)
        rulesLock.lock()
        lastGood = saved
        warning = nil
        rulesLock.unlock()
        syncLoginItem(saved.autoSort)
        applySchedule()
        onChange?()
        return saved
    }

    func importRules(from url: URL) throws -> RuleSet {
        let set = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
        return try saveRules(set)
    }

    func setAutoSort(_ on: Bool) throws {
        var set = rules
        set.autoSort = on
        _ = try saveRules(set)
        if on { runInBackground(trigger: "auto") }
    }

    /// Keeps "start at login" in step with auto-sort.
    private func syncLoginItem(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on && service.status != .enabled && service.status != .requiresApproval { try service.register() }
            if !on && service.status != .notRegistered { try service.unregister() }
        } catch {
            logger.write("[app] login item \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    /// "enabled", "requiresApproval", "notRegistered" or "notFound" (e.g. not in Applications).
    var loginItemStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notRegistered: return "notRegistered"
        default: return "notFound"
        }
    }

    func updateState(_ change: (inout AppState) -> Void) {
        change(&state)
        store.saveState(state)
        onChange?()
    }

    /// Hourly timer, active only while auto-sort is on.
    func applySchedule() {
        timer?.invalidate()
        timer = nil
        guard rules.autoSort else { return }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            self?.runInBackground(trigger: "auto", onlyIfAutoSort: true)
        }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            self?.runInBackground(trigger: "auto (wake)", onlyIfAutoSort: true)
        }
        applySchedule()
        runInBackground(trigger: "auto (launch)", onlyIfAutoSort: true)
    }
}
