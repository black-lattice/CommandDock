import XCTest
@testable import CommandDockCore

final class LauncherSessionTests: XCTestCase {
    func testFastLaunchBeforePresentationConsumesRepeatAndReleaseAndCancelsHint() {
        var recognizer = CommandTapRecognizer()
        var session = LauncherSession()
        var router = OverlayKeyRouter()
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1))
        XCTAssertTrue(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 1.1))
        let token = session.begin()
        // No run-loop turn or window presentation occurs before the next key.
        XCTAssertEqual(session.phase, .waiting)
        let action = router.keyDown(code: 12, modifiers: [], visible: session.isActive, bound: true, repeatKey: false)
        var launches: [UInt16] = []
        XCTAssertTrue(action.perform(dismiss: { XCTFail("Launch must not restore the old app") }, launch: {
            launches.append($0)
            session.end()
        }))
        XCTAssertEqual(launches, [12])
        XCTAssertFalse(session.reveal(token: token))
        XCTAssertEqual(router.keyDown(code: 12, modifiers: [], visible: session.isActive, bound: true, repeatKey: true), .consume)
        XCTAssertEqual(router.keyUp(code: 12), .consume)
        XCTAssertEqual(router.keyDown(code: 12, modifiers: [], visible: false, bound: true, repeatKey: false), .passThrough)
    }

    func testCancellationAndReplacementInvalidateOldPresentation() {
        var session = LauncherSession()
        let cancelled = session.begin()
        session.end() // Escape, mouse, settings, sleep, or foreground app change.
        XCTAssertFalse(session.reveal(token: cancelled))
        let replaced = session.begin()
        let current = session.begin()
        XCTAssertFalse(session.reveal(token: replaced))
        XCTAssertTrue(session.reveal(token: current))
        XCTAssertFalse(session.reveal(token: current)) // Only one presentation.
    }

    func testShortcutDuringWaitingDismissesWithoutConsumingEitherHalf() {
        for modifiers: KeyModifiers in [.command, .control, .option, .shift, .function] {
            var session = LauncherSession()
            var router = OverlayKeyRouter()
            let token = session.begin()
            let action = router.keyDown(code: 8, modifiers: modifiers, visible: session.isActive, bound: true, repeatKey: false)
            XCTAssertFalse(action.perform(dismiss: { session.end() }, launch: { _ in XCTFail() }))
            XCTAssertEqual(router.keyUp(code: 8), .passThrough)
            XCTAssertFalse(session.reveal(token: token))
        }
    }

    func testUnboundKeyCanRevealHintWhileStillConsumingItsRelease() {
        var session = LauncherSession()
        var router = OverlayKeyRouter()
        let token = session.begin()
        XCTAssertEqual(router.keyDown(code: 0, modifiers: [], visible: session.isActive, bound: false, repeatKey: false), .consume)
        XCTAssertTrue(session.reveal(token: token))
        XCTAssertEqual(router.keyUp(code: 0), .consume)
        XCTAssertTrue(session.isActive)
    }

    func testAnotherCommandCancelsWithoutReopeningOnRelease() {
        var session = LauncherSession()
        var recognizer = CommandTapRecognizer()
        let token = session.begin()
        _ = recognizer.flagsChanged(keyCode: 55, modifiers: .command, time: 1)
        recognizer.cancel()
        session.end()
        XCTAssertFalse(recognizer.flagsChanged(keyCode: 55, modifiers: [], time: 1.1))
        XCTAssertFalse(session.reveal(token: token))
    }

    func testFocusReturnsOnlyWhenTheUserHasNotSwitchedApplications() {
        XCTAssertTrue(LauncherFocusPolicy.shouldRestore(previous: 10, current: 10, launcher: 20))
        XCTAssertTrue(LauncherFocusPolicy.shouldRestore(previous: 10, current: 20, launcher: 20))
        XCTAssertFalse(LauncherFocusPolicy.shouldRestore(previous: 10, current: 30, launcher: 20))
        XCTAssertFalse(LauncherFocusPolicy.shouldRestore(previous: 10, current: nil, launcher: 20))
        XCTAssertFalse(LauncherFocusPolicy.shouldRestore(previous: nil, current: 20, launcher: 20))
        XCTAssertFalse(LauncherFocusPolicy.shouldRestore(previous: 20, current: 20, launcher: 20))
    }

    func testExperimentCountsAndMeasuresLaunchRequestsOnly() {
        var experiment = LauncherExperiment()
        XCTAssertNil(experiment.averageResponseTime)
        experiment.recordLaunch(beforeHint: true, responseTime: 0.1)
        experiment.recordLaunch(beforeHint: false, responseTime: 0.5)
        experiment.recordCancellation()
        experiment.recordLaunch(beforeHint: true, responseTime: -.infinity)
        XCTAssertEqual(experiment.launchesBeforeHint, 1)
        XCTAssertEqual(experiment.launchesAfterHint, 1)
        XCTAssertEqual(experiment.cancellations, 1)
        XCTAssertEqual(experiment.averageResponseTime!, 0.3, accuracy: 0.0001)
    }
}
