import SwiftUI
import ServiceManagement
import CommandDockCore

struct SettingsView: View {
    @ObservedObject var store: AppStore
    let retryPermission: () -> Void
    let requestPermission: () -> Void
    let preview: () -> Void
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var resetConfirm = false

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "gearshape") }
            bindings.tabItem { Label("应用绑定", systemImage: "keyboard") }
        }.padding(20).frame(width: 680, height: 540)
        .alert("恢复默认绑定？", isPresented: $resetConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { store.installDefaults() }
        } message: { Text("这会替换当前绑定。建议先导出一份备份。") }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("轻按 Command，打开你的应用").font(.title2).fontWeight(.semibold)
            Text("单独按下并松开任意一侧 ⌘，浮窗会保持显示。按应用对应的物理按键或点击图标即可启动；Esc、再次单击 ⌘ 或点击外部关闭浮窗。")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(store.listenerReady ? "全局键盘监听已连接" : "全局键盘监听未连接",
                          systemImage: store.listenerReady ? "checkmark.circle.fill" : "lock.shield")
                        .foregroundColor(store.listenerReady ? .green : .orange)
                    Text(store.listenerReady ? "全局 Command 触发已就绪。仅识别按键与修饰键，不记录输入内容，不上传数据。" : "单击 Command 呼出需要辅助功能授权；手动打开的浮窗仍可使用键盘。点击「启用全局快捷键」，按系统提示允许 CommandDock。")
                        .font(.callout).foregroundColor(.secondary)
                    if !store.listenerMessage.isEmpty {
                        Text(store.listenerMessage).font(.caption).foregroundColor(.orange)
                    }
                    HStack {
                        Button("启用全局快捷键", action: requestPermission)
                        Button("重新连接", action: retryPermission)
                        Text("授权后关闭设置窗口再试 ⌘").font(.caption).foregroundColor(.secondary)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("暂停 Command 监听", isOn: $store.paused)
            Toggle("登录时自动启动", isOn: $loginEnabled)
                .onChange(of: loginEnabled) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许 CommandDock。" : nil
                    } catch {
                        loginError = "登录项设置失败：\(error.localizedDescription)"
                        loginEnabled = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError = loginError { Text(loginError).font(.caption).foregroundColor(.orange) }
            HStack {
                Text("单击最长按住时间")
                Slider(value: $store.tapDuration, in: 0.2...0.8, step: 0.1).frame(width: 160)
                Text(String(format: "%.1f 秒", store.tapDuration)).monospacedDigit()
            }
            Text("⌘C、⌘V、⌘Tab 等组合键保持原有功能。浮窗显示时按组合键会先收起浮窗。安全输入模式（例如密码框）可能暂时阻止全局监听。")
                .font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 0)
            HStack { Button("显示浮窗", action: preview); Spacer(); Text("CommandDock \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · 原生 macOS").font(.caption).foregroundColor(.secondary) }
        }.padding(16)
    }
    private var bindings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按 MacBook 键位绑定应用").font(.headline)
            Text("绑定使用物理键位，中文输入法下也能使用。切换电脑后会优先通过应用标识定位，无需保持相同安装路径。")
                .font(.caption).foregroundColor(.secondary)
            List(KeyboardLayout.bindable) { key in
                HStack(spacing: 12) {
                    Text(key.label).font(.system(.body, design: .monospaced)).frame(width: 46, alignment: .leading)
                    if let binding = store.binding(for: key.code) {
                        Image(nsImage: store.icon(for: binding)).resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.name)
                            Text(store.url(for: binding) == nil ? "此电脑未安装该应用" : binding.bundleIdentifier ?? binding.path)
                                .font(.caption2).foregroundColor(store.url(for: binding) == nil ? .orange : .secondary).lineLimit(1)
                        }
                    } else { Text("未绑定").foregroundColor(.secondary) }
                    Spacer()
                    Button("选择应用") { store.chooseApplication(for: key) }
                    Button { store.set(nil, for: key.code) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).disabled(store.binding(for: key.code) == nil).help("清除绑定")
                }.padding(.vertical, 3)
            }
            HStack {
                Button("导入绑定") { store.importBindings() }
                Button("导出绑定") { store.exportBindings() }
                Spacer()
                Button("恢复默认") { resetConfirm = true }
            }
        }.padding(16)
    }
}
