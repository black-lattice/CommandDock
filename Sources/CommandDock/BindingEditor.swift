import SwiftUI
import CommandDockCore

struct BindingEditor: View {
    @ObservedObject var store: AppStore
    let key: KeyboardKey
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppBinding
    @State private var validation: String?

    init(store: AppStore, key: KeyboardKey) {
        self.store = store; self.key = key
        _draft = State(initialValue: store.binding(for: key.code) ?? AppBinding(path: "", name: ""))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置 \(key.label) 键").font(.title2).fontWeight(.semibold)
            Form {
                Picker("类型", selection: $draft.kind) {
                    ForEach(BindingKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.onChange(of: draft.kind) { _ in
                    draft.path = ""; draft.bundleIdentifier = nil
                    draft.browserIdentifier = nil; draft.browserPath = nil
                    validation = nil
                }
                TextField("显示名称", text: $draft.name)
                if draft.kind == .application {
                    Toggle("已在前台时隐藏应用", isOn: $draft.toggleVisibility)
                    Text("开启后：后台时显示，前台时隐藏；未运行时正常启动。")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if draft.kind == .shortcut {
                    TextField("快捷指令名称", text: $draft.path, prompt: Text("与快捷指令 App 中的名称一致"))
                    Text("执行本机已有的快捷指令。改名或删除后需更新此处；运行结果及授权由快捷指令 App 显示。")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(width: 380, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开快捷指令 App") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else if draft.kind == .website {
                    TextField("网址", text: $draft.path, prompt: Text("https://example.com"))
                    HStack {
                        Text("浏览器")
                        Text(draft.browserPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "系统默认")
                            .foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Button("选择…") {
                            if let url = AppStore.chooseURL(kind: .application) {
                                draft.browserIdentifier = Bundle(url: url)?.bundleIdentifier
                                draft.browserPath = url.path
                            }
                        }
                        Button("默认") { draft.browserIdentifier = nil; draft.browserPath = nil }
                    }
                } else {
                    HStack {
                        Text(draft.path.isEmpty ? "尚未选择\(draft.kind.title)" : draft.path)
                            .foregroundColor(.secondary).lineLimit(2).truncationMode(.middle)
                        Spacer()
                        Button("选择\(draft.kind.title)…") {
                            if let url = AppStore.chooseURL(kind: draft.kind), let binding = AppStore.fileBinding(url) {
                                draft.path = binding.path; draft.bundleIdentifier = binding.bundleIdentifier
                                draft.name = binding.name
                                validation = nil
                            }
                        }
                    }
                }
            }
            if let validation = validation { Text(validation).font(.callout).foregroundColor(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540)
    }
    private func save() {
        if draft.kind == .website || draft.kind == .shortcut {
            draft.path = draft.path.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.kind == .shortcut {
            guard draft.shortcutURL != nil else { validation = "请输入快捷指令名称。"; return }
            if draft.name.isEmpty { draft.name = draft.path }
        } else if draft.kind == .website {
            guard let url = AppBinding.websiteURL(draft.path) else {
                validation = "请输入完整的 http:// 或 https:// 网址。"; return
            }
            draft.path = url.absoluteString
            if draft.name.isEmpty { draft.name = url.host ?? "网址" }
        } else {
            guard let selected = AppStore.fileBinding(URL(fileURLWithPath: draft.path)), selected.kind == draft.kind else {
                validation = "请选择有效的\(draft.kind.title)。"; return
            }
            if draft.name.isEmpty { draft.name = selected.name }
        }
        store.set(draft, for: key.code)
        dismiss()
    }
}
