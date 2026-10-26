import CoreGraphics

/// Keeps mouse-button pairs consistent when gesture eligibility changes.
struct ClickSuppressionState {
    private var suppressedLeftMouseDown = false

    mutating func shouldSuppress(_ type: CGEventType, eligible: Bool) -> Bool {
        switch type {
        case .leftMouseDown:
            suppressedLeftMouseDown = eligible
            return eligible
        case .leftMouseUp:
            let suppress = suppressedLeftMouseDown
            suppressedLeftMouseDown = false
            return suppress
        default:
            return false
        }
    }
}
