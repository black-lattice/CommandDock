import SwiftUI
import CommandDockCore

struct TriggerSettingsView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        GroupBox("呼出方式") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("触发方式", selection: $store.triggerMode) {
                    ForEach(TriggerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if store.triggerMode == .shortcut {
                    HStack {
                        modifier("⌃ Control", .control)
                        modifier("⌥ Option", .option)
                        modifier("⇧ Shift", .shift)
                        modifier("⌘ Command", .command)
                    }
                    Picker("物理键位", selection: $store.customHotKey.code) {
                        ForEach(KeyboardLayout.bindable) { Text($0.label).tag($0.code) }
                    }
                    Text(store.customHotKey.isValid ? "当前快捷键：\(store.customHotKey.label)。请避开系统和其他应用已使用的组合。" : "至少选择 Control、Option 或 Command 中的一项。")
                        .font(.caption).foregroundColor(store.customHotKey.isValid ? .secondary : .red)
                } else if store.triggerMode == .doubleCommand {
                    Text("连续轻按同一侧 ⌘ 两次，两次松开间隔不超过 0.4 秒。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func modifier(_ title: String, _ flag: KeyModifiers) -> some View {
        Toggle(title, isOn: Binding(get: {
            KeyModifiers(rawValue: store.customHotKey.modifiers).contains(flag)
        }, set: { enabled in
            var flags = KeyModifiers(rawValue: store.customHotKey.modifiers)
            if enabled { flags.insert(flag) } else { flags.remove(flag) }
            store.customHotKey.modifiers = flags.rawValue
        }))
    }
}
