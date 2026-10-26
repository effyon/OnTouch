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
}
