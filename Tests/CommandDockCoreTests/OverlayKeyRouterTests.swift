import XCTest
@testable import CommandDockCore

final class OverlayKeyRouterTests: XCTestCase {
    func testSharedExecutorPassesReservedKeysAndShortcutsButConsumesEscape() {
        var router = OverlayKeyRouter()
        var dismissals = 0
        let dismiss = { dismissals += 1 }
        let launch: (UInt16) -> Void = { _ in XCTFail("Unexpected launch") }
        for code: UInt16 in [48, 36, 51, 123, 122] {
            let action = router.keyDown(code: code, modifiers: [], visible: true, bound: false, repeatKey: false)
            XCTAssertFalse(action.perform(dismiss: dismiss, launch: launch))
            XCTAssertEqual(router.keyUp(code: code), .passThrough)
        }
        XCTAssertEqual(dismissals, 5)
        XCTAssertTrue(router.keyDown(code: 53, modifiers: [], visible: true, bound: false, repeatKey: false)
            .perform(dismiss: dismiss, launch: launch))
        XCTAssertEqual(dismissals, 6)
        XCTAssertEqual(router.keyUp(code: 53), .consume)
    }

    func testReconnectDropsMissedReleasesButKeepsStillHeldConsumedKeys() {
        var router = OverlayKeyRouter()
        _ = router.keyDown(code: 12, modifiers: [], visible: true, bound: false, repeatKey: false)
        _ = router.keyDown(code: 13, modifiers: [], visible: true, bound: false, repeatKey: false)
        router.reconcileHeldKeys { $0 == 12 }
        XCTAssertTrue(router.hasConsumedKeys)
        XCTAssertEqual(router.keyUp(code: 13), .passThrough)
        XCTAssertEqual(router.keyDown(code: 12, modifiers: [], visible: false, bound: true, repeatKey: true), .consume)
        XCTAssertEqual(router.keyUp(code: 12), .consume)
        XCTAssertFalse(router.hasConsumedKeys)
    }
    func testLaunchConsumesItsReleaseAndRepeatAfterDismissal() {
        var router = OverlayKeyRouter()
        XCTAssertEqual(router.keyDown(code: 12, modifiers: [], visible: true, bound: true, repeatKey: false), .launch(12))
        XCTAssertEqual(router.keyDown(code: 12, modifiers: [], visible: false, bound: true, repeatKey: true), .consume)
        XCTAssertEqual(router.keyUp(code: 12), .consume)
        XCTAssertEqual(router.keyUp(code: 12), .passThrough)
    }
    func testShortcutsPassThroughWhileVisibleAndHidden() {
        for modifiers: KeyModifiers in [.command,.control,.option,.shift,.function,[.command,.shift]] {
            var router = OverlayKeyRouter()
            XCTAssertEqual(router.keyDown(code: 8, modifiers: modifiers, visible: true, bound: true, repeatKey: false), .dismissAndPassThrough)
            XCTAssertEqual(router.keyUp(code: 8), .passThrough)
            XCTAssertEqual(router.keyDown(code: 8, modifiers: modifiers, visible: false, bound: true, repeatKey: false), .passThrough)
        }
    }
    func testEscapeUnknownAndUnassignedKeys() {
        var router = OverlayKeyRouter()
        XCTAssertEqual(router.keyDown(code: 53, modifiers: [], visible: true, bound: false, repeatKey: false), .dismiss)
        XCTAssertEqual(router.keyUp(code: 53), .consume)
        XCTAssertEqual(router.keyDown(code: 0, modifiers: [], visible: true, bound: false, repeatKey: false), .consume)
        XCTAssertEqual(router.keyUp(code: 0), .consume)
        XCTAssertEqual(router.keyDown(code: 123, modifiers: [], visible: true, bound: false, repeatKey: false), .dismissAndPassThrough)
        XCTAssertEqual(router.keyUp(code: 123), .passThrough)
    }
}
