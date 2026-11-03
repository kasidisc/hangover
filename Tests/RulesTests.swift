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
    test("starterRulesAreValid") {
        let s = starterRules(screenshotPrefix: "Bildschirmfoto")
        _ = try validate(s, home: testHome, fileExists: allExist)
        expect(s.autoSort == false)
        let desktop = s.folders.first { $0.name == "Desktop" }!
        expect(desktop.ageField == .created)
        let shot = desktop.rules.first { $0.name == "Screenshots" }!
        expect(shot.nameContains! == ["Screenshot", "Screen Shot", "Bildschirmfoto"], "\(shot.nameContains!)")
        let shottr = desktop.rules.first { $0.nameStartsWith != nil }!
        expect(shottr.nameStartsWith! == ["SCR-"])
    }
}
