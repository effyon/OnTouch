import XCTest
import CMultitouch
@testable import OnTouch

final class GestureEngineTests: XCTestCase {
    func testNilZeroContactFrameFinishesTapAndClearsContacts() {
        var config = testConfig()
        config.mappings = [Mapping(anchor: false, fingers: 1, type: "tap",
                                   direction: "any", action: "newTab")]
        var actions: [String] = []
        let engine = GestureEngine(config: config) { action, _ in actions.append(action) }

        send([finger(1, x: 0.5, y: 0.5)], to: engine, at: 0)
        engine.handleFrame(data: nil, count: 0, timestamp: 0.02)

        XCTAssertEqual(actions, ["newTab"])
        XCTAssertEqual(GestureEngine.liveFingerCount, 0)
        engine.handleFrame(data: nil, count: 0, timestamp: 0.04)
        XCTAssertEqual(actions, ["newTab"], "An empty frame must not replay the tap")
    }

    func testNilNonemptyFrameIsIgnoredUntilValidLift() {
        var config = testConfig()
        config.mappings = [Mapping(anchor: false, fingers: 1, type: "tap",
                                   direction: "any", action: "newTab")]
        var actions: [String] = []
        let engine = GestureEngine(config: config) { action, _ in actions.append(action) }

        send([finger(1, x: 0.5, y: 0.5)], to: engine, at: 0)
        engine.handleFrame(data: nil, count: 1, timestamp: 0.01)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(GestureEngine.liveFingerCount, 1)

        engine.handleFrame(data: nil, count: 0, timestamp: 0.02)
        XCTAssertEqual(actions, ["newTab"])
    }

    func testRepeatedAnchoredTapsWithRestingThumb() {
        var actions: [String] = []
        let engine = GestureEngine(config: testConfig()) { action, _ in actions.append(action) }
        let held = [finger(1, x: 0.4, y: 0.5), finger(2, x: 0.02, y: 0.5)]
        let tap = finger(3, x: 0.7, y: 0.5)

        send(held, to: engine, at: 0)
        send(held, to: engine, at: 0.1)
        send(held + [tap], to: engine, at: 0.2)
        send(held, to: engine, at: 0.22)
        XCTAssertEqual(actions, ["nextTab"])

        send(held + [tap], to: engine, at: 0.5)
        send(held, to: engine, at: 0.52)
        XCTAssertEqual(actions, ["nextTab", "nextTab"])
    }

    func testRepeatedAnchoredSwipesWithRestingThumbFireOncePerEpisode() {
        var actions: [String] = []
        let engine = GestureEngine(config: testConfig()) { action, _ in actions.append(action) }
        let held = [finger(1, x: 0.4, y: 0.5), finger(2, x: 0.02, y: 0.5)]
        let start = [finger(3, x: 0.6, y: 0.7), finger(4, x: 0.8, y: 0.7)]
        let end = [finger(3, x: 0.6, y: 0.55), finger(4, x: 0.8, y: 0.55)]

        send(held, to: engine, at: 0)
        send(held, to: engine, at: 0.1)
        send(held + start, to: engine, at: 0.2)
        send(held + end, to: engine, at: 0.23)
        send(held + end, to: engine, at: 0.5)
        XCTAssertEqual(actions, ["closeTab"])

        send(held, to: engine, at: 0.55)
        send(held + start, to: engine, at: 0.6)
        send(held + end, to: engine, at: 0.63)
        XCTAssertEqual(actions, ["closeTab", "closeTab"])
    }

    func testMovingBeyondTapLimitClearsClickCandidates() {
        var config = testConfig()
        config.mappings = [Mapping(fingers: 1, type: "tap", direction: "right", action: "nextTab")]
        var actions: [String] = []
        let engine = GestureEngine(config: config) { action, _ in actions.append(action) }
        engine.enabled = false
        engine.enabled = true
        XCTAssertTrue(GestureEngine.clickCandidates(window: 0.25).isEmpty)

        let anchor = finger(1, x: 0.4, y: 0.5)
        send([anchor], to: engine, at: 0)
        send([anchor], to: engine, at: 0.1)
        send([anchor, finger(2, x: 0.7, y: 0.5)], to: engine, at: 0.2)
        XCTAssertEqual(GestureEngine.clickCandidates(window: 0.25).map(\.action), ["nextTab"])

        send([anchor, finger(2, x: 0.9, y: 0.5)], to: engine, at: 0.22)
        XCTAssertTrue(GestureEngine.clickCandidates(window: 0.25).isEmpty,
                      "A tap that can no longer fire must not suppress a click")
        XCTAssertTrue(actions.isEmpty)
    }

    func testDuplicateTapCandidatesFollowFirstMappingOrder() {
        var config = testConfig()
        config.mappings = [
            Mapping(fingers: 1, type: "tap", direction: "right", action: "nextTab",
                    apps: ["com.apple.Safari"]),
            Mapping(fingers: 1, type: "tap", direction: "right", action: "nextTab",
                    apps: ["com.google.Chrome"]),
        ]
        var dispatchedApps: [[String]] = []
        let engine = GestureEngine(config: config) { _, apps in dispatchedApps.append(apps) }
        engine.enabled = false
        engine.enabled = true

        let anchor = finger(1, x: 0.4, y: 0.5)
        send([anchor], to: engine, at: 0)
        send([anchor], to: engine, at: 0.1)
        send([anchor, finger(2, x: 0.7, y: 0.5)], to: engine, at: 0.2)
        let candidates = GestureEngine.clickCandidates(window: 0.25)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.apps, ["com.apple.Safari"],
                       "Click eligibility must use the binding the recognizer will choose")

        send([anchor], to: engine, at: 0.22)
        XCTAssertEqual(dispatchedApps, [["com.apple.Safari"]])
    }

    private func testConfig() -> Config {
        var config = Config()
        config.typingGuard = 0
        config.scrollGuard = 0
        return config
    }

    private func finger(_ id: Int32, x: Float, y: Float) -> Finger {
        var finger = Finger()
        finger.identifier = id
        finger.size = 0.1
        finger.normalized.position.x = x
        finger.normalized.position.y = y
        return finger
    }

    private func send(_ fingers: [Finger], to engine: GestureEngine, at timestamp: Double) {
        var fingers = fingers
        fingers.withUnsafeMutableBufferPointer { buffer in
            engine.handleFrame(data: buffer.baseAddress, count: buffer.count, timestamp: timestamp)
        }
    }
}
