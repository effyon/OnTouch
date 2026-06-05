import Foundation
import CoreGraphics
import CMultitouch

/// Recognizes "anchored" gestures from raw multitouch frames:
///   • hold one finger + tap to its LEFT  → previous tab
///   • hold one finger + tap to its RIGHT → next tab
///   • hold one finger + swipe DOWN with two others → close tab
///
/// All frames arrive on a single background thread (the MT callback), so the
/// mutable state here needs no locking.
final class GestureEngine {
    static let shared = GestureEngine()

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

    private var tracked: [Int32: Touch] = [:]
    private var cooldownUntil: Double = 0
    private var armed = true   // re-armed once all fingers lift

    func handleFrame(data: UnsafeMutablePointer<Finger>?, count: Int, timestamp now: Double) {
        guard enabled else { tracked.removeAll(); return }
        guard let data = data else { return }

        // 1. Ingest the current contacts.
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
                                              startPos: pos, curPos: pos,
                                              maxDisp: 0, lastSeen: now)
            }
        }

        // 2. Collect fingers that just lifted.
        var lifted: [Touch] = []
        for id in tracked.keys where !currentIDs.contains(id) {
            if let t = tracked[id] { lifted.append(t) }
            tracked.removeValue(forKey: id)
        }

        // 3. Re-arm as soon as the action fingers lift, even while the anchor
        //    stays down — this lets you repeat a gesture (e.g. tap, tap, tap to
        //    page back through tabs) without lifting your anchor each time.
        if tracked.count <= 1 { armed = true }

        guard now >= cooldownUntil, armed else { return }

        // 4. Identify the anchor: a held, near-stationary finger.
        let present = Array(tracked.values)
        guard let anchor = present
            .filter({ $0.maxDisp < cfg.anchorMaxMove && (now - $0.startTime) >= cfg.anchorMinHold })
            .min(by: { $0.maxDisp < $1.maxDisp })
        else { return }

        // 5a. Tap gesture (fires on the second finger lifting).
        for t in lifted where t.id != anchor.id {
            let duration = t.lastSeen - t.startTime
            guard duration <= cfg.tapMaxDuration,
                  t.maxDisp <= cfg.tapMaxMove,
                  anchor.startTime <= t.startTime else { continue }
            if t.startPos.x < anchor.curPos.x {
                fire(.prevTab, now)          // tapped to the left of the anchor
            } else {
                fire(.nextTab, now)          // tapped to the right of the anchor
            }
            return
        }

        // 5b. Two-finger downward swipe with the anchor held.
        let movers = present.filter { $0.id != anchor.id }
        if movers.count == 2 {
            let bothSwipingDown = movers.allSatisfy {
                ($0.curPos.y - $0.startPos.y) < -CGFloat(cfg.swipeDownDist)
            }
            if bothSwipingDown {
                fire(.closeTab, now)
            }
        }
    }

    private func fire(_ action: Action, _ now: Double) {
        NSLog("OnTouch: gesture → \(action)")
        actions.perform(action)
        cooldownUntil = now + cfg.cooldown
        armed = false
    }
}
