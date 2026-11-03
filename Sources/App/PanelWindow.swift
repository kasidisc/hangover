import AppKit
import WebKit

/// The main window: the bundled ui.html in a web view, wired to Swift through Bridge.
final class PanelWindow: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private let window: NSWindow
    private let web: WKWebView
    private let bridge: Bridge
    private let pageURL: URL?

    init(controller: AppController) {
        let config = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1120, height: 800), configuration: config)
        pageURL = Bundle.main.url(forResource: "ui", withExtension: "html")
        bridge = Bridge(controller: controller, web: web, pageURL: pageURL)
        config.userContentController.add(bridge, name: "hangover")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Hangover"
        window.minSize = NSSize(width: 640, height: 480)
        window.contentView = web
        web.navigationDelegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("HangoverPanel")
        if !window.setFrameUsingName("HangoverPanel") { window.center() }
        if let ui = pageURL {
            web.loadFileURL(ui, allowingReadAccessTo: ui.deletingLastPathComponent())
        } else {
            web.loadHTMLString("<p style='font:14px -apple-system;padding:20px'>ui.html is missing from the app bundle.</p>",
                               baseURL: nil)
        }
    }

    /// The panel only ever shows its own page; dropped files and links don't navigate it.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let target = action.request.url?.standardizedFileURL.path
        decisionHandler(target != nil && target == pageURL?.standardizedFileURL.path ? .allow : .cancel)
    }

    /// Dev/test hook (env only, never set for users): HANGOVER_TEST_JS runs a script in the page after it
    /// loads, then HANGOVER_SNAPSHOT saves a PNG of the panel 3 s later.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let env = ProcessInfo.processInfo.environment
        if let js = env["HANGOVER_TEST_JS"], let code = try? String(contentsOfFile: js, encoding: .utf8) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { webView.evaluateJavaScript(code, completionHandler: nil) }
        }
        if let out = env["HANGOVER_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                webView.takeSnapshot(with: nil) { image, _ in
                    guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    try? png.write(to: URL(fileURLWithPath: out))
                }
            }
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func pushState() { bridge.push("state", bridge.stateJSON()) }

    func runPreview() { bridge.push("runPreview", [:]) }
}
