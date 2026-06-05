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
            button.image = Self.brandImage()
            button.imagePosition = .imageOnly
            button.toolTip = "OnTouch"
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

    /// A monochrome "On" wordmark for the menu bar, matching the app icon. As a
    /// template image, macOS tints it correctly for light/dark menu bars.
    private static func brandImage() -> NSImage {
        let text = "On" as NSString
        let font = NSFont.systemFont(ofSize: 14, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let size = text.size(withAttributes: attrs)
        let image = NSImage(size: NSSize(width: ceil(size.width) + 2, height: ceil(size.height)))
        image.lockFocus()
        text.draw(at: NSPoint(x: 1, y: 0), withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = true
        return image
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
