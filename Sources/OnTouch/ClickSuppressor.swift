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

    guard GestureEngine.shared.enabled else { return Unmanaged.passUnretained(event) }

    let suppressor = ClickSuppressor.shared
    if type == .leftMouseDown, GestureEngine.liveFingerCount >= 2 {
        suppressor?.pendingSuppressUp = true
        return nil                      // drop the click
    }
    if type == .leftMouseUp, GestureEngine.liveFingerCount >= 2 || (suppressor?.pendingSuppressUp ?? false) {
        suppressor?.pendingSuppressUp = false
        return nil                      // drop the matching release
    }
    return Unmanaged.passUnretained(event)
}

final class ClickSuppressor {
    static var shared: ClickSuppressor?
    var tap: CFMachPort?
    var pendingSuppressUp = false

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
