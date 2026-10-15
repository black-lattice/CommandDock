import AppKit
import XCTest
import CommandDockCore
@testable import CommandDock

final class AppStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    override func setUp() {
        suite = "CommandDock.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data("{}".utf8), forKey: "bindings")
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testExchangeMoveAndPersistencePreserveAllBindingOptions() {
        let store = AppStore(defaults: defaults)
        let app = AppBinding(path: "/Applications/Test.app", name: "Test", toggleVisibility: true)
        let site = AppBinding(path: "https://example.com", name: "网站", kind: .website, browserIdentifier: "com.apple.Safari")
        store.set(app, for: 12); store.set(site, for: 13)
        store.swapBindings(12, 13)
        XCTAssertEqual(store.binding(for: 12), site)
        XCTAssertEqual(store.binding(for: 13), app)
        store.swapBindings(13, 14)
        XCTAssertNil(store.binding(for: 13))
        XCTAssertEqual(store.binding(for: 14), app)
        store.swapBindings(14, 53) // Reserved key cannot steal a binding.
        XCTAssertEqual(store.binding(for: 14), app)
        let restored = AppStore(defaults: defaults)
        XCTAssertEqual(restored.bindings, store.bindings)
    }
    func testTriggerAndExclusionPreferencesPersist() {
        let store = AppStore(defaults: defaults)
        store.triggerMode = .shortcut
        store.customHotKey = CustomHotKey(code: 12, modifiers: KeyModifiers.command.union(.shift).rawValue)
        store.pausedApplications = [PausedApplication(bundleIdentifier: "test.game", path: "/Test.app", name: "Test")]
        let restored = AppStore(defaults: defaults)
        XCTAssertEqual(restored.triggerMode, .shortcut)
        XCTAssertEqual(restored.customHotKey, store.customHotKey)
        XCTAssertEqual(restored.pausedApplications, store.pausedApplications)
    }
    func testPauseFollowsForegroundApplicationAndResumesWhenRuleRemoved() {
        let store = AppStore(defaults: defaults)
        store.pausedApplications = [PausedApplication(bundleIdentifier: "test.game", path: "/Test.app", name: "暂停目标")]
        store.updateFrontApplication(identifier: "test.game", path: "/Test.app", processIdentifier: -1)
        XCTAssertEqual(store.autoPausedAppName, "暂停目标")
        store.updateFrontApplication(identifier: "test.launcher", path: "/Launcher.app", processIdentifier: ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(store.autoPausedAppName, "暂停目标")
        store.updateFrontApplication(identifier: "test.editor", path: "/Editor.app", processIdentifier: -2)
        XCTAssertNil(store.autoPausedAppName)
        store.updateFrontApplication(identifier: "test.game", path: "/Test.app", processIdentifier: -1)
        store.pausedApplications = []
        XCTAssertNil(store.autoPausedAppName)
    }
    func testDroppedFilesAndFoldersKeepTheirNamesAndClassifyCorrectly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.v2.txt")
        try Data().write(to: file)
        XCTAssertEqual(AppStore.fileBinding(directory)?.kind, .folder)
        XCTAssertEqual(AppStore.fileBinding(file)?.kind, .file)
        XCTAssertEqual(AppStore.fileBinding(file)?.name, "notes.v2.txt")
        XCTAssertNil(AppStore.fileBinding(URL(string: "https://example.com")!))
    }
}
