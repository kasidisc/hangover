import AppKit
import ServiceManagement

/// Owns the engine, the saved state and the hourly schedule. The menu bar and the panel both talk to this.
final class AppController {
    let store: Store
    let logger: Logger
    private let sorter: Sorter
    private let previewSorter: Sorter
    private let queue = DispatchQueue(label: "hangover.sort")
    private var timer: Timer?
    private(set) var state: AppState
    private(set) var loadWarning: String?
    var onChange: (() -> Void)?

    init(supportDir: URL, logURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        store = Store(dir: supportDir, home: home)
        logger = Logger(url: logURL)
        sorter = Sorter(fs: RealFileSystem(), log: logger, home: home, now: Date.init, calendar: .current)
        previewSorter = Sorter(fs: RealFileSystem(), log: Logger(url: URL(fileURLWithPath: "/dev/null")),
                               home: home, now: Date.init, calendar: .current)
        state = store.loadState()
        loadWarning = store.loadRules().warning
    }

    var rules: RuleSet { store.loadRules().0 }

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

    @discardableResult
    func sortNow(trigger: String = "manual") -> [SortResult] {
        let results = sorter.run(rules, apply: true, trigger: trigger)
        state.lastRun = Date()
        state.lastResults = results
        store.saveState(state)
        DispatchQueue.main.async { self.onChange?() }
        return results
    }

    func preview() -> [SortResult] {
        previewSorter.run(rules, apply: false, trigger: "preview")
    }

    func saveRules(_ set: RuleSet) throws -> RuleSet {
        let saved = try store.saveRules(set)
        loadWarning = nil
        applySchedule()
        onChange?()
        return saved
    }

    func setAutoSort(_ on: Bool) throws {
        var set = rules
        set.autoSort = on
        _ = try saveRules(set)
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            logger.write("[app] login item \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        if on { runInBackground(trigger: "auto") }
    }

    func updateState(_ change: (inout AppState) -> Void) {
        change(&state)
        store.saveState(state)
        onChange?()
    }

    func runInBackground(trigger: String) {
        queue.async { self.sortNow(trigger: trigger) }
    }

    /// Hourly timer and wake hook, active only while auto-sort is on.
    func applySchedule() {
        timer?.invalidate()
        timer = nil
        guard rules.autoSort else { return }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.runInBackground(trigger: "auto") }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            guard let self = self, self.rules.autoSort else { return }
            self.runInBackground(trigger: "auto (wake)")
        }
        applySchedule()
        if rules.autoSort { runInBackground(trigger: "auto (launch)") }
    }
}
