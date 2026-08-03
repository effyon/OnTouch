import Foundation
import CoreGraphics
import CMultitouch

/// Recognizes anchored gestures from raw multitouch frames and matches them
/// against the configured `mappings`. A gesture = an optional held anchor finger
/// plus one or more "acting" fingers that either tap (quick touch near the
/// anchor) or swipe (travel in a direction).
///
/// All frames arrive on one background thread (the MT callback), so the mutable
/// state needs no locking.
final class GestureEngine {
    static let shared = GestureEngine()

    /// Number of fingers currently on the trackpad.
    static var liveFingerCount = 0

    /// Uptime of the last frame in which a real gesture was in progress (an
    /// eligible anchor plus at least one acting finger). ClickSuppressor uses
    /// this — not the raw finger count — so a thumb resting on the edge plus a
    /// normal click is NOT mistaken for a gesture and clicks pass through.
    static private(set) var lastGestureUptime: Double = -1000

    /// True if a gesture was in progress within the last `window` seconds (the
    /// grace window covers tap-to-click events that arrive just after lift).
    static func isGesturing(window: Double) -> Bool {
        ProcessInfo.processInfo.systemUptime - lastGestureUptime < window
    }

    var enabled = true

    private let cfg = Config.shared
    private let actions = ActionRunner()

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

    func handleFrame(data: UnsafeMutablePointer<Finger>?, count: Int, timestamp now: Double) {
        guard enabled else { tracked.removeAll(); episode = nil; Self.liveFingerCount = 0; return }
        guard let data = data else { return }

        // 1. Ingest current contacts.
        var currentIDs = Set<Int32>()
        for i in 0..<count {
            let f = data[i]
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
        Self.liveFingerCount = currentIDs.count

        // 2. Collect fingers that just lifted.
        var lifted: [Touch] = []
        for id in tracked.keys where !currentIDs.contains(id) {
            if let t = tracked[id] { lifted.append(t) }
            tracked.removeValue(forKey: id)
        }

        // 3. Re-arm as soon as the acting fingers lift (anchor may stay down),
        //    so gestures can be repeated without lifting the anchor.
        if tracked.count <= 1 { armed = true }

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

        // A gesture is "in progress" only when an eligible anchor is planted and
        // another finger is acting — that's what arms click suppression.
        if anchor != nil && !(acting.isEmpty && actingLifted.isEmpty) {
            Self.lastGestureUptime = ProcessInfo.processInfo.systemUptime
        }

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
        NSLog("OnTouch: \(m.fingers)-finger \(m.type) \(m.direction) → \(m.action)")
        actions.perform(action: m.action, apps: m.apps ?? cfg.targetBundleIDs)
        cooldownUntil = now + cfg.cooldown
        armed = false
    }
}
