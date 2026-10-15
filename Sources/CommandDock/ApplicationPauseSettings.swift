import SwiftUI
import CommandDockCore

struct PausedApplication: Codable, Equatable, Identifiable {
    var bundleIdentifier: String?
    var path: String
    var name: String
    var id: String { bundleIdentifier ?? path }
    func matches(identifier: String?, path: String?) -> Bool {
        if let expected = bundleIdentifier { return identifier == expected }
        return self.path == path
    }
}

struct ApplicationPauseSettings: View {
    @ObservedObject var store: AppStore
    var body: some View {
        GroupBox("指定应用内暂停触发") {
            VStack(alignment: .leading, spacing: 10) {
                Text("列表中的应用位于前台时，自动暂停全局呼出；切换到其他应用后恢复。菜单栏仍可手动显示浮窗。")
                    .font(.caption).foregroundColor(.secondary)
                if let name = store.autoPausedAppName {
                    Label("当前因「\(name)」暂停触发", systemImage: "pause.circle")
                        .font(.callout).foregroundColor(.orange)
                }
                if !store.pausedApplications.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.pausedApplications) { app in
                                HStack {
                                    Text(app.name).lineLimit(1)
                                    Spacer()
                                    Button("移除") { store.pausedApplications.removeAll { $0.id == app.id } }
                                        .accessibilityLabel("移除 \(app.name) 的暂停规则")
                                }
                            }
                        }
                    }.frame(maxHeight: 120)
                }
                Button("添加应用…") {
                    guard let url = AppStore.chooseURL(kind: .application),
                          let binding = AppStore.fileBinding(url), binding.kind == .application else { return }
                    let app = PausedApplication(bundleIdentifier: binding.bundleIdentifier, path: binding.path, name: binding.name)
                    if !store.pausedApplications.contains(where: { $0.id == app.id }) { store.pausedApplications.append(app) }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
