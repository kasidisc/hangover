import Foundation

private let cal = Calendar.current
private let fixedNow = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
private let yesterday = cal.date(byAdding: .day, value: -1, to: fixedNow)!

/// Creates a file (or directory) with a given creation date.
@discardableResult
private func make(_ dir: URL, _ name: String, created: Date = yesterday, modified: Date? = nil, dir isDir: Bool = false,
                  contents: String = "x") -> URL {
    let url = dir.appendingPathComponent(name)
    if isDir {
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } else {
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
    }
    try! FileManager.default.setAttributes([.creationDate: created, .modificationDate: modified ?? created],
                                           ofItemAtPath: url.path)
    return url
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

/// Real file system, but "date added" comes from a table (macOS doesn't let tests set it).
private struct AddedOverride: FileSystem {
    let real = RealFileSystem()
    let added: [String: Date]
    func contents(of url: URL) throws -> [URL] { try real.contents(of: url) }
    func isDirectory(_ url: URL) -> Bool? { real.isDirectory(url) }
    func isAppBundle(_ url: URL) -> Bool { real.isAppBundle(url) }
    func isSymlink(_ url: URL) -> Bool { real.isSymlink(url) }
    func facts(_ url: URL) throws -> FileFacts {
        var f = try real.facts(url)
        f.dayAdded = added[url.lastPathComponent]
        return f
    }
    func exists(_ url: URL) -> Bool { real.exists(url) }
    func createDirectory(_ url: URL) throws { try real.createDirectory(url) }
    func move(_ url: URL, to: URL) throws { try real.move(url, to: to) }
}

private func setup(_ rules: [Rule], age: AgeField = .created, fs: FileSystem = RealFileSystem())
    -> (root: URL, src: URL, set: RuleSet, sorter: Sorter, log: URL) {
    let root = tempDir()
    let src = root.appendingPathComponent("In")
    try! FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    var set = starterRules(screenshotPrefix: nil)
    set.folders = [WatchedFolder(name: "In", path: src.path, ageField: age, rules: rules)]
    let log = root.appendingPathComponent("Hangover.log")
    let sorter = Sorter(fs: fs, log: Logger(url: log), home: root, now: { fixedNow }, calendar: cal)
    return (root, src, set, sorter, log)
}

private func archives(_ root: URL) -> Rule {
    Rule(name: "Archives", extensions: ["zip"], to: root.appendingPathComponent("Archives").path)
}

func registerSorterTests() {
    test("dryRunMovesNothing") {
        var t = setup([])
        t.set.folders[0].rules = [archives(t.root)]
        make(t.src, "a.zip")
        let r = t.sorter.run(t.set, apply: false, trigger: "test")
        expect(r.map(\.status) == [.wouldMove], "\(r)")
        expect(exists(t.src.appendingPathComponent("a.zip")))
        expect(!exists(t.root.appendingPathComponent("Archives")), "no destination dir in dry run")
    }
    test("applyMovesYesterdayOnly") {
        var t = setup([])
        t.set.folders[0].rules = [archives(t.root)]
        make(t.src, "a.zip")
        make(t.src, "b.zip", created: fixedNow)
        let r = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(exists(t.root.appendingPathComponent("Archives/a.zip")))
        expect(exists(t.src.appendingPathComponent("b.zip")), "today's file stays")
        expect(r.first { $0.file == "b.zip" }?.status == .waiting)
        let log = (try? String(contentsOf: t.log, encoding: .utf8)) ?? ""
        expect(log.contains("MOVED (Archives) a.zip -> "), log)
    }
    test("usesDateAddedForAddedFolders") {
        let fs = AddedOverride(added: ["old.zip": yesterday, "new.zip": fixedNow])  // "added" differs from "created" only for new.zip
        var t = setup([], age: .added, fs: fs)
        t.set.folders[0].rules = [archives(t.root)]
        make(t.src, "old.zip", created: yesterday)    // added yesterday -> moves
        make(t.src, "new.zip", created: yesterday)    // created yesterday but added today -> waits
        let r = t.sorter.run(t.set, apply: false, trigger: "test")
        expect(r.first { $0.file == "old.zip" }?.status == .wouldMove, "\(r)")
        expect(r.first { $0.file == "new.zip" }?.status == .waiting, "\(r)")
    }
    test("clashesNeverOverwrite") {
        var t = setup([])
        let dest = t.root.appendingPathComponent("Pics")
        t.set.folders[0].rules = [Rule(name: "Pics", extensions: ["png"], to: dest.path)]
        make(dest, "a.png", contents: "old")
        make(t.src, "a.png", contents: "new1")
        make(t.src, "a-2.png", contents: "new2")
        _ = t.sorter.run(t.set, apply: true, trigger: "test")
        let names = try FileManager.default.contentsOfDirectory(atPath: dest.path).filter { !$0.hasPrefix(".") }
        expect(names.count == 3, "\(names)")
        expect((try? String(contentsOf: dest.appendingPathComponent("a.png"), encoding: .utf8)) == "old")
        let all = names.compactMap { try? String(contentsOf: dest.appendingPathComponent($0), encoding: .utf8) }
        expect(Set(all) == ["old", "new1", "new2"], "\(all)")
    }
    test("freeDestinationHandlesAppBundles") {
        let dir = URL(fileURLWithPath: "/x")
        let taken: Set<String> = ["/x/Bar.app", "/x/foo.png"]
        expect(freeDestination(dir: dir, name: "Bar.app", exists: { taken.contains($0.path) }).lastPathComponent == "Bar-2.app")
        expect(freeDestination(dir: dir, name: "foo.png", exists: { taken.contains($0.path) }).lastPathComponent == "foo-2.png")
        expect(freeDestination(dir: dir, name: "new.png", exists: { taken.contains($0.path) }).lastPathComponent == "new.png")
    }
    test("doesNotRecurseIntoDestinations") {
        var t = setup([])
        let inner = t.src.appendingPathComponent("Archives")
        t.set.folders[0].rules = [Rule(name: "Archives", extensions: ["zip"], to: inner.path)]
        make(inner, "already.zip")
        let r = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(r.isEmpty, "\(r)")
        expect(exists(inner.appendingPathComponent("already.zip")))
    }
    test("missingFolderDoesNotStopOthers") {
        var t = setup([])
        t.set.folders[0].rules = [archives(t.root)]
        let ghost = WatchedFolder(name: "Ghost", path: t.root.appendingPathComponent("nope").path, rules: [archives(t.root)])
        t.set.folders.insert(ghost, at: 0)
        make(t.src, "a.zip")
        let r = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(r.contains { $0.folder == "Ghost" && $0.status == .error }, "\(r)")
        expect(exists(t.root.appendingPathComponent("Archives/a.zip")))
    }
    test("foldersNeverMovedExceptAppBundles") {
        var t = setup([])
        let out = t.root.appendingPathComponent("Out")
        t.set.folders[0].rules = [
            Rule(name: "Apps", extensions: ["app"], allowBundles: true, to: out.path),
            Rule(name: "Zips", extensions: ["zip"], allowBundles: true, to: out.path),
            Rule(name: "Apps2", extensions: ["app2"], to: out.path),
        ]
        make(t.src, "Stuff.zip", dir: true)
        make(t.src.appendingPathComponent("Tool.app/Contents"), "Info.plist")
        make(t.src, "Tool.app", dir: true)  // back-date the bundle itself
        make(t.src, "Fake.app", dir: true)
        make(t.src, "Tool2.app2", dir: true)
        _ = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(exists(out.appendingPathComponent("Tool.app")), "app bundle moves")
        expect(exists(t.src.appendingPathComponent("Fake.app")), "plain folder named .app stays")
        expect(exists(t.src.appendingPathComponent("Stuff.zip")), "plain folder stays even with allowBundles")
        expect(exists(t.src.appendingPathComponent("Tool2.app2")), "folder stays without allowBundles")
    }
    test("secretsStayAndAreReported") {
        var t = setup([])
        t.set.folders[0].rules = [Rule(name: "Docs", extensions: ["csv"], to: t.root.appendingPathComponent("Docs").path)]
        make(t.src, "keys.pem")
        make(t.src, "aws_accessKeys.csv")
        let r = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(r.count == 1 && r[0].status == .secret && r[0].file == "aws_accessKeys.csv", "\(r)")
        expect(exists(t.src.appendingPathComponent("aws_accessKeys.csv")))
        expect(exists(t.src.appendingPathComponent("keys.pem")))
    }
    test("modifiedTodayWaits") {
        var t = setup([])
        t.set.folders[0].rules = [archives(t.root)]
        make(t.src, "late.zip", created: yesterday, modified: fixedNow)  // download finished after midnight
        let r = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(r.first?.status == .waiting, "\(r)")
        expect(exists(t.src.appendingPathComponent("late.zip")))
    }
    test("firefoxPlaceholderSkipped") {
        var t = setup([])
        t.set.folders[0].rules = [archives(t.root)]
        make(t.src, "big.zip", contents: "")      // zero-byte placeholder
        make(t.src, "big.zip.part")
        let r = t.sorter.run(t.set, apply: true, trigger: "test")
        expect(r.isEmpty, "\(r)")
        expect(exists(t.src.appendingPathComponent("big.zip")))
    }
    test("logRotates") {
        let dir = tempDir()
        let url = dir.appendingPathComponent("Hangover.log")
        let log = Logger(url: url, maxBytes: 200)
        for i in 0..<20 { log.write("line number \(i) with some padding text") }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        expect(size < 400, "size \(size)")
        expect(exists(dir.appendingPathComponent("Hangover.log.1")))
    }
}
