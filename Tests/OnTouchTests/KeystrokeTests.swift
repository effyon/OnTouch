import CoreGraphics
import XCTest
@testable import OnTouch

final class KeystrokeTests: XCTestCase {
    func testFinderVerifiedTabAndNavigationActions() {
        let expected: [(String, CGKeyCode, CGEventFlags)] = [
            ("nextTab", 48, .maskControl),
            ("prevTab", 48, [.maskControl, .maskShift]),
            ("closeTab", 13, .maskCommand),
            ("newTab", 17, .maskCommand),
            ("back", 33, .maskCommand),
            ("forward", 30, .maskCommand),
            ("newWindow", 45, .maskCommand),
        ]
        for (action, keyCode, flags) in expected {
            assertKeystroke(action, app: "com.apple.finder", keyCode: keyCode, flags: flags)
        }
    }

    func testFinderRejectsBrowserActionsInsteadOfRepurposingShortcuts() {
        for action in ["reopenTab", "closeWindow", "reload", "privateWindow",
                       "showAllTabs", "zoomIn", "zoomOut", "firstTab"] {
            XCTAssertNil(Keys.parse(action, targetBundleID: "com.apple.finder"), action)
        }
    }

    func testFinderAllowsExplicitUserChords() {
        // These collide as named browser actions, but a literal is intentional.
        assertKeystroke("cmd+shift+t", app: "com.apple.finder", keyCode: 17,
                        flags: [.maskCommand, .maskShift])
        assertKeystroke("cmd+r", app: "com.apple.finder", keyCode: 15, flags: .maskCommand)
        assertKeystroke("cmd+shift+n", app: "com.apple.finder", keyCode: 45,
                        flags: [.maskCommand, .maskShift])
        assertKeystroke("cmd+1", app: "com.apple.finder", keyCode: 18, flags: .maskCommand)
    }

    func testChromeUsesOrderedTabShortcuts() {
        assertKeystroke("nextTab", app: "com.google.Chrome", keyCode: 124,
                        flags: [.maskCommand, .maskAlternate])
        assertKeystroke("prevTab", app: "com.google.Chrome", keyCode: 123,
                        flags: [.maskCommand, .maskAlternate])
    }

    func testChromeOtherActionsRetainExistingShortcuts() {
        assertKeystroke("closeTab", app: "com.google.Chrome", keyCode: 13, flags: .maskCommand)
        assertKeystroke("reopenTab", app: "com.google.Chrome", keyCode: 17,
                        flags: [.maskCommand, .maskShift])
        // Tab overview is not silently reinterpreted as Chrome Tab Search.
        assertKeystroke("showAllTabs", app: "com.google.Chrome", keyCode: 42,
                        flags: [.maskCommand, .maskShift])
    }

    func testSafariDefaultsAreUnaffected() {
        assertKeystroke("nextTab", app: "com.apple.Safari", keyCode: 48, flags: .maskControl)
        assertKeystroke("prevTab", app: "com.apple.Safari", keyCode: 48,
                        flags: [.maskControl, .maskShift])
        assertKeystroke("closeTab", app: "com.apple.Safari", keyCode: 13, flags: .maskCommand)
        assertKeystroke("reopenTab", app: "com.apple.Safari", keyCode: 17,
                        flags: [.maskCommand, .maskShift])
        assertKeystroke("showAllTabs", app: "com.apple.Safari", keyCode: 42,
                        flags: [.maskCommand, .maskShift])
    }

    func testNoTargetRetainsGenericBuiltins() {
        assertKeystroke("nextTab", keyCode: 48, flags: .maskControl)
        assertKeystroke("privateWindow", keyCode: 45, flags: [.maskCommand, .maskShift])
    }

    func testOtherAppsRetainGenericBehavior() {
        for app in ["com.brave.Browser", "com.microsoft.edgemac", "example.custom"] {
            assertKeystroke("nextTab", app: app, keyCode: 48, flags: .maskControl)
        }
    }

    func testFirefoxPrivateWindowUsesItsOwnShortcut() {
        assertKeystroke("privateWindow", app: "org.mozilla.firefox", keyCode: 35,
                        flags: [.maskCommand, .maskShift])
        assertKeystroke("reopenTab", app: "org.mozilla.firefox", keyCode: 17,
                        flags: [.maskCommand, .maskShift])
    }

    func testExplicitChordBypassesChromeNamedActionOverride() {
        assertKeystroke("ctrl+tab", app: "com.google.Chrome", keyCode: 48, flags: .maskControl)
    }

    func testUnknownActionsAndInvalidChordsAreRejected() {
        for action in ["", "unknownAction", "cmd+unknownKey", "unknownModifier+t"] {
            XCTAssertNil(Keys.parse(action, targetBundleID: "com.apple.finder"), action)
            XCTAssertNil(Keys.parse(action), action)
        }
    }

    private func assertKeystroke(_ action: String, app: String? = nil,
                                 keyCode: CGKeyCode, flags: CGEventFlags,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let result = Keys.parse(action, targetBundleID: app)
        XCTAssertNotNil(result, action, file: file, line: line)
        XCTAssertEqual(result?.keyCode, keyCode, action, file: file, line: line)
        XCTAssertEqual(result?.flags.rawValue, flags.rawValue, action, file: file, line: line)
    }
}
