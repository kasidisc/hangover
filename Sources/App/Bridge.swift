import AppKit
import ServiceManagement
import WebKit

/// Handles messages from ui.html: {id, action, payload} -> window.__hangoverReply(id, {ok, data|error}).
final class Bridge: NSObject, WKScriptMessageHandler {
    private let controller: AppController
    private weak var web: WKWebView?
    private let pageURL: URL?

    init(controller: AppController, web: WKWebView, pageURL: URL?) {
        self.controller = controller
        self.web = web
        self.pageURL = pageURL
    }

    // MARK: JSON helpers

    private func json<T: Encodable>(_ value: T) -> Any {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return NSNull() }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
    }

    private func decode<T: Decodable>(_ type: T.Type, from any: Any?) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: any ?? [:], options: [.fragmentsAllowed])
        return try JSONDecoder().decode(type, from: data)
    }

    private func tilde(_ path: String) -> String {
        let home = controller.store.home.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    func stateJSON() -> [String: Any] {
        let p = controller.problemsNow()
        let s = controller.state
        return [
            "rules": json(controller.rules),
            "lastRun": s.lastRun.map { ISO8601DateFormatter().string(from: $0) } as Any,
            "problems": ["errors": json(p.errors), "secrets": json(p.secrets)],
            "log": controller.logger.tail(150),
            "logPath": tilde(controller.logger.url.path),
            "firstRunDone": s.firstRunDone,
            "warning": controller.loadWarning as Any,
            "loginItem": controller.loginItemStatus,
        ]
    }

    // MARK: Outgoing

    private func send(_ script: String, _ args: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { self.web?.evaluateJavaScript("\(script)(...\(text))", completionHandler: nil) }
    }

    func push(_ event: String, _ data: Any) { send("window.__hangoverPush", [event, data]) }

    private func reply(_ id: Any, ok data: Any = NSNull()) { send("window.__hangoverReply", [id, ["ok": true, "data": data]]) }

    private func reply(_ id: Any, error: Error) {
        send("window.__hangoverReply", [id, ["ok": false, "error": friendlyError(error)]])
    }

    // MARK: Incoming

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only the bundled panel page may drive Hangover (not a file dropped onto the window).
        guard message.frameInfo.isMainFrame, let page = pageURL,
              message.frameInfo.request.url?.standardizedFileURL.path == page.standardizedFileURL.path else { return }
        guard let body = message.body as? [String: Any], let id = body["id"], let action = body["action"] as? String else { return }
        let payload = body["payload"]
        do {
            switch action {
            case "getState":
                reply(id, ok: stateJSON())
            case "saveRules":
                let saved = try controller.saveRules(try decode(RuleSet.self, from: payload))
                reply(id, ok: json(saved))
            case "preview", "sortNow":
                controller.queue.async {
                    let results = action == "preview" ? self.controller.preview() : self.controller.sortNow(trigger: "panel")
                    self.reply(id, ok: self.json(results))
                }
            case "setAutoSort":
                try controller.setAutoSort((payload as? Bool) ?? false)
                reply(id, ok: stateJSON())
            case "pickFolder":
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.prompt = "Choose"
                if panel.runModal() == .OK, let url = panel.url { reply(id, ok: tilde(url.path)) } else { reply(id) }
            case "importRules":
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                panel.prompt = "Import"
                if panel.runModal() == .OK, let url = panel.url {
                    reply(id, ok: json(try controller.importRules(from: url)))
                } else { reply(id) }
            case "exportRules":
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "hangover-rules.json"
                if panel.runModal() == .OK, let url = panel.url {
                    try controller.store.exportRules(to: url)
                    reply(id, ok: tilde(url.path))
                } else { reply(id) }
            case "ignoreSecret":
                let p = payload as? [String: String] ?? [:]
                if let folder = p["folder"], let file = p["file"], let dir = controller.folderPaths()[folder] {
                    let path = dir.appendingPathComponent(file).path
                    controller.updateState { if !$0.ignoredSecrets.contains(path) { $0.ignoredSecrets.append(path) } }
                }
                reply(id, ok: stateJSON())
            case "openLoginItems":
                SMAppService.openSystemSettingsLoginItems()
                reply(id)
            case "openPrivacySettings":
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                reply(id)
            case "completeFirstRun":
                controller.updateState { $0.firstRunDone = true }
                reply(id, ok: stateJSON())
            default:
                reply(id, error: RuleError.invalid("unknown action \(action)"))
            }
        } catch {
            reply(id, error: error)
        }
    }
}
