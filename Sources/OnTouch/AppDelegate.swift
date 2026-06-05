import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let reader = MultitouchReader()
    private var enableItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        promptForAccessibility()
        if !reader.start() {
            NSLog("OnTouch: no multitouch device — check Input Monitoring permission")
        }
    }

    // MARK: Menu bar

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Prefer an SF Symbol; fall back to text so the item is always visible.
            if let image = NSImage(systemSymbolName: "hand.point.up.left.fill",
                                   accessibilityDescription: "OnTouch") {
                button.image = image
            }
            // A short title guarantees a visible hit target even if the symbol
            // fails to render (and helps you spot it next to other menu items).
            button.title = "OnTouch"
            button.imagePosition = .imageLeading
        }

        let menu = NSMenu()
        enableItem = NSMenuItem(title: "Gestures Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.state = .on
        enableItem.target = self
        menu.addItem(enableItem)
        menu.addItem(.separator())

        for line in ["Hold a finger, tap left/right = prev/next tab",
                     "…swipe = back/fwd/reload, 2-finger = close/new/reopen",
                     "Customize: ~/.config/trackpad-tabs/config.json"] {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let ax = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        let im = NSMenuItem(title: "Open Input Monitoring Settings…", action: #selector(openInputMonitoring), keyEquivalent: "")
        im.target = self
        menu.addItem(im)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit OnTouch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        GestureEngine.shared.enabled.toggle()
        enableItem.state = GestureEngine.shared.enabled ? .on : .off
    }

    // MARK: Permissions

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("OnTouch: Accessibility permission not yet granted")
        }
    }

    @objc private func openAccessibility() { openPane("Privacy_Accessibility") }
    @objc private func openInputMonitoring() { openPane("Privacy_ListenEvent") }

    private func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
