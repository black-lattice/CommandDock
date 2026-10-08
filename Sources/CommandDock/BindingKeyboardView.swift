import SwiftUI
import CommandDockCore

struct BindingKeyboardView: View {
    @ObservedObject var store: AppStore
    @State private var hoveredKey: UInt16?
    @State private var removalKey: KeyboardKey?
    @State private var confirmRemoval = false
    private let gap: CGFloat = 6
    private func width(_ units: Double) -> CGFloat { CGFloat(units) * 60 + CGFloat(units - 1) * gap }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: gap) {
                ForEach(KeyboardLayout.rows.indices, id: \.self) { index in
                    HStack(spacing: gap) {
                        ForEach(KeyboardLayout.rows[index]) { key in
                            if KeyboardLayout.reserved.contains(key.code) {
                                decorative(key.label, units: key.width, height: 66)
                            } else {
                                keycap(key)
                            }
                        }
                    }
                }
                HStack(spacing: gap) {
                    decorative("fn", units: 1)
                    decorative("control", units: 1)
                    decorative("option", units: 1)
                    decorative("⌘", units: 1.25)
                    keycap(KeyboardKey(49, "space", width: 5.75), height: 50)
                    decorative("⌘", units: 1.25)
                    decorative("option", units: 1)
                    decorative("←  ↑↓  →", units: 2.25)
                }
            }
        }.frame(maxWidth: .infinity)
        .alert("清除绑定？", isPresented: $confirmRemoval, presenting: removalKey) { key in
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { store.set(nil, for: key.code) }
        } message: { key in
            Text("确定清除「\(key.label)」键的应用绑定吗？")
        }
    }

    private func keycap(_ key: KeyboardKey, height: CGFloat = 66) -> some View {
        let binding = store.binding(for: key.code)
        let hovered = hoveredKey == key.code
        let missing = binding.map { store.url(for: $0) == nil } ?? false
        return ZStack(alignment: .topTrailing) {
            Button {
                store.chooseApplication(for: key)
            } label: {
                VStack(spacing: 2) {
                    Text(key.label).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let binding = binding {
                        Image(nsImage: store.icon(for: binding)).resizable().frame(width: 26, height: 26)
                        Text(binding.name).font(.system(size: 9)).lineLimit(1)
                            .foregroundColor(missing ? .orange : .primary)
                    } else {
                        Spacer(minLength: 0)
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.04), in: Circle())
                        Spacer(minLength: 0)
                    }
                }.padding(7).frame(width: width(key.width), height: height)
            }
            .buttonStyle(BindingKeyStyle(hovered: hovered, bound: binding != nil))
            .help(binding.map { "\(key.label) → \($0.name)\n\(missing ? "此电脑未安装该应用" : $0.bundleIdentifier ?? $0.path)" } ?? "点击为 \(key.label) 选择应用")
            .accessibilityLabel(binding.map { "\(key.label)，已绑定\($0.name)，点击更换应用" } ?? "\(key.label)，未绑定，点击选择应用")
            if binding != nil {
                Button {
                    removalKey = key
                    confirmRemoval = true
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                }
                .buttonStyle(.plain).padding(3)
                .opacity(hovered ? 1 : 0)
                .disabled(!hovered)
                .accessibilityHidden(!hovered)
                .help("清除 \(key.label) 的绑定")
                .accessibilityLabel("清除 \(key.label) 的绑定")
            }
        }
        .onHover { inside in
            if inside { hoveredKey = key.code }
            else if hoveredKey == key.code { hoveredKey = nil }
        }
    }

    private func decorative(_ label: String, units: Double, height: CGFloat = 50) -> some View {
        Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            .frame(width: width(units), height: height)
            .background(Color.primary.opacity(0.025)).cornerRadius(8)
    }
}

private struct BindingKeyStyle: ButtonStyle {
    let hovered: Bool
    let bound: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovered || configuration.isPressed ? Color.accentColor.opacity(0.12) : Color.primary.opacity(bound ? 0.065 : 0.025))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hovered ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: hovered ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
