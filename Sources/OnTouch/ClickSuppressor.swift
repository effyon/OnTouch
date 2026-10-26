import CoreGraphics
import Foundation

/// While a gesture is in progress (2+ fingers on the trackpad), a "tap to
/// click" tap would otherwise register as a left click — clicking links under
/// the cursor instead of just switching tabs. This event tap drops those
/// clicks so gestures don't activate whatever is under the pointer.
private func clickTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                             event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // Re-enable the tap if the system disabled it.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = ClickSuppressor.shared?.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    guard let suppressor = ClickSuppressor.shared else { return Unmanaged.passUnretained(event) }
    var eligible = false
    if type == .leftMouseDown, GestureEngine.shared.enabled,
       !TypingMonitor.isTyping(window: Config.shared.typingGuard) {
        eligible = GestureEngine.clickCandidates(window: 0.25).contains { mapping in
            // A recent scroll blocks taps, while deliberate swipe gestures can
            // still act on a scrollable page.
            (mapping.type != "tap" || !ScrollMonitor.isScrolling(window: Config.shared.scrollGuard))
                && suppressor.actions.canPerform(action: mapping.action,
                    apps: mapping.apps ?? Config.shared.targetBundleIDs)
        }
    }
    // Always drain a swallowed down, even after disabling or leaving the app.
    // A down that passed through must retain its up (including during a drag).
    if suppressor.state.shouldSuppress(type, eligible: eligible) { return nil }
    return Unmanaged.passUnretained(event)
}

final class ClickSuppressor {
    static var shared: ClickSuppressor?
    var tap: CFMachPort?
    var state = ClickSuppressionState()
    let actions = ActionRunner()

    func start() {
        ClickSuppressor.shared = self
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: clickTapCallback,
                                          userInfo: nil) else {
            NSLog("OnTouch: could not create click event tap (needs Accessibility)")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("OnTouch: click suppressor active")
    }
}
