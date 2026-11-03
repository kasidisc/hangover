import Foundation

/// Lowercased last extension: "foo.tar.gz" -> "gz", "Makefile" -> "".
func fileExtension(_ name: String) -> String {
    (name as NSString).pathExtension.lowercased()
}

/// Hidden files, Office lock files and partial downloads are never touched.
func isSkipped(_ name: String, _ never: NeverMove) -> Bool {
    if never.skipNamePrefixes.contains(where: { name.hasPrefix($0) }) { return true }
    return never.skipExtensions.contains(fileExtension(name))
}

func isSecret(_ name: String, _ never: NeverMove) -> Bool {
    if never.secretExtensions.contains(fileExtension(name)) { return true }
    let low = name.lowercased()
    return never.secretNameContains.contains { low.contains($0) }
}

private func matches(_ rule: Rule, _ name: String) -> Bool {
    guard rule.enabled else { return false }
    if let exts = rule.extensions, !exts.map({ $0.lowercased() }).contains(fileExtension(name)) { return false }
    if let pre = rule.nameStartsWith, !pre.contains(where: { name.hasPrefix($0) }) { return false }
    if let sub = rule.nameContains, !sub.contains(where: { name.contains($0) }) { return false }
    return true
}

/// First enabled rule (top to bottom) whose filled-in filters all match.
func firstMatchingRule(_ name: String, in folder: WatchedFolder) -> Rule? {
    folder.rules.first { matches($0, name) }
}
