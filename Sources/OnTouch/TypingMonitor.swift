import AppKit

/// Marker stamped on the key events OnTouch itself posts, so the typing monitor
/// can ignore them (otherwise firing a gesture would look like "typing" and
/// suppress the next gesture — breaking rapid repeats).
let kOnTouchSyntheticMarker: Int64 = 0x4F_4E_54_43   // "ONTC"

/// Tracks when the user last pressed a physical key, so the gesture engine can
/// pause while they're typing — preventing stray gestures from firing
/// shortcuts into text fields.
final class TypingMonitor {
    static private(set) var lastKeyUptime: Double = -1000

    private var monitor: Any?

    func start() {
        // Global monitor: sees key events delivered to other apps. Requires the
        // Accessibility permission, which OnTouch already needs.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            // Ignore the synthetic keystrokes OnTouch posts for its own actions.
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == kOnTouchSyntheticMarker {
                return
            }
            TypingMonitor.lastKeyUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    /// True if a real key was pressed within the last `window` seconds.
    static func isTyping(window: Double) -> Bool {
        ProcessInfo.processInfo.systemUptime - lastKeyUptime < window
    }
}
