import AppKit
import CoreGraphics

/// Posts the keystroke for an action, but only when one of the allowed apps is
/// frontmost — so gestures never hijack input from unrelated windows.
final class ActionRunner {
    func perform(action: String, apps: [String]) {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              apps.contains(front) else { return }
        guard let ks = Keys.parse(action) else {
            NSLog("OnTouch: unknown action '\(action)'")
            return
        }
        post(ks)
    }

    private func post(_ ks: Keystroke) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: ks.keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: ks.keyCode, keyDown: false)
        else { return }
        down.flags = ks.flags
        up.flags = ks.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
