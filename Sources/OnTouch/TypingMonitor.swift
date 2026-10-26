import AppKit

/// Marker stamped on the key events OnTouch itself posts, so the typing monitor
/// can ignore them (otherwise firing a gesture would look like "typing" and
/// suppress the next gesture — breaking rapid repeats).
let kOnTouchSyntheticMarker: Int64 = 0x4F_4E_54_43   // "ONTC"

/// Tracks when the user last pressed a physical key, so the gesture engine can
/// pause while they're typing — preventing stray gestures from firing
/// shortcuts into text fields.
final class TypingMonitor {
    private static let timestampLock = NSLock()
    private static var keyUptime: Double = -1000
    static private(set) var lastKeyUptime: Double {
        get {
            timestampLock.lock()
            defer { timestampLock.unlock() }
            return keyUptime
        }
        set {
            timestampLock.lock()
            keyUptime = newValue
            timestampLock.unlock()
        }
    }

    private var monitor: Any?

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        // Global monitor: sees key events delivered to other apps. Requires the
        // Accessibility permission, which OnTouch already needs.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            // Ignore the synthetic keystrokes OnTouch posts for its own actions.
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == kOnTouchSyntheticMarker {
                return
            }
            TypingMonitor.lastKeyUptime = ProcessInfo.processInfo.systemUptime
        }
        Diagnostic.log("OnTouch: typing monitor active=\(monitor != nil)")
    }

    func stop() {
        guard let monitor = monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        Diagnostic.log("OnTouch: typing monitor stopped")
    }

    /// True if a real key was pressed within the last `window` seconds.
    static func isTyping(window: Double) -> Bool {
        ProcessInfo.processInfo.systemUptime - lastKeyUptime < window
    }
}
