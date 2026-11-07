import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!

    // Files opened from the Finder arrive before applicationDidFinishLaunching.
    func applicationWillFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.orderFrontRegardless()
        setUpStatusItem()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let file = urls.first(where: SupportedFile.isSupported) else { return }
        panel.reader.open(file)
        panel.orderFrontRegardless()
    }

    // The app has no Dock icon, so the menu bar item is the only way to quit it.
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.circle",
            accessibilityDescription: "Hublot"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Open File…", action: #selector(openFile), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Obsidian Notes", action: #selector(showNotes), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show / Hide", action: #selector(togglePanel), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Hublot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        statusItem.menu = menu
    }

    @objc private func openFile() {
        panel.orderFrontRegardless()
        panel.reader.chooseFile()
    }

    @objc private func showNotes() {
        panel.orderFrontRegardless()
        panel.reader.showNotes()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }
}
