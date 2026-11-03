import Foundation

let defaultNeverMove = NeverMove(
    secretExtensions: ["pem", "key", "p12", "pfx", "ppk", "env", "kdbx", "ovpn", "keychain", "cer", "crt"],
    secretNameContains: ["accesskey", "access_key", "password", "passwd", "secret", "credential", "token",
                         "id_rsa", "id_ed25519", "ssh key", "recovery-code", "recovery_code", "private key"],
    skipExtensions: ["download", "crdownload", "part", "partial", "opdownload", "ini", "db", "torrent"],
    skipNamePrefixes: ["~$", "."]
)

let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg", "psd",
                       "dng", "cr2", "nef", "arw", "raw"]

/// Generic, Hazel-like rules for a new user. Auto-sort starts off until the user turns it on.
func starterRules(screenshotPrefix: String?) -> RuleSet {
    var shotNames = ["Screenshot", "Screen Shot"]
    if let p = screenshotPrefix, !p.isEmpty, !shotNames.contains(p) { shotNames.append(p) }
    let desktop = WatchedFolder(name: "Desktop", path: "~/Desktop", ageField: .created, rules: [
        Rule(name: "Screen Recordings", extensions: ["mov", "mp4"], nameContains: ["Screen Recording"],
             to: "~/Movies/Screen Recordings"),
        Rule(name: "Shottr", extensions: ["png", "jpg", "jpeg", "heic", "gif", "webp"], nameStartsWith: ["SCR-"],
             to: "~/Pictures/Screenshots"),
        Rule(name: "Screenshots", extensions: ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"],
             nameContains: shotNames, to: "~/Pictures/Screenshots"),
    ])
    let downloads = WatchedFolder(name: "Downloads", path: "~/Downloads", ageField: .added, rules: [
        Rule(name: "Installers", extensions: ["dmg", "pkg", "app"], allowBundles: true, to: "~/Downloads/Installers"),
        Rule(name: "Archives", extensions: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso"],
             to: "~/Downloads/Archives"),
        Rule(name: "Images", extensions: imageExtensions, to: "~/Downloads/Images"),
        Rule(name: "Videos", extensions: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg"],
             to: "~/Downloads/Videos"),
        Rule(name: "Audio", extensions: ["mp3", "m4a", "wav", "aac", "flac", "ogg", "aif", "aiff", "opus"],
             to: "~/Downloads/Audio"),
        Rule(name: "PDFs", extensions: ["pdf"], to: "~/Downloads/PDFs"),
        Rule(name: "Documents", extensions: ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
                                             "odt", "ods", "odp", "rtf", "txt", "md", "csv", "tsv", "epub"],
             to: "~/Downloads/Documents"),
    ])
    return RuleSet(autoSort: false, neverMove: defaultNeverMove, folders: [desktop, downloads])
}
