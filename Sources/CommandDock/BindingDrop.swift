import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CommandDockCore

struct BindingDrop: DropDelegate {
    static let keyType = UTType.utf8PlainText.identifier
    static let types = [UTType.fileURL.identifier, UTType.url.identifier, keyType]
    let store: AppStore
    let code: UInt16
    @Binding var targeted: UInt16?

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: Self.types)
    }
    func dropEntered(info: DropInfo) { targeted = code }
    func dropExited(info: DropInfo) { if targeted == code { targeted = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // SwiftUI's macOS source advertises copy; swapping is handled atomically by the store.
        DropProposal(operation: .copy)
    }
    func performDrop(info: DropInfo) -> Bool {
        targeted = nil
        let urlProvider = info.itemProviders(for: [UTType.fileURL.identifier, UTType.url.identifier]).first
        if let provider = info.itemProviders(for: [Self.keyType]).first {
            provider.loadDataRepresentation(forTypeIdentifier: Self.keyType) { data, _ in
                DispatchQueue.main.async {
                    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    if let source = BindingDragPayload.decode(text) { store.swapBindings(source, code) }
                    else if let urlProvider = urlProvider { loadURL(urlProvider) }
                    else { bind(AppBinding.websiteURL(text)) }
                }
            }
            return true
        }
        guard let provider = urlProvider else { return false }
        loadURL(provider)
        return true
    }
    private func loadURL(_ provider: NSItemProvider) {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL.identifier : UTType.url.identifier
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let value = item as? URL { url = value }
            else if let value = item as? String { url = URL(string: value) }
            else { url = nil }
            DispatchQueue.main.async { bind(url) }
        }
    }
    private func bind(_ url: URL?) {
        guard let url = url else { store.errorMessage = "请拖入应用、文件、文件夹或 http/https 网址。"; return }
        if let binding = AppStore.fileBinding(url) { store.set(binding, for: code) }
        else if let website = AppBinding.websiteURL(url.absoluteString) {
            store.set(AppBinding(path: website.absoluteString, name: website.host ?? "网址", kind: .website), for: code)
        } else { store.errorMessage = "无法打开拖入的目标，请检查文件是否存在或网址是否正确。" }
    }
    static func provider(for code: UInt16, bound: Bool) -> NSItemProvider {
        // NSString advertises a system-recognized pasteboard type on macOS.
        return bound ? NSItemProvider(object: BindingDragPayload.encode(code) as NSString) : NSItemProvider()
    }
}
