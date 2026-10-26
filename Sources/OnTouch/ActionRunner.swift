import AppKit
import CoreGraphics

struct ActionTarget: Equatable {
    let pid: pid_t
    let bundleID: String
}

struct PointerWindow {
    let number: Int
    let owner: ActionTarget
    let layer: Int

    init(number: Int, owner: ActionTarget, layer: Int = 0) {
        self.number = number
        self.owner = owner
        self.layer = layer
    }
}

/// Resolve the actual mouse-hit window, never a bounding rectangle above it.
enum PointerTargetPolicy {
    static func resolve(hitWindowNumber: Int, windows: [PointerWindow]) -> ActionTarget? {
        guard hitWindowNumber > 0,
              let window = windows.first(where: { $0.number == hitWindowNumber }),
              window.layer == 0 else { return nil }
        return window.owner
    }
}

/// Keep the pointer guard and the recipient of the shortcut in agreement.
enum TargetPolicy {
    static func resolve(apps: [String], frontmost: ActionTarget?,
                        underPointer: ActionTarget?) -> ActionTarget? {
        guard let frontmost = frontmost else { return nil }
        if apps.isEmpty || apps.contains("*") { return frontmost }
        guard apps.contains(frontmost.bundleID), underPointer == frontmost else { return nil }
        return frontmost
    }
}

/// Shortcuts act only in the active app. For scoped bindings, that app must
/// also own the window under the pointer. Background windows never steal focus.
final class ActionRunner {
    private let targetProvider: ([String]) -> ActionTarget?
    private let eventPoster: (Keystroke, pid_t) -> Void

    init(targetProvider: @escaping ([String]) -> ActionTarget? = ActionRunner.systemTarget,
         eventPoster: @escaping (Keystroke, pid_t) -> Void = ActionRunner.post) {
        self.targetProvider = targetProvider
        self.eventPoster = eventPoster
    }

    func perform(action: String, apps: [String]) {
        // MT callbacks arrive off the main thread. AppKit target lookup belongs
        // on the main thread, alongside menu state and event monitors.
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.perform(action: action, apps: apps) }
            return
        }
        guard let target = targetProvider(apps) else { return }
        guard let ks = Keys.parse(action, targetBundleID: target.bundleID) else {
            Diagnostic.log("OnTouch: unsupported action '\(action)' for \(target.bundleID)")
            return
        }
        Diagnostic.log("OnTouch: posting \(action) to \(target.bundleID) pid=\(target.pid)")
        eventPoster(ks, target.pid)
    }

    /// Used by the click guard; this resolves a target without posting input.
    func canPerform(action: String, apps: [String]) -> Bool {
        guard let target = targetProvider(apps) else { return false }
        return Keys.parse(action, targetBundleID: target.bundleID) != nil
    }

    private static func systemTarget(apps: [String]) -> ActionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        let frontmost = ActionTarget(pid: app.processIdentifier, bundleID: bundleID)
        if apps.isEmpty || apps.contains("*") { return frontmost }
        let pointer = appUnderCursor()
        let target = TargetPolicy.resolve(apps: apps, frontmost: frontmost, underPointer: pointer)
        if target == nil {
            Diagnostic.log("OnTouch: target blocked; active=\(frontmost.bundleID), pointer=\(pointer?.bundleID ?? "unknown")")
        }
        return target
    }

    private static func appUnderCursor() -> ActionTarget? {
        // AppKit follows mouse-down hit testing across apps and excludes
        // transparent regions/windows that ignore mouse events. A rectangle
        // from CGWindowList can cover Finder while belonging to an overlay.
        // This API takes Cocoa screen points, with no manual Y-axis flip.
        let hitNumber = NSWindow.windowNumber(at: NSEvent.mouseLocation,
                                              belowWindowWithWindowNumber: 0)
        guard hitNumber > 0 else {
            Diagnostic.log("OnTouch: no mouse-hit window")
            return nil
        }
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let hits: [PointerWindow] = windows.compactMap { window in
            guard let number = window[kCGWindowNumber as String] as? Int,
                  number == hitNumber,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            else { return nil }
            Diagnostic.log("OnTouch: mouse-hit window=\(number), owner=\(bundleID), layer=\(layer)")
            return PointerWindow(number: number,
                                 owner: ActionTarget(pid: pid, bundleID: bundleID), layer: layer)
        }
        // Menus/panels, the desktop, missing IDs, and vanished windows fail
        // closed. A real interactive overlay is never bypassed for Finder.
        return PointerTargetPolicy.resolve(hitWindowNumber: hitNumber, windows: hits)
    }

    private static func post(_ ks: Keystroke, to pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: ks.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: ks.keyCode, keyDown: false)
        else { return }
        down.flags = ks.flags
        up.flags = ks.flags
        down.setIntegerValueField(.eventSourceUserData, value: kOnTouchSyntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: kOnTouchSyntheticMarker)
        // Pin both halves to the validated process, even if focus changes now.
        down.postToPid(pid)
        up.postToPid(pid)
    }
}
