import AppKit

/// Tracks when the user last scrolled, so the gesture engine can pause during
/// (and just after) scrolling — preventing the brief touches between scroll
/// strokes from being mistaken for tab-switch taps.
final class ScrollMonitor {
    private static let timestampLock = NSLock()
    private static var scrollUptime: Double = -1000
    static private(set) var lastScrollUptime: Double {
        get {
            timestampLock.lock()
            defer { timestampLock.unlock() }
            return scrollUptime
        }
        set {
            timestampLock.lock()
            scrollUptime = newValue
            timestampLock.unlock()
        }
    }

    private var monitor: Any?

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { event in
            // Count only real user-driven scroll *movement*. Ignore inertial
            // momentum (fingers are off the pad), and — crucially — ignore the
            // zero-delta "scroll began/ended" phase events that fire just from
            // placing fingers down (those were suppressing the gestures
            // themselves).
            guard event.momentumPhase == [],
                  event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }
            ScrollMonitor.lastScrollUptime = ProcessInfo.processInfo.systemUptime
        }
        Diagnostic.log("OnTouch: scroll monitor active=\(monitor != nil)")
    }

    func stop() {
        guard let monitor = monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        Diagnostic.log("OnTouch: scroll monitor stopped")
    }

    /// True if the user scrolled within the last `window` seconds.
    static func isScrolling(window: Double) -> Bool {
        ProcessInfo.processInfo.systemUptime - lastScrollUptime < window
    }
}
