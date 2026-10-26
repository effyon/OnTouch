import AppKit
import CoreGraphics

struct ActionTarget: Equatable {
    let pid: pid_t
    let bundleID: String
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
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else { return nil }
        let point = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for window in windows {
            guard let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  bounds.contains(point) else { continue }
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            else { return nil }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            Diagnostic.log("OnTouch: pointer owner=\(bundleID), layer=\(layer), alpha=\(alpha)")
            return ActionTarget(pid: pid, bundleID: bundleID)
        }
        return nil
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
