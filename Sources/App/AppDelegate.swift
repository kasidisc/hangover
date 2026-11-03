import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller: AppController
    private var statusItem: NSStatusItem!
    private var panel: PanelWindow?

    init(controller: AppController) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.onChange = { [weak self] in self?.refresh() }
        controller.start()
        refresh()
        if !controller.state.firstRunDone { openPanel() }
    }

    private func refresh() {
        let s = controller.status()
        let symbol = s.errorCount > 0 ? "exclamationmark.triangle" : "pills"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hangover")
        panel?.pushState()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = controller.status()
        var line: String
        if let last = s.lastRun {
            let f = DateFormatter()
            f.dateStyle = Calendar.current.isDateInToday(last) ? .none : .short
            f.timeStyle = .short
            line = "Last sorted \(f.string(from: last))"
        } else {
            line = "Not run yet"
        }
        line += s.errorCount > 0 ? " · \(s.errorCount) problem\(s.errorCount == 1 ? "" : "s")" : " · all good"
        let header = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Sort Now", #selector(sortNow)))
        menu.addItem(item("Preview…", #selector(preview)))
        menu.addItem(item("Open Hangover…", #selector(openPanel)))
        let auto = item("Auto-sort", #selector(toggleAuto))
        auto.state = s.autoSort ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        menu.addItem(item("Quit Hangover", #selector(NSApplication.terminate(_:)), target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = target ?? self
        return i
    }

    @objc func sortNow() { controller.runInBackground(trigger: "menu") }

    @objc func preview() {
        openPanel()
        panel?.runPreview()
    }

    @objc func toggleAuto() {
        do { try controller.setAutoSort(!controller.rules.autoSort) } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func openPanel() {
        if panel == nil { panel = PanelWindow(controller: controller) }
        panel?.show()
    }
}
