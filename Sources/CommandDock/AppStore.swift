import AppKit
import Combine
import UniformTypeIdentifiers
import CommandDockCore

final class AppStore: ObservableObject {
    @Published private(set) var bindings: [UInt16: AppBinding] = [:]
    @Published var listenerReady = false
    @Published var listenerMessage = ""
    @Published var paused = false
    @Published var errorMessage: String?
    @Published var tapDuration: Double {
        didSet { UserDefaults.standard.set(tapDuration, forKey: "tapDuration") }
    }
    private var iconCache: [String: NSImage] = [:]
    private var applicationURLs = ApplicationURLCache()
    private let defaults = UserDefaults.standard

    init() {
        let savedDuration = UserDefaults.standard.double(forKey: "tapDuration")
        tapDuration = savedDuration > 0 ? savedDuration : 0.5
        if let data = defaults.data(forKey: "bindings") {
            do { bindings = try BindingCodec.decode(data) }
            catch { errorMessage = "绑定配置无法读取，已保留原配置。可导入备份或重新绑定。" }
        } else {
            installDefaults()
        }
    }

    func binding(for code: UInt16) -> AppBinding? { bindings[code] }
    func url(for binding: AppBinding, refresh: Bool = false) -> URL? {
        applicationURLs.url(for: binding, refresh: refresh) { binding in
            if let identifier = binding.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { return url }
            let url = URL(fileURLWithPath: binding.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
    func refreshApplicationCache() {
        applicationURLs.removeAll()
        iconCache.removeAll()
        objectWillChange.send()
    }
    func icon(for binding: AppBinding) -> NSImage {
        let key = binding.bundleIdentifier ?? binding.path
        if let cached = iconCache[key] { return cached }
        let image = url(for: binding).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: "应用未安装")!
        image.size = NSSize(width: 28, height: 28)
        iconCache[key] = image
        return image
    }
    func chooseApplication(for key: KeyboardKey) {
        let picker = NSOpenPanel()
        picker.title = "为 \(key.label) 绑定应用"
        picker.message = "选择一个 .app 应用。可以前往「应用程序」或其他目录。"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.applicationBundle]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard let bundle = Bundle(url: url), url.pathExtension == "app" else {
            errorMessage = "请选择有效的 macOS 应用。"; return
        }
        set(AppBinding(bundleIdentifier: bundle.bundleIdentifier, path: url.path,
                       name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")), for: key.code)
    }
    func set(_ binding: AppBinding?, for code: UInt16) {
        bindings[code] = binding
        refreshApplicationCache()
        persist()
    }
    func launch(_ code: UInt16) {
        guard let binding = bindings[code] else { return }
        guard let url = url(for: binding, refresh: true) else {
            errorMessage = "未找到「\(binding.name)」。请先安装应用，或在设置中重新绑定。"; return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            guard let error = error else { return }
            DispatchQueue.main.async { self?.errorMessage = "无法打开「\(binding.name)」：\(error.localizedDescription)" }
        }
    }
    func installDefaults() {
        let identifiers: [(UInt16, String)] = [
            (12,"com.apple.Safari"),(13,"com.apple.mail"),(14,"com.apple.finder"),
            (15,"com.apple.Terminal"),(17,"com.apple.iCal"),(0,"com.apple.AppStore"),
            (1,"com.apple.systempreferences"),(2,"com.apple.Notes"),(3,"com.google.Chrome"),
            (6,"com.apple.Music"),(8,"com.apple.calculator"),(9,"com.apple.Preview")
        ]
        bindings = [:]
        for (code, identifier) in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                bindings[code] = AppBinding(bundleIdentifier: identifier, path: url.path,
                    name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            }
        }
        refreshApplicationCache()
        persist()
    }
    func exportBindings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CommandDock-bindings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try BindingCodec.encode(bindings).write(to: url, options: .atomic) }
        catch { errorMessage = "导出失败：\(error.localizedDescription)" }
    }
    func importBindings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BoundedFileReader.read(from: url, maximumBytes: 1_000_000)
            let imported = try BindingCodec.decode(data)
            bindings = imported
            refreshApplicationCache()
            persist()
        } catch { errorMessage = "导入失败，原绑定未修改：\(error.localizedDescription)" }
    }
    private func persist() {
        do { defaults.set(try BindingCodec.encode(bindings), forKey: "bindings") }
        catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }
}
