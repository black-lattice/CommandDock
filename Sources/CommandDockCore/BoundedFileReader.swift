import Foundation

public enum BoundedFileReader {
    public static func read(from url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes) ?? Data()
        guard data.count < maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
