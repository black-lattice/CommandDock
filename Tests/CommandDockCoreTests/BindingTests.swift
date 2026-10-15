import XCTest
@testable import CommandDockCore

final class BindingTests: XCTestCase {
    func testLegacyBindingsImportAsApplications() throws {
        let data = Data(#"{"12":{"path":"/Applications/Safari.app","name":"Safari","bundleIdentifier":"com.apple.Safari"}}"#.utf8)
        let binding = try XCTUnwrap(BindingCodec.decode(data)[12])
        XCTAssertEqual(binding.kind, .application)
        XCTAssertFalse(binding.toggleVisibility)
        XCTAssertEqual(binding.bundleIdentifier, "com.apple.Safari")
    }
    func testAllKindsRoundTripWithBrowserPreference() throws {
        for kind in BindingKind.allCases {
            let binding = AppBinding(path: "https://example.com", name: "测试", kind: kind,
                browserIdentifier: "com.apple.Safari", browserPath: "/Applications/Safari.app", toggleVisibility: true)
            XCTAssertEqual(try BindingCodec.decode(BindingCodec.encode([12: binding]))[12], binding)
        }
    }
    func testWebsiteValidationRejectsExecutableSchemesAndMissingHosts() {
        for input in ["javascript:alert(1)", "file:///tmp/test", "https://", "example.com", ""] {
            XCTAssertNil(AppBinding.websiteURL(input))
        }
        XCTAssertEqual(AppBinding.websiteURL(" https://example.com/a?q=1 ")?.host, "example.com")
    }
    func testShortcutNamesCannotInjectExtraURLParameters() throws {
        let binding = AppBinding(path: "工作 & name=另一个/测试?#", name: "工作", kind: .shortcut)
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(binding.shortcutURL), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "shortcuts")
        XCTAssertEqual(parts.host, "run-shortcut")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "name", value: binding.path)])
        XCTAssertNil(AppBinding(path: "  ", name: "", kind: .shortcut).shortcutURL)
    }
    func testDragPayloadDoesNotInterpretOrdinaryTextOrReservedKeysAsBindings() {
        XCTAssertEqual(BindingDragPayload.decode(BindingDragPayload.encode(12)), 12)
        for text in ["12", "https://example.com", "CommandDock key 53", "CommandDock key 99999"] {
            XCTAssertNil(BindingDragPayload.decode(text))
        }
    }
    func testUnknownKindFailsInsteadOfReinterpretingTargetAsApplication() {
        let data = Data(#"{"12":{"path":"target","name":"test","kind":"unsupported"}}"#.utf8)
        XCTAssertThrowsError(try BindingCodec.decode(data))
    }
}
