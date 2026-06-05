import AppKit
import CoreGraphics

enum Action: CustomStringConvertible {
    case nextTab, prevTab, closeTab, closeAll
    var description: String {
        switch self {
        case .nextTab: return "next tab"
        case .prevTab: return "previous tab"
        case .closeTab: return "close tab"
        case .closeAll: return "close all tabs"
        }
    }
}

/// Translates recognized gestures into key events delivered to the frontmost
/// target app. Gestures are ignored unless one of the configured apps is front,
/// so we never hijack input from unrelated windows.
final class ActionRunner {
    private let targets = Set(Config.shared.targetBundleIDs)

    // Virtual key codes (kVK_*).
    private let kTab: CGKeyCode = 48
    private let kW:   CGKeyCode = 13

    func perform(_ action: Action) {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              targets.contains(front) else { return }

        switch action {
        case .nextTab:  postKey(kTab, [.maskControl])              // Ctrl-Tab
        case .prevTab:  postKey(kTab, [.maskControl, .maskShift])  // Ctrl-Shift-Tab
        case .closeTab: postKey(kW, [.maskCommand])                // Cmd-W
        case .closeAll: postKey(kW, [.maskCommand, .maskShift])    // Cmd-Shift-W (close window)
        }
    }

    private func postKey(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
