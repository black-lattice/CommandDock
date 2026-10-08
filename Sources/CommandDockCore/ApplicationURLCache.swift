import Foundation

public struct ApplicationURLCache {
    private struct Key: Hashable {
        let identifier: String?
        let path: String
    }
    private var values: [Key: URL?] = [:]
    public init() {}

    public mutating func url(for binding: AppBinding, refresh: Bool = false,
                             resolve: (AppBinding) -> URL?) -> URL? {
        let key = Key(identifier: binding.bundleIdentifier, path: binding.path)
        if !refresh, let cached = values[key] { return cached }
        let result = resolve(binding)
        values.updateValue(result, forKey: key)
        return result
    }

    public mutating func removeAll() { values.removeAll() }
}
