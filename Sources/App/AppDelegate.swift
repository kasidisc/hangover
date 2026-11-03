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
        installEditMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.onChange = { [weak self] in self?.refresh() }
        controller.start()
        refresh()
        if !controller.state.firstRunDone { openPanel() }
    }

    /// Menu-bar apps have no visible menu, but copy/paste/select-all in the panel's text boxes
    /// only work if these key equivalents exist in the main menu.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Hangover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(windowItem)
        NSApp.mainMenu = main
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
