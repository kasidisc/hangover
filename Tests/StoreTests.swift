import Foundation

/// Temp "home" with Desktop and Downloads, plus a Store in its Application Support.
private func makeStore() -> (store: Store, home: URL, dir: URL) {
    let home = tempDir()
    for d in ["Desktop", "Downloads"] {
        try! FileManager.default.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
    }
    let dir = home.appendingPathComponent("Support")
    return (Store(dir: dir, home: home), home, dir)
}

private func names(_ dir: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
}

func registerStoreTests() {
    test("firstLoadWritesStarterRules") {
        let t = makeStore()
        let (set, warning) = t.store.loadRules()
        expect(warning == nil)
        expect(set.folders.map(\.name) == ["Desktop", "Downloads"])
        expect(FileManager.default.fileExists(atPath: t.dir.appendingPathComponent("rules.json").path))
    }
    test("saveKeepsBackupAndExtraKeys") {
        let t = makeStore()
        var (set, _) = t.store.loadRules()
        set.extra["_comment"] = .string("my notes")
        let first = try t.store.saveRules(set)
        set.autoSort = true
        _ = try t.store.saveRules(set)
        let bak = try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: t.dir.appendingPathComponent("rules.json.bak")))
        expect(bak == first, "backup holds the previous save")
        let (now, _) = t.store.loadRules()
        expect(now.autoSort && now.extra["_comment"] == .string("my notes"))
    }
    test("corruptRulesFileFallsBack") {
        let t = makeStore()
        var (set, _) = t.store.loadRules()
        set.autoSort = true
        _ = try t.store.saveRules(set)          // rules.json = autoSort on
        set.autoSort = false
        _ = try t.store.saveRules(set)          // .bak = autoSort on, rules.json = off
        try "{not json".write(to: t.dir.appendingPathComponent("rules.json"), atomically: true, encoding: .utf8)
        let (loaded, warning) = t.store.loadRules()
        expect(warning != nil, "user is told")
        expect(loaded.autoSort == true, "fell back to the backup")
        expect(names(t.dir).contains { $0.hasPrefix("rules.json.corrupt-") }, "\(names(t.dir))")
    }
    test("corruptWithoutBackupUsesLastGoodInMemory") {
        let t = makeStore()
        var (set, _) = t.store.loadRules()
        set.autoSort = true
        try JSONEncoder().encode(set).write(to: t.dir.appendingPathComponent("rules.json"))  // hand-written, no .bak
        try "{oops".write(to: t.dir.appendingPathComponent("rules.json"), atomically: true, encoding: .utf8)
        let (loaded, warning) = t.store.loadRules(lastGood: set)
        expect(warning != nil && loaded.autoSort == true, "kept the rules the app was running with")
    }
    test("importInvalidLeavesRulesUntouched") {
        let t = makeStore()
        let (before, _) = t.store.loadRules()
        let bad = t.home.appendingPathComponent("bad.json")
        try "{\"folders\": [{\"name\": \"X\", \"path\": \"~/Downloads\", \"rules\": [{\"name\": \"A\", \"to\": \"~/.Trash\", \"extensions\": [\"zip\"]}]}]}"
            .write(to: bad, atomically: true, encoding: .utf8)
        expectThrows({ _ = try t.store.importRules(from: bad) }, contains: "Trash")
        expect(t.store.loadRules().0 == before)
    }
    test("importsReferenceRules") {
        let t = makeStore()
        let set = try t.store.importRules(from: fixtureURL("reference-rules.json"))
        expect(set.folders[1].rules.count == 13)
        expect(t.store.loadRules().0 == set)
    }
    test("exportWritesLoadableFile") {
        let t = makeStore()
        let (set, _) = t.store.loadRules()
        let out = t.home.appendingPathComponent("export.json")
        try t.store.exportRules(to: out)
        expect(try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: out)) == set)
    }
    test("stateRoundTrips") {
        let t = makeStore()
        expect(t.store.loadState().firstRunDone == false)
        var s = t.store.loadState()
        s.firstRunDone = true
        s.ignoredSecrets = ["/a/b"]
        t.store.saveState(s)
        expect(t.store.loadState().firstRunDone && t.store.loadState().ignoredSecrets == ["/a/b"])
    }
    test("missingWatchedFolderDoesNotResetRules") {
        let t = makeStore()
        var (set, _) = t.store.loadRules()
        let drive = t.home.appendingPathComponent("ExternalDrive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        set.folders.append(WatchedFolder(name: "Drive", path: drive.path,
                                         rules: [Rule(name: "Zips", extensions: ["zip"], to: "~/Zips")]))
        _ = try t.store.saveRules(set)
        try FileManager.default.removeItem(at: drive)  // drive unplugged
        let (loaded, warning) = t.store.loadRules()
        expect(warning == nil, "\(warning ?? "")")
        expect(loaded.folders.count == 3, "rules kept")
    }
    test("ignoredSecretsAreHidden") {
        let results = [
            SortResult(folder: "Downloads", status: .secret, file: "a.pem", rule: "X"),
            SortResult(folder: "Downloads", status: .secret, file: "b.env", rule: "X"),
            SortResult(folder: "Downloads", status: .error, file: "c.zip", rule: "X", detail: "boom"),
            SortResult(folder: "Downloads", status: .moved, file: "d.zip", rule: "X"),
        ]
        let p = problems(from: results, ignoring: ["/h/Downloads/a.pem"],
                         folderPaths: ["Downloads": URL(fileURLWithPath: "/h/Downloads")])
        expect(p.errors.map(\.file) == ["c.zip"])
        expect(p.secrets.map(\.file) == ["b.env"])
    }
}
