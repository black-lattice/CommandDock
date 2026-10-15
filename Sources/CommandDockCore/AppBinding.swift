import Foundation

public enum BindingKind: String, Codable, CaseIterable {
    case application, file, folder, website, shortcut
    public var title: String {
        switch self {
        case .application: return "应用"
        case .file: return "文件"
        case .folder: return "文件夹"
        case .website: return "网址"
        case .shortcut: return "快捷指令"
        }
    }
}

public struct AppBinding: Codable, Equatable {
    public var bundleIdentifier: String?
    public var path: String
    public var name: String
    public var kind: BindingKind
    public var browserIdentifier: String?
    public var browserPath: String?
    public var toggleVisibility: Bool

    public init(bundleIdentifier: String? = nil, path: String, name: String,
                kind: BindingKind = .application, browserIdentifier: String? = nil, browserPath: String? = nil, toggleVisibility: Bool = false) {
        self.bundleIdentifier = bundleIdentifier; self.path = path; self.name = name
        self.toggleVisibility = toggleVisibility
        self.kind = kind; self.browserIdentifier = browserIdentifier; self.browserPath = browserPath
    }
    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, path, name, kind, browserIdentifier, browserPath, toggleVisibility
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        path = try values.decode(String.self, forKey: .path)
        name = try values.decode(String.self, forKey: .name)
        // Files exported by 1.0.x contain only application fields.
        kind = try values.decodeIfPresent(BindingKind.self, forKey: .kind) ?? .application
        browserIdentifier = try values.decodeIfPresent(String.self, forKey: .browserIdentifier)
        browserPath = try values.decodeIfPresent(String.self, forKey: .browserPath)
        toggleVisibility = try values.decodeIfPresent(Bool.self, forKey: .toggleVisibility) ?? false
    }
    public var shortcutURL: URL? {
        guard kind == .shortcut, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "shortcuts"; parts.host = "run-shortcut"
        parts.queryItems = [URLQueryItem(name: "name", value: path)]
        return parts.url
    }
    public static func websiteURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
