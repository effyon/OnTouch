import XCTest
@testable import OnTouch

final class ActionRunnerTests: XCTestCase {
    private let finder = ActionTarget(pid: 100, bundleID: "com.apple.finder")
    private let safari = ActionTarget(pid: 200, bundleID: "com.apple.Safari")

    func testPointerOverAllowedBackgroundWindowCannotTargetForegroundApp() {
        let editor = ActionTarget(pid: 300, bundleID: "com.apple.TextEdit")
        XCTAssertNil(TargetPolicy.resolve(apps: [finder.bundleID], frontmost: editor, underPointer: finder))
        XCTAssertNil(TargetPolicy.resolve(apps: [finder.bundleID, safari.bundleID],
                                         frontmost: safari, underPointer: finder))
    }

    func testScopedTargetNeedsSameProcessAndKnownPointerOwner() {
        XCTAssertEqual(TargetPolicy.resolve(apps: [finder.bundleID], frontmost: finder,
                                            underPointer: finder), finder)
        XCTAssertNil(TargetPolicy.resolve(apps: [finder.bundleID], frontmost: finder, underPointer: nil))
        let otherProcess = ActionTarget(pid: 101, bundleID: finder.bundleID)
        XCTAssertNil(TargetPolicy.resolve(apps: [finder.bundleID], frontmost: finder,
                                         underPointer: otherProcess))
    }

    func testWildcardAndLegacyEmptyListSelectForegroundProcess() {
        XCTAssertEqual(TargetPolicy.resolve(apps: ["*"], frontmost: safari, underPointer: finder), safari)
        XCTAssertEqual(TargetPolicy.resolve(apps: [], frontmost: finder, underPointer: nil), finder)
        XCTAssertNil(TargetPolicy.resolve(apps: ["*"], frontmost: nil, underPointer: safari))
    }

    func testDispatchResolvesChromeShortcutAndPinsRecipient() {
        let chrome = ActionTarget(pid: 400, bundleID: "com.google.Chrome")
        var posts: [(Keystroke, Int32)] = []
        let runner = ActionRunner(targetProvider: { _ in chrome }, eventPoster: { posts.append(($0, $1)) })
        runner.perform(action: "nextTab", apps: [chrome.bundleID])
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.0.keyCode, 124)
        XCTAssertEqual(posts.first?.0.flags, [.maskCommand, .maskAlternate])
        XCTAssertEqual(posts.first?.1, chrome.pid)
    }

    func testUnsupportedFinderActionAndMissingTargetNeverPost() {
        var posts = 0
        let runner = ActionRunner(targetProvider: { _ in self.finder }, eventPoster: { _, _ in posts += 1 })
        XCTAssertFalse(runner.canPerform(action: "reopenTab", apps: [finder.bundleID]))
        runner.perform(action: "reopenTab", apps: [finder.bundleID])
        let missing = ActionRunner(targetProvider: { _ in nil }, eventPoster: { _, _ in posts += 1 })
        missing.perform(action: "closeTab", apps: [finder.bundleID])
        XCTAssertEqual(posts, 0)
    }

    func testNativeFinderHitWinsOverEarlierOverlayBounds() {
        let overlay = ActionTarget(pid: 300, bundleID: "com.openai.codex")
        let windows = [
            PointerWindow(number: 10, owner: overlay, layer: 3),
            PointerWindow(number: 20, owner: finder),
        ]
        let pointer = PointerTargetPolicy.resolve(hitWindowNumber: 20, windows: windows)

        XCTAssertEqual(pointer, finder)
        XCTAssertEqual(TargetPolicy.resolve(apps: [finder.bundleID], frontmost: finder,
                                            underPointer: pointer), finder)
    }

    func testRealOtherAppHitDoesNotFallThroughToFinder() {
        let otherApp = ActionTarget(pid: 300, bundleID: "com.openai.codex")
        let windows = [
            PointerWindow(number: 10, owner: otherApp),
            PointerWindow(number: 20, owner: finder),
        ]
        let pointer = PointerTargetPolicy.resolve(hitWindowNumber: 10, windows: windows)

        XCTAssertEqual(pointer, otherApp)
        XCTAssertNil(TargetPolicy.resolve(apps: [finder.bundleID], frontmost: finder,
                                          underPointer: pointer))
        XCTAssertNil(PointerTargetPolicy.resolve(hitWindowNumber: 10, windows: [
            PointerWindow(number: 10, owner: otherApp, layer: 3),
            PointerWindow(number: 20, owner: finder),
        ]))
    }

    func testMissingOrNonpositiveNativeWindowHitFailsClosed() {
        let windows = [
            PointerWindow(number: -1, owner: finder),
            PointerWindow(number: 0, owner: finder),
            PointerWindow(number: 20, owner: finder),
        ]
        for number in [-1, 0, 999] {
            XCTAssertNil(PointerTargetPolicy.resolve(hitWindowNumber: number, windows: windows))
        }
        XCTAssertNil(PointerTargetPolicy.resolve(hitWindowNumber: 20, windows: []))
    }

    func testChromeNativeWindowHitRetainsTargetPolicy() {
        let chrome = ActionTarget(pid: 400, bundleID: "com.google.Chrome")
        let windows = [
            PointerWindow(number: 20, owner: finder),
            PointerWindow(number: 30, owner: chrome),
        ]
        let pointer = PointerTargetPolicy.resolve(hitWindowNumber: 30, windows: windows)

        XCTAssertEqual(pointer, chrome)
        XCTAssertEqual(TargetPolicy.resolve(apps: [chrome.bundleID], frontmost: chrome,
                                            underPointer: pointer), chrome)
    }

    func testNativeMenuAndDockHitsDoNotFallThroughToNormalWindow() {
        let dock = ActionTarget(pid: 500, bundleID: "com.apple.dock")
        let windows = [
            PointerWindow(number: 10, owner: finder, layer: 101),
            PointerWindow(number: 20, owner: dock, layer: 20),
            PointerWindow(number: 30, owner: finder, layer: 0),
        ]

        XCTAssertNil(PointerTargetPolicy.resolve(hitWindowNumber: 10, windows: windows))
        XCTAssertNil(PointerTargetPolicy.resolve(hitWindowNumber: 20, windows: windows))
        XCTAssertEqual(PointerTargetPolicy.resolve(hitWindowNumber: 30, windows: windows), finder)
    }
}
