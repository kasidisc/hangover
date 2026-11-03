import AppKit

// HANGOVER_SUPPORT_DIR (tests/dev) keeps rules, state and the log out of the real locations.
let env = ProcessInfo.processInfo.environment
let supportDir: URL
let logURL: URL
if let override = env["HANGOVER_SUPPORT_DIR"], !override.isEmpty {
    supportDir = URL(fileURLWithPath: override)
    logURL = supportDir.appendingPathComponent("Hangover.log")
} else {
    let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    supportDir = lib.appendingPathComponent("Application Support/Hangover")
    logURL = lib.appendingPathComponent("Logs/Hangover.log")
}
let controller = AppController(supportDir: supportDir, logURL: logURL)

if CommandLine.arguments.contains("--sort-once") {
    // One apply pass with the current rules, results as JSON, no UI.
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try enc.encode(controller.sortNow(trigger: "cli")), encoding: .utf8)!)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(controller: controller)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
