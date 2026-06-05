import AppKit
import CoreGraphics

/// Posts the keystroke for an action, but only when one of the allowed apps is
/// frontmost — so gestures never hijack input from unrelated windows.
final class ActionRunner {
    func perform(action: String, apps: [String]) {
        // "*" (or an empty list) means "every app". Otherwise the frontmost app
        // must be in the list.
        let anyApp = apps.isEmpty || apps.contains("*")
        if !anyApp {
            guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  apps.contains(front) else { return }
        }
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
        // Mark these as OnTouch's own so the typing monitor ignores them.
        down.setIntegerValueField(.eventSourceUserData, value: kOnTouchSyntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: kOnTouchSyntheticMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
