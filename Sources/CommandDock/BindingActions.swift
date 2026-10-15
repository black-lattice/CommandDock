import AppKit
import UniformTypeIdentifiers
import CommandDockCore

extension AppStore {
    static func chooseURL(kind: BindingKind) -> URL? {
        let picker = NSOpenPanel()
        picker.title = "选择\(kind.title)"
        picker.canChooseDirectories = kind == .folder
        picker.canChooseFiles = kind != .folder
        picker.allowsMultipleSelection = false
        if kind == .application {
            picker.directoryURL = URL(fileURLWithPath: "/Applications")
            picker.allowedContentTypes = [.applicationBundle]
        }
        return picker.runModal() == .OK ? picker.url : nil
    }
    static func fileBinding(_ url: URL) -> AppBinding? {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let isApplication = url.pathExtension.lowercased() == "app" && Bundle(url: url) != nil
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        return AppBinding(bundleIdentifier: isApplication ? Bundle(url: url)?.bundleIdentifier : nil,
            path: url.path, name: isApplication ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent,
            kind: isApplication ? .application : isDirectory ? .folder : .file)
    }
    func launch(_ code: UInt16, foregroundApplication: NSRunningApplication? = nil) {
        guard let binding = binding(for: code) else { return }
        guard let url = url(for: binding, refresh: true) else {
            errorMessage = "未找到或无法打开「\(binding.name)」。请检查目标或重新绑定。"; return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let completion: (NSRunningApplication?, Error?) -> Void = { [weak self] _, error in
            guard let error = error else { return }
            DispatchQueue.main.async { self?.errorMessage = "无法打开「\(binding.name)」：\(error.localizedDescription)" }
        }
        if binding.kind == .application {
            let front = foregroundApplication ?? NSWorkspace.shared.frontmostApplication
            if binding.toggleVisibility, let front = front, !front.isTerminated,
               front.bundleURL?.standardizedFileURL == url.standardizedFileURL {
                if !front.hide() { errorMessage = "无法隐藏「\(binding.name)」。" }
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
        } else if binding.kind == .website, binding.browserIdentifier != nil || binding.browserPath != nil {
            let browser = AppBinding(bundleIdentifier: binding.browserIdentifier, path: binding.browserPath ?? "", name: "浏览器")
            guard let browserURL = self.url(for: browser, refresh: true) else {
                errorMessage = "指定的浏览器未安装，请重新选择浏览器。"; return
            }
            NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: config, completionHandler: completion)
        } else if !NSWorkspace.shared.open(url) {
            errorMessage = "无法打开「\(binding.name)」，请检查文件权限或默认打开方式。"
        }
    }
}
