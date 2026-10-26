import Foundation
import CoreGraphics
import CMultitouch

/// Recognizes anchored gestures from raw multitouch frames and matches them
/// against the configured `mappings`. A gesture = an optional held anchor finger
/// plus one or more "acting" fingers that either tap (quick touch near the
/// anchor) or swipe (travel in a direction).
///
/// Contact state is updated by the MT callback path. The click-candidate
/// snapshot is synchronized separately with the main event tap.
final class GestureEngine {
    static let shared = GestureEngine()

    /// Number of fingers currently on the trackpad.
    static var liveFingerCount = 0

    /// Uptime of the last frame in which a real gesture was in progress (an
    /// eligible anchor plus at least one acting finger). ClickSuppressor uses
    /// this — not the raw finger count — so a thumb resting on the edge plus a
    /// normal click is NOT mistaken for a gesture and clicks pass through.
    private static var lastGestureUptime: Double = -1000
    private static var recentClickMappings: [Mapping] = []
    private static let clickSnapshotLock = NSLock()

    /// True if a gesture was in progress within the last `window` seconds (the
    /// grace window covers tap-to-click events that arrive just after lift).
    static func isGesturing(window: Double) -> Bool {
        clickSnapshotLock.lock()
        defer { clickSnapshotLock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastGestureUptime < window
    }

    /// Candidate bindings cross from the MT callback to the main event tap.
    static func clickCandidates(window: Double) -> [Mapping] {
        clickSnapshotLock.lock()
        defer { clickSnapshotLock.unlock() }
        guard ProcessInfo.processInfo.systemUptime - lastGestureUptime < window else { return [] }
        return recentClickMappings
    }

    private static func noteClickCandidates(_ mappings: [Mapping]) {
        clickSnapshotLock.lock()
        recentClickMappings = mappings
        lastGestureUptime = mappings.isEmpty ? -1000 : ProcessInfo.processInfo.systemUptime
        clickSnapshotLock.unlock()
    }

    private let stateLock = NSRecursiveLock()
    private var enabledStorage = true

    var enabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return enabledStorage
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            enabledStorage = newValue
            if !newValue { resetState() }
        }
    }

    private let cfg: Config
    private let actionSink: (String, [String]) -> Void

    init(config: Config = .shared,
         actionSink: @escaping (String, [String]) -> Void = {
             ActionRunner().perform(action: $0, apps: $1)
         }) {
        cfg = config
        self.actionSink = actionSink
    }

    private struct Touch {
        let id: Int32
        let startTime: Double
        let startPos: CGPoint
        var curPos: CGPoint
        var maxDisp: CGFloat
        var lastSeen: Double
    }

    /// One run of acting (non-anchor) fingers, from first touch to last lift.
    private struct Episode {
        let start: Double
        var peak: Int            // most acting fingers seen at once
        var maxDisp: CGFloat     // furthest any acting finger has moved
        let centroid: CGPoint    // where the acting fingers first landed
        var fired: Bool          // a swipe already fired this episode
    }

    private var tracked: [Int32: Touch] = [:]
    private var episode: Episode?
    private var cooldownUntil: Double = 0
    private var armed = true     // re-armed once acting fingers clear

    /// Permission/device restarts must not reuse contacts from a prior stream.
    func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }
        resetState()
    }

    private func resetState() {
        tracked.removeAll()
        episode = nil
        cooldownUntil = 0
        armed = true
        Self.liveFingerCount = 0
        Self.noteClickCandidates([])
    }

    func handleFrame(data: UnsafeMutablePointer<Finger>?, count: Int, timestamp now: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard enabledStorage else { resetState(); return }
        // Multitouch callbacks may use a nil pointer for a zero-contact frame.
        // Process it as a lift so the previous contacts and episode can clear.
        guard count >= 0, count == 0 || data != nil else { return }

        // 1. Ingest current contacts.
        var currentIDs = Set<Int32>()
        for f in UnsafeBufferPointer(start: data, count: count) {
            guard Double(f.size) > cfg.minTouchSize else { continue }
            let pos = CGPoint(x: CGFloat(f.normalized.position.x),
                              y: CGFloat(f.normalized.position.y))
            currentIDs.insert(f.identifier)
            if var t = tracked[f.identifier] {
                t.curPos = pos
                t.maxDisp = max(t.maxDisp, hypot(pos.x - t.startPos.x, pos.y - t.startPos.y))
                t.lastSeen = now
                tracked[f.identifier] = t
            } else {
                tracked[f.identifier] = Touch(id: f.identifier, startTime: now,
                                              startPos: pos, curPos: pos, maxDisp: 0, lastSeen: now)
            }
        }
        if Self.liveFingerCount != currentIDs.count {
            Diagnostic.log("OnTouch: qualifying contact count=\(currentIDs.count)")
        }
        Self.liveFingerCount = currentIDs.count

        // 2. Collect fingers that just lifted.
        var lifted: [Touch] = []
        for id in tracked.keys where !currentIDs.contains(id) {
            if let t = tracked[id] { lifted.append(t) }
            tracked.removeValue(forKey: id)
        }

        // Touches that STARTED in any edge strip are "resting" — a parked thumb
        // (measured: left edge at mid-height, or top edge near the keyboard).
        // Resting touches can be neither anchors nor acting fingers; otherwise
        // a thumb + a stationary clicking finger reads as anchor + acting =
        // "gesture", wrongly arming click suppression or switching tabs.
        let isResting: (Touch) -> Bool = {
            $0.startPos.y <= CGFloat(self.cfg.anchorEdgeZone)          // bottom
                || $0.startPos.y >= CGFloat(1 - self.cfg.topEdgeZone)  // top
                || $0.startPos.x <= CGFloat(self.cfg.sideEdgeZone)     // left
                || $0.startPos.x >= CGFloat(1 - self.cfg.sideEdgeZone) // right
        }

        // 4. Identify the anchor: a held, near-stationary, non-resting finger.
        let present = Array(tracked.values)
        let anchor = present
            .filter {
                $0.maxDisp < cfg.anchorMaxMove
                    && (now - $0.startTime) >= cfg.anchorMinHold
                    && !isResting($0)
            }
            .min(by: { $0.maxDisp < $1.maxDisp })

        let acting = present.filter { $0.id != anchor?.id && !isResting($0) }
        let actingLifted = lifted.filter { $0.id != anchor?.id && !isResting($0) }
        let frameMaxDisp = (acting.map { $0.maxDisp } + actingLifted.map { $0.maxDisp }).max() ?? 0

        // Re-arm when acting fingers clear. A resting edge thumb may remain
        // alongside the anchor and must not prevent another gesture.
        if acting.isEmpty { armed = true }

        // 5. Maintain the acting-finger episode.
        if !acting.isEmpty {
            if episode == nil {
                episode = Episode(start: now, peak: acting.count, maxDisp: frameMaxDisp,
                                  centroid: centroid(acting.map { $0.startPos }), fired: false)
            } else {
                episode!.peak = max(episode!.peak, acting.count)
                episode!.maxDisp = max(episode!.maxDisp, frameMaxDisp)
            }
        }

        let baseCanFire = now >= cooldownUntil && armed
            && !TypingMonitor.isTyping(window: cfg.typingGuard)
        // Scrolling only blocks TAP gestures (a quick tap during scroll
        // repositioning gets mistaken for a tab switch). Swipe gestures like
        // close-tab are themselves downward motions and need an anchor, so the
        // scroll guard must NOT block them — otherwise closing tabs fails on
        // long, scrollable pages.
        let canFireSwipe = baseCanFire
        let canFireTap = baseCanFire && !ScrollMonitor.isScrolling(window: cfg.scrollGuard)

        // A swipe is inherently deliberate (the fingers travel), so it only
        // needs a stationary anchor present. A tap additionally requires the
        // anchor to have been held BEFORE the tapping finger began — that's what
        // rejects a two-finger tap / right-click (both fingers land together).
        let anchorPresent = anchor != nil
        let anchorLeads: Bool = {
            guard let a = anchor, let ep = episode else { return false }
            return (ep.start - a.startTime) >= cfg.anchorLead
        }()

        // Suppress clicks only for a binding that could recognize this episode.
        // The event tap also checks the current app and action support. A mere
        // two-finger contact, a typing/scroll guard, or an unmapped pattern must
        // not swallow ordinary clicks in another app.
        if let ep = episode, !ep.fired {
            let tapDir = tapDirection(ep.centroid, anchor: anchorLeads ? anchor : nil)
            var candidates: [Mapping] = []
            if canFireTap, (now - ep.start) <= cfg.tapMaxDuration,
               ep.maxDisp <= cfg.tapMaxMove,
               let mapping = match(anchor: anchorLeads, fingers: ep.peak,
                                   type: "tap", direction: tapDir) {
                candidates.append(mapping)
            }
            if canFireSwipe, !acting.isEmpty {
                let directions = swipeDirection(acting).map { [$0] } ?? ["left", "right", "up", "down"]
                for direction in directions {
                    if let mapping = match(anchor: anchorPresent, fingers: acting.count,
                                           type: "swipe", direction: direction) {
                        candidates.append(mapping)
                    }
                }
            }
            // Empty snapshots clear an invalid ongoing pattern. Completed
            // episodes retain the last valid snapshot for tap-to-click grace.
            Self.noteClickCandidates(candidates)
        }

        // 6a. Swipe — fires mid-gesture, while the acting fingers are still down.
        if canFireSwipe, var ep = episode, !ep.fired, !acting.isEmpty,
           let dir = swipeDirection(acting) {
            if let m = match(anchor: anchorPresent, fingers: acting.count, type: "swipe", direction: dir) {
                fire(m, now)
                ep.fired = true
                episode = ep
            }
        }

        // 6b. Tap — fires when the acting fingers have all lifted.
        if acting.isEmpty, let ep = episode {
            if canFireTap, !ep.fired,
               (now - ep.start) <= cfg.tapMaxDuration, ep.maxDisp <= cfg.tapMaxMove {
                let dir = tapDirection(ep.centroid, anchor: anchorLeads ? anchor : nil)
                if let m = match(anchor: anchorLeads, fingers: ep.peak, type: "tap", direction: dir) {
                    fire(m, now)
                }
            }
            episode = nil
        }
    }

    // MARK: - Geometry helpers

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let n = CGFloat(pts.count)
        return CGPoint(x: pts.map { $0.x }.reduce(0, +) / n,
                       y: pts.map { $0.y }.reduce(0, +) / n)
    }

    /// Direction of a tap relative to the anchor. Returns "none" (which matches
    /// no directional binding) if there's no anchor or the tap is too close to
    /// it to read a clear direction.
    private func tapDirection(_ c: CGPoint, anchor: Touch?) -> String {
        guard let a = anchor else { return "none" }
        let dx = c.x - a.curPos.x, dy = c.y - a.curPos.y
        let sep = CGFloat(cfg.tapMinSep)
        // Prefer horizontal (tab switching). A left/right tap often lands higher
        // than the anchor too, so we must NOT let that vertical offset reclassify
        // it as up/down — as long as there's clear horizontal separation, it's
        // a left/right tap regardless of how high it landed.
        if abs(dx) >= sep { return dx < 0 ? "left" : "right" }
        if abs(dy) >= sep { return dy < 0 ? "down" : "up" }
        return "none"
    }

    /// Direction of a swipe, or nil if the fingers haven't all moved far enough
    /// in a consistent direction yet.
    private func swipeDirection(_ fs: [Touch]) -> String? {
        let deltas = fs.map { CGPoint(x: $0.curPos.x - $0.startPos.x,
                                      y: $0.curPos.y - $0.startPos.y) }
        let avg = centroid(deltas)
        let d = CGFloat(cfg.swipeDist)
        if abs(avg.x) >= abs(avg.y) {
            guard deltas.allSatisfy({ abs($0.x) >= d && ($0.x < 0) == (avg.x < 0) }) else { return nil }
            return avg.x < 0 ? "left" : "right"
        } else {
            guard deltas.allSatisfy({ abs($0.y) >= d && ($0.y < 0) == (avg.y < 0) }) else { return nil }
            return avg.y < 0 ? "down" : "up"
        }
    }

    // MARK: - Matching & firing

    private func match(anchor: Bool, fingers: Int, type: String, direction: String) -> Mapping? {
        cfg.mappings.first {
            $0.anchor == anchor && $0.fingers == fingers && $0.type == type &&
            ($0.direction == direction || $0.direction == "any")
        }
    }

    private func fire(_ m: Mapping, _ now: Double) {
        Diagnostic.log("OnTouch: \(m.fingers)-finger \(m.type) \(m.direction) → \(m.action)")
        actionSink(m.action, m.apps ?? cfg.targetBundleIDs)
        cooldownUntil = now + cfg.cooldown
        armed = false
    }
}
