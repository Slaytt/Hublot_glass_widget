import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel()
        panel.orderFrontRegardless()
        setUpStatusItem()
    }

    // The app has no Dock icon, so the menu bar item is the only way to quit it.
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.circle",
            accessibilityDescription: "Hublot"
        )

        let menu = NSMenu()
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

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }
}
