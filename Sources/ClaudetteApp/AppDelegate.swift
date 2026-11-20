import AppKit
import ClaudetteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "C"
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Quit Claudette", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
