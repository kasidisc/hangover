import Foundation

/// Any JSON value; used to round-trip keys Hangover doesn't know (e.g. "_comment").
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

enum AgeField: String, Codable { case added, created }

struct Rule: Codable, Equatable {
    var name: String
    var enabled: Bool
    var extensions: [String]?
    var nameStartsWith: [String]?
    var nameContains: [String]?
    var allowBundles: Bool?
    var to: String

    enum CodingKeys: String, CodingKey {
        case name, enabled, extensions, to
        case nameStartsWith = "name_starts_with", nameContains = "name_contains", allowBundles = "allow_bundles"
    }

    init(name: String, enabled: Bool = true, extensions: [String]? = nil, nameStartsWith: [String]? = nil,
         nameContains: [String]? = nil, allowBundles: Bool? = nil, to: String) {
        self.name = name; self.enabled = enabled; self.extensions = extensions
        self.nameStartsWith = nameStartsWith; self.nameContains = nameContains
        self.allowBundles = allowBundles; self.to = to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        extensions = try c.decodeIfPresent([String].self, forKey: .extensions)
        nameStartsWith = try c.decodeIfPresent([String].self, forKey: .nameStartsWith)
        nameContains = try c.decodeIfPresent([String].self, forKey: .nameContains)
        allowBundles = try c.decodeIfPresent(Bool.self, forKey: .allowBundles)
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
    }
}

struct WatchedFolder: Codable, Equatable {
    var name: String
    var path: String
    var ageField: AgeField
    var enabled: Bool
    var rules: [Rule]

    enum CodingKeys: String, CodingKey { case name, path, enabled, rules, ageField = "age_field" }

    init(name: String, path: String, ageField: AgeField = .added, enabled: Bool = true, rules: [Rule]) {
        self.name = name; self.path = path; self.ageField = ageField; self.enabled = enabled; self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        ageField = try c.decodeIfPresent(AgeField.self, forKey: .ageField) ?? .added
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}

struct NeverMove: Codable, Equatable {
    var secretExtensions: [String]
    var secretNameContains: [String]
    var skipExtensions: [String]
    var skipNamePrefixes: [String]

    enum CodingKeys: String, CodingKey {
        case secretExtensions = "secret_extensions", secretNameContains = "secret_name_contains"
        case skipExtensions = "skip_extensions", skipNamePrefixes = "skip_name_prefixes"
    }
}

struct RuleSet: Codable, Equatable {
    var autoSort: Bool
    var neverMove: NeverMove
    var folders: [WatchedFolder]
    /// Top-level keys Hangover doesn't use, kept so hand-written notes survive a save.
    var extra: [String: JSONValue]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    private static let known: Set<String> = ["auto_sort", "never_move", "folders"]

    init(autoSort: Bool, neverMove: NeverMove, folders: [WatchedFolder], extra: [String: JSONValue] = [:]) {
        self.autoSort = autoSort; self.neverMove = neverMove; self.folders = folders; self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        autoSort = try c.decodeIfPresent(Bool.self, forKey: Key("auto_sort")) ?? false
        neverMove = try c.decodeIfPresent(NeverMove.self, forKey: Key("never_move")) ?? defaultNeverMove
        folders = try c.decode([WatchedFolder].self, forKey: Key("folders"))
        var extra: [String: JSONValue] = [:]
        for k in c.allKeys where !Self.known.contains(k.stringValue) {
            extra[k.stringValue] = try c.decode(JSONValue.self, forKey: k)
        }
        self.extra = extra
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (k, v) in extra { try c.encode(v, forKey: Key(k)) }
        try c.encode(autoSort, forKey: Key("auto_sort"))
        try c.encode(neverMove, forKey: Key("never_move"))
        try c.encode(folders, forKey: Key("folders"))
    }
}

enum RuleError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { if case .invalid(let m) = self { return m }; return "" }
}

func expandTilde(_ path: String, home: URL) -> URL {
    if path == "~" { return home }
    if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
    return URL(fileURLWithPath: path)
}

private func cleanList(_ list: [String]?, lower: Bool = false) -> [String]? {
    guard let list = list else { return nil }
    let out = list.map { s -> String in
        var t = s.trimmingCharacters(in: .whitespaces)
        if lower { while t.hasPrefix(".") { t.removeFirst() }; t = t.lowercased() }
        return t
    }.filter { !$0.isEmpty }
    return out.isEmpty ? nil : out
}

/// Cleans a rule set and refuses unsafe or malformed rules (messages match the reference server.py).
func validate(_ set: RuleSet, home: URL, fileExists: (URL) -> Bool) throws -> RuleSet {
    var s = set
    s.neverMove.secretExtensions = cleanList(s.neverMove.secretExtensions, lower: true) ?? []
    s.neverMove.skipExtensions = cleanList(s.neverMove.skipExtensions, lower: true) ?? []
    s.neverMove.secretNameContains = (cleanList(s.neverMove.secretNameContains) ?? []).map { $0.lowercased() }
    s.neverMove.skipNamePrefixes = cleanList(s.neverMove.skipNamePrefixes) ?? []
    for must in ["~$", "."] where !s.neverMove.skipNamePrefixes.contains(must) {
        s.neverMove.skipNamePrefixes.append(must)  // hidden/lock files are always skipped
    }

    let trash = home.appendingPathComponent(".Trash").standardizedFileURL.path
    for fi in s.folders.indices {
        var f = s.folders[fi]
        f.name = f.name.trimmingCharacters(in: .whitespaces)
        f.path = f.path.trimmingCharacters(in: .whitespaces)
        if f.name.isEmpty || f.path.isEmpty {
            throw RuleError.invalid("every watched folder needs a name and a path")
        }
        let src = expandTilde(f.path, home: home).standardizedFileURL
        if !fileExists(src) {
            throw RuleError.invalid("watched folder '\(f.name)' does not exist: \(f.path)")
        }
        for ri in f.rules.indices {
            var r = f.rules[ri]
            r.name = r.name.trimmingCharacters(in: .whitespaces)
            r.to = r.to.trimmingCharacters(in: .whitespaces)
            if r.name.isEmpty { throw RuleError.invalid("folder '\(f.name)' has a rule with no name") }
            if !(r.to.hasPrefix("~/") || r.to.hasPrefix("/")) {
                throw RuleError.invalid("rule '\(r.name)': destination must start with ~/ or /")
            }
            let dest = expandTilde(r.to, home: home).standardizedFileURL.path
            if dest == trash || dest.hasPrefix(trash + "/") || dest.contains("/.Trash") {
                throw RuleError.invalid("rule '\(r.name)': moving to the Trash is not allowed")
            }
            if dest == src.path {
                throw RuleError.invalid("rule '\(r.name)': destination is the watched folder itself")
            }
            r.extensions = cleanList(r.extensions, lower: true)
            r.nameStartsWith = cleanList(r.nameStartsWith)
            r.nameContains = cleanList(r.nameContains)
            if r.extensions == nil && r.nameStartsWith == nil && r.nameContains == nil {
                throw RuleError.invalid("rule '\(r.name)' matches everything; give it extensions or a name filter")
            }
            f.rules[ri] = r
        }
        s.folders[fi] = f
    }
    return s
}
