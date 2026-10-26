import XCTest
import CoreGraphics
@testable import OnTouch

final class ClickSuppressionStateTests: XCTestCase {
    func testEligibleClickSuppressesBothEvents() {
        var state = ClickSuppressionState()

        XCTAssertTrue(state.shouldSuppress(.leftMouseDown, eligible: true))
        XCTAssertTrue(state.shouldSuppress(.leftMouseUp, eligible: true))
    }

    func testIneligibleClickPassesBothEvents() {
        var state = ClickSuppressionState()

        XCTAssertFalse(state.shouldSuppress(.leftMouseDown, eligible: false))
        XCTAssertFalse(state.shouldSuppress(.leftMouseUp, eligible: false))
    }

    func testDragReleasePassesWhenGestureBecomesEligibleAfterDown() {
        var state = ClickSuppressionState()

        XCTAssertFalse(state.shouldSuppress(.leftMouseDown, eligible: false))
        XCTAssertFalse(state.shouldSuppress(.leftMouseUp, eligible: true))
    }

    func testSuppressedClickDrainsAfterDisableOrContextChange() {
        var state = ClickSuppressionState()

        XCTAssertTrue(state.shouldSuppress(.leftMouseDown, eligible: true))
        XCTAssertTrue(state.shouldSuppress(.leftMouseUp, eligible: false))
        XCTAssertFalse(state.shouldSuppress(.leftMouseDown, eligible: false))
        XCTAssertFalse(state.shouldSuppress(.leftMouseUp, eligible: false))
    }

    func testUnpairedReleaseAlwaysPasses() {
        var state = ClickSuppressionState()

        XCTAssertFalse(state.shouldSuppress(.leftMouseUp, eligible: true))
        XCTAssertTrue(state.shouldSuppress(.leftMouseDown, eligible: true))
        XCTAssertTrue(state.shouldSuppress(.leftMouseUp, eligible: true))
        XCTAssertFalse(state.shouldSuppress(.leftMouseUp, eligible: true))
    }

    func testUnrelatedEventsPassWithoutChangingPendingPair() {
        var state = ClickSuppressionState()

        XCTAssertTrue(state.shouldSuppress(.leftMouseDown, eligible: true))
        for type in [CGEventType.rightMouseDown, .rightMouseUp, .keyDown, .mouseMoved] {
            XCTAssertFalse(state.shouldSuppress(type, eligible: true))
        }
        XCTAssertTrue(state.shouldSuppress(.leftMouseUp, eligible: false))
        XCTAssertFalse(state.shouldSuppress(.leftMouseUp, eligible: true))
    }
}
