import Foundation

let testHome = URL(fileURLWithPath: "/Users/tester")
let allExist: (URL) -> Bool = { _ in true }

func loadReference() throws -> RuleSet {
    try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: fixtureURL("reference-rules.json")))
}

func folder(_ name: String, _ path: String, rules: [Rule]) -> WatchedFolder {
    WatchedFolder(name: name, path: path, ageField: .added, enabled: true, rules: rules)
}

func rule(_ name: String, ext: [String]? = ["zip"], to: String) -> Rule {
    Rule(name: name, enabled: true, extensions: ext, nameStartsWith: nil, nameContains: nil, allowBundles: nil, to: to)
}

func setWith(_ folders: [WatchedFolder]) -> RuleSet {
    var s = starterRules(screenshotPrefix: nil)
    s.folders = folders
    return s
}

func registerRulesTests() {
    test("decodesReferenceRulesFile") {
        let s = try loadReference()
        expect(s.folders.count == 2)
        expect(s.folders[0].ageField == .created)
        expect(s.folders[1].rules.count == 13, "got \(s.folders[1].rules.count)")
        expect(s.extra["_comment"] != nil, "extra keys kept")
        let again = try JSONDecoder().decode(RuleSet.self, from: JSONEncoder().encode(s))
        expect(again == s, "round trip")
    }
    test("rejectsTrashDestination") {
        let s = setWith([folder("Downloads", "~/Downloads", rules: [rule("A", to: "~/.Trash")])])
        expectThrows({ _ = try validate(s, home: testHome, fileExists: allExist) }, contains: "moving to the Trash is not allowed")
    }
    test("rejectsFilterlessRule") {
        let s = setWith([folder("Downloads", "~/Downloads", rules: [rule("A", ext: nil, to: "~/X")])])
        expectThrows({ _ = try validate(s, home: testHome, fileExists: allExist) }, contains: "matches everything")
    }
    test("rejectsMissingWatchedFolder") {
        let s = setWith([folder("Nope", "~/does-not-exist", rules: [])])
        expectThrows({ _ = try validate(s, home: testHome, fileExists: { _ in false }) }, contains: "does not exist")
    }
    test("rejectsDestinationEqualToSource") {
        let s = setWith([folder("Downloads", "~/Downloads", rules: [rule("A", to: "~/Downloads")])])
        expectThrows({ _ = try validate(s, home: testHome, fileExists: allExist) }, contains: "destination is the watched folder itself")
    }
    test("rejectsRelativeDestination") {
        let s = setWith([folder("Downloads", "~/Downloads", rules: [rule("A", to: "Downloads/X")])])
        expectThrows({ _ = try validate(s, home: testHome, fileExists: allExist) }, contains: "must start with ~/ or /")
    }
    test("cleansLists") {
        var s = setWith([folder("Downloads", "~/Downloads", rules: [rule("A", ext: [" .PNG ", ""], to: "~/X")])])
        s.neverMove.skipNamePrefixes = ["."]
        let v = try validate(s, home: testHome, fileExists: allExist)
        expect(v.folders[0].rules[0].extensions == ["png"], "\(String(describing: v.folders[0].rules[0].extensions))")
        expect(v.neverMove.skipNamePrefixes.contains("~$"))
    }
    test("emptiedNeverMoveListsRestoreMinimums") {
        var s = starterRules(screenshotPrefix: nil)
        s.neverMove = NeverMove(secretExtensions: [], secretNameContains: [], skipExtensions: [], skipNamePrefixes: [])
        let v = try validate(s, home: testHome, fileExists: allExist)
        for e in ["download", "crdownload", "part", "partial", "opdownload"] { expect(v.neverMove.skipExtensions.contains(e), e) }
        expect(v.neverMove.secretExtensions.contains("pem") && v.neverMove.secretNameContains.contains("password"))
    }
    test("missingNeverMoveListDecodesEmpty") {
        let json = #"{"folders": [], "never_move": {"skip_extensions": ["iso"]}}"#
        let s = try JSONDecoder().decode(RuleSet.self, from: Data(json.utf8))
        expect(s.neverMove.secretExtensions.isEmpty && s.neverMove.skipExtensions == ["iso"])
    }
    test("rejectsDestinationEqualToSourceIgnoringCase") {
        let s = setWith([folder("Downloads", "~/Downloads", rules: [rule("A", to: "~/downloads/")])])
        expectThrows({ _ = try validate(s, home: testHome, fileExists: allExist) }, contains: "destination is the watched folder itself")
    }
    test("friendlyErrorsAreReadable") {
        let bad = Data(#"{"folders": [{"name": 5}]}"#.utf8)
        do { _ = try JSONDecoder().decode(RuleSet.self, from: bad); expect(false) } catch {
            let msg = friendlyError(error)
            expect(!msg.contains("DecodingError") && !msg.contains("codingPath") && msg.contains("rules"), msg)
        }
        expect(friendlyError(RuleError.invalid("rule 'A': nope")) == "rule 'A': nope")
        let ns = NSError(domain: NSCocoaErrorDomain, code: 257, userInfo: [NSLocalizedDescriptionKey: "Permission denied here"])
        expect(friendlyError(ns) == "Permission denied here")
    }
    test("starterRulesAreValid") {
        let s = starterRules(screenshotPrefix: "Bildschirmfoto")
        _ = try validate(s, home: testHome, fileExists: allExist)
        expect(s.autoSort == false)
        let desktop = s.folders.first { $0.name == "Desktop" }!
        expect(desktop.ageField == .created)
        let shot = desktop.rules.first { $0.name == "Screenshots" }!
        expect(shot.nameContains! == ["Screenshot", "Screen Shot", "Bildschirmfoto"], "\(shot.nameContains!)")
        let scr = desktop.rules.first { $0.nameStartsWith != nil }!
        expect(scr.nameStartsWith! == ["SCR-"])
    }
}
