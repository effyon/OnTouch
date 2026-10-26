import AppKit
import ApplicationServices
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let reader = MultitouchReader()
    private let typingMonitor = TypingMonitor()
    private let scrollMonitor = ScrollMonitor()
    private let clickSuppressor = ClickSuppressor()
    private var enableItem: NSMenuItem!
    private var accessibilityStatusItem: NSMenuItem!
    private var inputMonitoringStatusItem: NSMenuItem!
    private var permissionTimer: Timer?
    private var accessibilityGranted: Bool?
    private var inputMonitoringGranted: Bool?
    private var lastAccessibilityStartUptime: Double = -1000
    private var lastReaderStartUptime: Double = -1000

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch Services can run copies from different folders at once. Each
        // copy would otherwise recognize and post the same gesture twice.
        let current = NSRunningApplication.current
        if let bundleID = current.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier < current.processIdentifier }) {
            Diagnostic.log("OnTouch: another instance is already running; quitting duplicate")
            NSApp.terminate(nil)
            return
        }
        setupMenu()
        promptForAccessibility()
        let inputGranted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        Diagnostic.log("OnTouch: Input Monitoring request granted=\(inputGranted)")
        // Preserve the original private-MT startup attempt. ListenEvent status
        // is diagnostic; its requirement for this private API is unverified.
        Diagnostic.log("OnTouch: attempting raw multitouch startup regardless of ListenEvent grant")
        startReader()
        refreshPermissions()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        reader.stop()
        typingMonitor.stop()
        scrollMonitor.stop()
        clickSuppressor.stop()
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let about = NSMenuItem(title: "OnTouch \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        enableItem = NSMenuItem(title: "Gestures Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.state = .on
        enableItem.target = self
        menu.addItem(enableItem)
        accessibilityStatusItem = NSMenuItem(title: "Accessibility: Checking…", action: nil, keyEquivalent: "")
        accessibilityStatusItem.isEnabled = false
        menu.addItem(accessibilityStatusItem)
        inputMonitoringStatusItem = NSMenuItem(title: "Input Monitoring: Checking…", action: nil, keyEquivalent: "")
        inputMonitoringStatusItem.isEnabled = false
        menu.addItem(inputMonitoringStatusItem)
        menu.addItem(.separator())

        for line in ["Hold a finger, tap left/right = prev/next tab",
                     "Hold a finger, 2-finger swipe down = close tab",
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

    private func refreshPermissions() {
        let now = ProcessInfo.processInfo.systemUptime
        let axGranted = AXIsProcessTrusted()
        let inputGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

        if accessibilityGranted != axGranted {
            accessibilityGranted = axGranted
            Diagnostic.log("OnTouch: Accessibility granted=\(axGranted)")
            if axGranted {
                lastAccessibilityStartUptime = now
                typingMonitor.start()
                scrollMonitor.start()
                clickSuppressor.start()
            } else {
                typingMonitor.stop()
                scrollMonitor.stop()
                clickSuppressor.stop()
            }
        }

        if inputMonitoringGranted != inputGranted {
            let previousGrant = inputMonitoringGranted
            inputMonitoringGranted = inputGranted
            Diagnostic.log("OnTouch: Input Monitoring granted=\(inputGranted)")
            if previousGrant != nil, inputGranted {
                reader.stop()
                startReader()
            } else if previousGrant == true, !inputGranted {
                reader.stop()
            }
        }

        // Retry failed starts at a bounded interval, without repeating prompts.
        if axGranted, now - lastAccessibilityStartUptime >= 5,
           !typingMonitor.isRunning || !scrollMonitor.isRunning || !clickSuppressor.isRunning {
            lastAccessibilityStartUptime = now
            typingMonitor.start()
            scrollMonitor.start()
            clickSuppressor.start()
        }
        if inputGranted, now - lastReaderStartUptime >= 5, !reader.isRunning {
            startReader()
        }

        accessibilityStatusItem.title = "Accessibility: \(axGranted ? "Allowed" : "Permission needed")"
        inputMonitoringStatusItem.title = "Input Monitoring: \(inputGranted ? "Allowed" : "Not granted")"
    }

    private func startReader() {
        lastReaderStartUptime = ProcessInfo.processInfo.systemUptime
        if !reader.start() {
            Diagnostic.log("OnTouch: no multitouch device running immediately after startup attempt")
        }
    }

    private func promptForAccessibility() {
        Diagnostic.log("OnTouch: initial Accessibility trusted=\(AXIsProcessTrusted())")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            Diagnostic.log("OnTouch: Accessibility permission not yet granted")
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
