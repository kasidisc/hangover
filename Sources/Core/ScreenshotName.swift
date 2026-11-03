import Foundation

/// The name macOS gives new screenshots when it isn't the English "Screenshot",
/// e.g. a custom name set with `defaults write com.apple.screencapture name`, or the
/// localized word on a non-English Mac. Nil when it's plain "Screenshot" or unknown.
func screenshotNamePrefix() -> String? {
    if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name"),
       !custom.isEmpty, custom != "Screenshot" {
        return custom
    }
    for path in ["/System/Library/CoreServices/screencaptureui.app",
                 "/System/Library/CoreServices/SystemUIServer.app"] {
        guard let bundle = Bundle(path: path) else { continue }
        let word = bundle.localizedString(forKey: "Screenshot", value: nil, table: nil)
        if !word.isEmpty && word != "Screenshot" { return word }
    }
    return nil
}
