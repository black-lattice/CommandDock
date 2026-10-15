import XCTest
@testable import CommandDockCore

final class TriggerConfigurationTests: XCTestCase {
    func testSideSelectionAndShortcutDisableCommandTaps() {
        var matcher = TriggerMatcher()
        XCTAssertTrue(matcher.acceptTap(code: 55, time: 1, mode: .leftCommand))
        XCTAssertFalse(matcher.acceptTap(code: 54, time: 2, mode: .leftCommand))
        XCTAssertTrue(matcher.acceptTap(code: 54, time: 3, mode: .rightCommand))
        XCTAssertFalse(matcher.acceptTap(code: 55, time: 4, mode: .rightCommand))
        XCTAssertFalse(matcher.acceptTap(code: 55, time: 5, mode: .shortcut))
    }
    func testDoubleTapRequiresSameSideWithinWindowAndResetsAfterTrigger() {
        var matcher = TriggerMatcher()
        XCTAssertFalse(matcher.acceptTap(code: 55, time: 1, mode: .doubleCommand))
        XCTAssertFalse(matcher.acceptTap(code: 54, time: 1.1, mode: .doubleCommand))
        XCTAssertTrue(matcher.acceptTap(code: 54, time: 1.3, mode: .doubleCommand))
        XCTAssertFalse(matcher.acceptTap(code: 54, time: 1.4, mode: .doubleCommand))
        XCTAssertFalse(matcher.acceptTap(code: 54, time: 2, mode: .doubleCommand))
        matcher.reset()
        XCTAssertFalse(matcher.acceptTap(code: 54, time: 2.1, mode: .doubleCommand))
    }
    func testShortcutRequiresExactModifiersAndAtLeastOneCommandControlOrOption() {
        let shortcut = CustomHotKey()
        XCTAssertTrue(shortcut.matches(code: 49, modifiers: [.control, .option]))
        XCTAssertFalse(shortcut.matches(code: 49, modifiers: [.control, .option, .shift]))
        XCTAssertFalse(shortcut.matches(code: 12, modifiers: [.control, .option]))
        XCTAssertFalse(CustomHotKey(code: 49, modifiers: KeyModifiers.shift.rawValue).isValid)
        XCTAssertFalse(CustomHotKey(code: 53, modifiers: KeyModifiers.command.rawValue).isValid)
        XCTAssertEqual(shortcut.label, "⌃⌥space")
    }
}
