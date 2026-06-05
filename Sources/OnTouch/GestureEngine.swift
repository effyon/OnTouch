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

    /// Number of fingers currently on the trackpad. Read by ClickSuppressor to
    /// drop the click that a gesture-tap would otherwise generate.
    static var liveFingerCount = 0

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

        // 4. Identify the anchor: a held, near-stationary finger.
        let present = Array(tracked.values)
        let anchor = present
            .filter { $0.maxDisp < cfg.anchorMaxMove && (now - $0.startTime) >= cfg.anchorMinHold }
            .min(by: { $0.maxDisp < $1.maxDisp })

        let acting = present.filter { $0.id != anchor?.id }
        let actingLifted = lifted.filter { $0.id != anchor?.id }
        let frameMaxDisp = (acting.map { $0.maxDisp } + actingLifted.map { $0.maxDisp }).max() ?? 0

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

        // Hold off while the user is actively typing.
        let canFire = now >= cooldownUntil && armed && !TypingMonitor.isTyping(window: cfg.typingGuard)

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
        if canFire, var ep = episode, !ep.fired, !acting.isEmpty,
           let dir = swipeDirection(acting) {
            if let m = match(anchor: anchorPresent, fingers: acting.count, type: "swipe", direction: dir) {
                fire(m, now)
                ep.fired = true
                episode = ep
            }
        }

        // 6b. Tap — fires when the acting fingers have all lifted.
        if acting.isEmpty, let ep = episode {
            if canFire, !ep.fired,
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
        if abs(dx) >= abs(dy) {
            return abs(dx) >= sep ? (dx < 0 ? "left" : "right") : "none"
        }
        return abs(dy) >= sep ? (dy < 0 ? "down" : "up") : "none"
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
