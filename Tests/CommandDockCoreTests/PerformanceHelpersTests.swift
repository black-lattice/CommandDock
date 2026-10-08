import XCTest
@testable import CommandDockCore

final class PerformanceHelpersTests: XCTestCase {
    func testBoundedReaderReadsSmallFileAndRejectsExactLimit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("{}".utf8)
        try data.write(to: file)
        XCTAssertEqual(try BoundedFileReader.read(from: file, maximumBytes: 3), data)
        XCTAssertThrowsError(try BoundedFileReader.read(from: file, maximumBytes: 2)) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.fileReadTooLarge.rawValue)
        }
    }

    func testBoundedReaderRejectsLargeSparseFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 2_000_000_000)
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        XCTAssertThrowsError(try BoundedFileReader.read(from: file, maximumBytes: 1_000_000)) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.fileReadTooLarge.rawValue)
        }
    }

    func testURLCacheStoresMissingResultsAndRefreshesMovedApplications() {
        var cache = ApplicationURLCache()
        let binding = AppBinding(bundleIdentifier: "test.app", path: "/Applications/Old.app", name: "Test")
        var queries = 0
        var location: URL?
        let resolve: (AppBinding) -> URL? = { _ in queries += 1; return location }
        XCTAssertNil(cache.url(for: binding, resolve: resolve))
        XCTAssertNil(cache.url(for: binding, resolve: resolve))
        XCTAssertEqual(queries, 1)
        location = URL(fileURLWithPath: "/Applications/New.app")
        XCTAssertEqual(cache.url(for: binding, refresh: true, resolve: resolve), location)
        XCTAssertEqual(cache.url(for: binding, resolve: resolve), location)
        XCTAssertEqual(queries, 2)
        cache.removeAll()
        XCTAssertEqual(cache.url(for: binding, resolve: resolve), location)
        XCTAssertEqual(queries, 3)
    }

    func testURLCacheDistinguishesFallbackPathsForSameIdentifier() {
        var cache = ApplicationURLCache()
        let first = AppBinding(bundleIdentifier: "test.app", path: "/Applications/First.app", name: "First")
        let second = AppBinding(bundleIdentifier: "test.app", path: "/Applications/Second.app", name: "Second")
        let resolve: (AppBinding) -> URL? = { URL(fileURLWithPath: $0.path) }
        XCTAssertEqual(cache.url(for: first, resolve: resolve)?.path, first.path)
        XCTAssertEqual(cache.url(for: second, resolve: resolve)?.path, second.path)
    }
}
