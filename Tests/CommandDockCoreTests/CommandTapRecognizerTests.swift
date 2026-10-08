import XCTest
@testable import CommandDockCore

final class CommandTapRecognizerTests: XCTestCase {
    func testEitherCommandTriggersOnlyOnRelease() {
        for code: UInt16 in [54, 55] {
            var recognizer = CommandTapRecognizer()
            XCTAssertFalse(recognizer.flagsChanged(keyCode: code, modifiers: .command, time: 1))
            XCTAssertTrue(recognizer.flagsChanged(keyCode: code, modifiers: [], time: 1.2))
            XCTAssertFalse(recognizer.flagsChanged(keyCode: code, modifiers: [], time: 1.3))
        }
    }
    func testShortcutsNeverTrigger() {
        for key: UInt16 in [8,9,48,49,12,0] { // Copy, paste, app switch, Spotlight, quit, select all
            var recognizer = CommandTapRecognizer()
            _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1)
            recognizer.cancel() // actual keyDown, regardless of its identity
            XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 1.2), "Shortcut key \(key)")
        }
    }
    func testModifierChordsAndBothCommandsAreRejected() {
        for extra: KeyModifiers in [.shift,.control,.option,.function] {
            var recognizer = CommandTapRecognizer()
            _ = recognizer.flagsChanged(keyCode: 55, modifiers: [.command,extra], time: 1)
            XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: extra, time: 1.1))
            recognizer.reset()
            _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1)
            _ = recognizer.flagsChanged(keyCode: 56, modifiers: [.command,extra], time: 1.1)
            _ = recognizer.flagsChanged(keyCode: 56, modifiers: .command, time: 1.2)
            XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 1.3))
        }
        var recognizer = CommandTapRecognizer()
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1)
        _ = recognizer.flagsChanged(keyCode: 54, modifiers: .command, time: 1.1)
        _ = recognizer.flagsChanged(keyCode: 54, modifiers: .command, time: 1.2)
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 1.3))
    }
    func testLongHoldMouseAndResetDoNotTrigger() {
        var recognizer = CommandTapRecognizer()
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1)
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 2))
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 3)
        recognizer.cancel()
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 3.1))
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 4)
        recognizer.reset()
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 4.1))
    }
    func testAlreadyHeldKeysAndMouseButtonsRejectTap() {
        var recognizer = CommandTapRecognizer()
        recognizer.keyDown(8)
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1)
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 1.1))
        recognizer.keyUp(8)
        recognizer.mouseDown(0)
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 2)
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 2.1))
        recognizer.mouseUp(0)
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 3)
        XCTAssertTrue(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 3.1))
    }
    func testBindingsRoundTripAndRejectReservedKeys() throws {
        let binding = AppBinding(bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app", name: "Safari")
        let data = try BindingCodec.encode([12: binding, 55: binding, 65535: binding])
        XCTAssertEqual(try BindingCodec.decode(data), [12: binding])
        XCTAssertThrowsError(try BindingCodec.decode(Data("corrupt".utf8)))
        XCTAssertEqual(Set(KeyboardLayout.bindable.map(\.code)).count, KeyboardLayout.bindable.count)
        XCTAssertEqual(KeyboardLayout.key(code: 12)?.label, "Q")
        XCTAssertEqual(KeyboardLayout.key(code: 0)?.label, "A")
    }
}
