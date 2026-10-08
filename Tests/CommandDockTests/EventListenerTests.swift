import AppKit
import XCTest
import CommandDockCore
@testable import CommandDock

final class EventListenerTests: XCTestCase {
    private func key(_ code: UInt16, down: Bool = true, modifiers: CGEventFlags = [], repeatKey: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = modifiers
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return event
    }

    private func flags(_ code: UInt16, modifiers: CGEventFlags, at seconds: Double) -> CGEvent {
        let event = key(code, modifiers: modifiers)
        event.type = .flagsChanged
        event.timestamp = UInt64(seconds * 1_000_000_000)
        return event
    }

    private func localKey(_ code: UInt16, down: Bool = true, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero,
            modifierFlags: modifiers, timestamp: 1, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
    }

    func testLocalAndGlobalReservedKeysAndShortcutsActuallyPassThrough() {
        for local in [false, true] {
            for code: UInt16 in [48, 36, 51, 123, 122, 8] {
                let listener = EventListener()
                var active = true
                var dismissals = 0
                listener.active = { active }
                listener.dismiss = { active = false; dismissals += 1 }
                listener.launch = { _ in XCTFail("Shortcut must not launch a binding") }
                listener.bound = { _ in true }
                if local {
                    XCTAssertNotNil(listener.handleLocalEvent(localKey(code, modifiers: code == 8 ? .command : [])))
                    XCTAssertNotNil(listener.handleLocalEvent(localKey(code, down: false)))
                } else {
                    XCTAssertTrue(listener.handle(.keyDown, key(code, modifiers: code == 8 ? .maskCommand : [])) != nil)
                    XCTAssertTrue(listener.handle(.keyUp, key(code, down: false)) != nil)
                }
                XCTAssertFalse(active)
                XCTAssertEqual(dismissals, 1)
            }
        }
    }

    func testBothPathsLaunchOnceAndConsumeRepeatAndReleaseAfterSessionEnds() {
        for local in [false, true] {
            let listener = EventListener()
            var active = true
            var launches: [UInt16] = []
            listener.enabled = { active }
            listener.active = { active }
            listener.bound = { $0 == 12 }
            listener.dismiss = { XCTFail("Launch must not restore old focus") }
            listener.launch = { launches.append($0); active = false }
            if local {
                XCTAssertNil(listener.handleLocalEvent(localKey(12)))
                XCTAssertNil(listener.handleLocalEvent(localKey(12, repeatKey: true)))
                XCTAssertNil(listener.handleLocalEvent(localKey(12, down: false)))
            } else {
                XCTAssertTrue(listener.handle(.keyDown, key(12)) == nil)
                XCTAssertTrue(listener.handle(.keyDown, key(12, repeatKey: true)) == nil)
                XCTAssertTrue(listener.handle(.keyUp, key(12, down: false)) == nil)
            }
            XCTAssertEqual(launches, [12])
        }
    }

    func testCommandReleaseArmsBeforeTheVeryNextEventAndNeverPresentsAfterLaunch() {
        let listener = EventListener()
        var session = LauncherSession()
        var token: UInt64 = 0
        var launches = 0
        listener.active = { session.isActive }
        listener.bound = { $0 == 12 }
        listener.toggle = { token = session.begin() }
        listener.launch = { _ in launches += 1; session.end() }
        _ = listener.handle(.flagsChanged, flags(55, modifiers: .maskCommand, at: 1))
        _ = listener.handle(.flagsChanged, flags(55, modifiers: [], at: 1.1))
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertTrue(listener.handle(.keyDown, key(12)) == nil)
        XCTAssertEqual(launches, 1)
        XCTAssertFalse(session.reveal(token: token))
    }

    func testPendingSessionCancelsOnModifierAndDoesNotReopenOnRelease() {
        let listener = EventListener()
        var active = true
        var toggles = 0
        listener.active = { active }
        listener.dismiss = { active = false }
        listener.toggle = { toggles += 1 }
        _ = listener.handle(.flagsChanged, flags(55, modifiers: .maskCommand, at: 1))
        _ = listener.handle(.flagsChanged, flags(55, modifiers: [], at: 1.1))
        XCTAssertFalse(active)
        XCTAssertEqual(toggles, 0)
    }

    func testManualPreviewStillRoutesKeysWhenGlobalTriggerIsPaused() {
        let listener = EventListener()
        listener.enabled = { false }
        listener.active = { true }
        listener.bound = { $0 == 12 }
        var launches = 0
        listener.launch = { _ in launches += 1 }
        XCTAssertTrue(listener.handle(.keyDown, key(12)) == nil)
        XCTAssertEqual(launches, 1)
        XCTAssertTrue(listener.handle(.keyUp, key(12, down: false)) == nil)
    }

    func testUnboundPendingKeyRevealsHintAndConsumesRelease() {
        let listener = EventListener()
        var session = LauncherSession()
        let token = session.begin()
        listener.active = { session.isActive }
        listener.visible = { session.phase == .visible }
        listener.reveal = { XCTAssertTrue(session.reveal(token: token)) }
        XCTAssertTrue(listener.handle(.keyDown, key(0)) == nil)
        XCTAssertEqual(session.phase, .visible)
        XCTAssertTrue(listener.handle(.keyUp, key(0, down: false)) == nil)
    }

    func testMouseClickCancelsPendingSessionWithoutSwallowingClick() {
        let listener = EventListener()
        var active = true
        listener.active = { active }
        listener.visible = { false }
        listener.dismiss = { XCTFail("An outside click must not restore old focus") }
        listener.outsideClick = { active = false }
        let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        XCTAssertTrue(listener.handle(.leftMouseDown, event) != nil)
        XCTAssertFalse(active)
    }
}
