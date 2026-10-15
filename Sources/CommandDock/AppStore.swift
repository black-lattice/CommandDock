import AppKit
import Combine
import UniformTypeIdentifiers
import CommandDockCore

final class AppStore: ObservableObject {
    @Published private(set) var bindings: [UInt16: AppBinding] = [:]
    @Published var listenerReady = false
    @Published var listenerMessage = ""
    @Published var paused = false
    @Published var autoPausedAppName: String?
    @Published var pausedApplications: [PausedApplication] {
        didSet {
            defaults.set(try? JSONEncoder().encode(pausedApplications), forKey: "pausedApplications")
            updateFrontApplication(NSWorkspace.shared.frontmostApplication)
        }
    }
    private var lastExternalApplication: (identifier: String?, path: String?)?
    @Published var triggerMode: TriggerMode {
        didSet { defaults.set(triggerMode.rawValue, forKey: "triggerMode") }
    }
    @Published var customHotKey: CustomHotKey {
        didSet { defaults.set(try? JSONEncoder().encode(customHotKey), forKey: "customHotKey") }
    }
    @Published var blindLaunchEnabled: Bool {
        didSet { defaults.set(blindLaunchEnabled, forKey: "blindLaunchEnabled") }
    }
    @Published var hintDelay: Double {
        didSet { defaults.set(hintDelay, forKey: "hintDelay") }
    }
    @Published var experiment = LauncherExperiment()
    @Published var errorMessage: String?
    @Published var tapDuration: Double {
        didSet { defaults.set(tapDuration, forKey: "tapDuration") }
    }
    private var iconCache: [String: NSImage] = [:]
    private var applicationURLs = ApplicationURLCache()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pausedApplications = defaults.data(forKey: "pausedApplications")
            .flatMap { try? JSONDecoder().decode([PausedApplication].self, from: $0) } ?? []
        triggerMode = TriggerMode(rawValue: defaults.string(forKey: "triggerMode") ?? "") ?? .eitherCommand
        customHotKey = defaults.data(forKey: "customHotKey")
            .flatMap { try? JSONDecoder().decode(CustomHotKey.self, from: $0) } ?? CustomHotKey()
        blindLaunchEnabled = defaults.bool(forKey: "blindLaunchEnabled")
        let delay = defaults.object(forKey: "hintDelay") as? Double ?? 0.25
        hintDelay = delay.isFinite ? min(max(delay, 0.1), 0.6) : 0.25
        let savedDuration = defaults.double(forKey: "tapDuration")
        tapDuration = savedDuration.isFinite && savedDuration > 0 ? min(max(savedDuration, 0.2), 0.8) : 0.5
        if let data = defaults.data(forKey: "bindings") {
            do { bindings = try BindingCodec.decode(data) }
            catch { errorMessage = "绑定配置无法读取，已保留原配置。可导入备份或重新绑定。" }
        } else {
            installDefaults()
        }
    }

    func updateFrontApplication(_ application: NSRunningApplication?) {
        updateFrontApplication(identifier: application?.bundleIdentifier, path: application?.bundleURL?.path,
            processIdentifier: application?.processIdentifier ?? ProcessInfo.processInfo.processIdentifier)
    }
    func updateFrontApplication(identifier: String?, path: String?, processIdentifier: pid_t) {
        if processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplication = (identifier, path)
        }
        let name = lastExternalApplication.flatMap { app in
            pausedApplications.first(where: { $0.matches(identifier: app.identifier, path: app.path) })?.name
        }
        if autoPausedAppName != name { autoPausedAppName = name }
    }
    func binding(for code: UInt16) -> AppBinding? { bindings[code] }
    func url(for binding: AppBinding, refresh: Bool = false) -> URL? {
        if binding.kind == .shortcut { return binding.shortcutURL }
        if binding.kind == .website { return AppBinding.websiteURL(binding.path) }
        return applicationURLs.url(for: binding, refresh: refresh) { binding in
            if binding.kind == .application, let identifier = binding.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { return url }
            guard binding.path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: binding.path)
            if binding.kind == .application && (url.pathExtension.lowercased() != "app" || Bundle(url: url) == nil) { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
    func refreshApplicationCache() {
        applicationURLs.removeAll()
        iconCache.removeAll()
        objectWillChange.send()
    }
    func icon(for binding: AppBinding) -> NSImage {
        let key = binding.kind.rawValue + ":" + (binding.bundleIdentifier ?? binding.path)
        if let cached = iconCache[key] { return cached }
        let image: NSImage
        switch binding.kind {
        case .website: image = NSImage(systemSymbolName: "globe", accessibilityDescription: "网址")!
        case .shortcut: image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "快捷指令")!
        default:
            image = url(for: binding).map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: "目标不存在")!
        }
        image.size = NSSize(width: 28, height: 28)
        iconCache[key] = image
        return image
    }
    func set(_ binding: AppBinding?, for code: UInt16) {
        bindings[code] = binding
        refreshApplicationCache()
        persist()
    }
    func swapBindings(_ first: UInt16, _ second: UInt16) {
        guard first != second, KeyboardLayout.key(code: first) != nil,
              KeyboardLayout.key(code: second) != nil, bindings[first] != nil else { return }
        let original = bindings[first]
        bindings[first] = bindings[second]
        bindings[second] = original
        refreshApplicationCache()
        persist()
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
