import SwiftUI
import CommandDockCore

struct KeyboardView: View {
    @ObservedObject var store: AppStore
    let launch: (UInt16) -> Void
    let dismiss: () -> Void
    private let gap: CGFloat = 6
    private func width(_ units: Double) -> CGFloat { CGFloat(units) * 60 + CGFloat(units - 1) * gap }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: gap) {
                Button(action: dismiss) { Text("esc").frame(width: 60, height: 28) }.buttonStyle(KeycapStyle())
                ForEach(1...12, id: \.self) { n in
                    Text("F\(n)").font(.system(size: 10)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(Color.primary.opacity(0.04)).cornerRadius(6)
                }
                Image(systemName: "touchid").foregroundColor(.secondary).frame(width: 52, height: 28)
            }
            VStack(spacing: gap) {
                ForEach(KeyboardLayout.rows.indices, id: \.self) { index in
                    HStack(spacing: gap) {
                        ForEach(KeyboardLayout.rows[index]) { key in
                            keycap(key)
                        }
                    }
                }
                HStack(spacing: gap) {
                    decorative("fn", 1)
                    decorative("control", 1)
                    decorative("option", 1)
                    decorative("⌘", 1.25, accent: true)
                    keycap(KeyboardKey(49, "space", width: 5.75), height: 50)
                    decorative("⌘", 1.25, accent: true)
                    decorative("option", 1)
                    HStack(spacing: 3) {
                        Text("◀").frame(maxWidth: .infinity)
                        VStack(spacing: 0) { Text("▲"); Text("▼") }.frame(maxWidth: .infinity)
                        Text("▶").frame(maxWidth: .infinity)
                    }.font(.system(size: 10)).foregroundColor(.secondary)
                        .frame(width: width(2.25), height: 50)
                        .background(Color.primary.opacity(0.04)).cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 999)
    }
    @ViewBuilder private func keycap(_ key: KeyboardKey, height: CGFloat = 66) -> some View {
        if KeyboardLayout.reserved.contains(key.code) {
            decorative(key.label, key.width, height: height)
        } else {
            let binding = store.binding(for: key.code)
            Button { if binding != nil { launch(key.code) } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.label).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(binding == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let binding = binding {
                        HStack { Spacer(); Image(nsImage: store.icon(for: binding)).resizable().frame(width: 26, height: 26); Spacer() }
                        Text(binding.name).font(.system(size: 9)).lineLimit(1).frame(maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 0)
                        Text("·").foregroundColor(.secondary).frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                }.padding(7).frame(width: width(key.width), height: height)
            }.buttonStyle(KeycapStyle(bound: binding != nil))
                .disabled(binding == nil)
                .help(binding.map { "\(key.label) · \($0.name)" } ?? "\(key.label) 尚未绑定，在设置中添加应用")
                .accessibilityLabel(binding.map { "\(key.label)，打开\($0.name)" } ?? "\(key.label)，未绑定")
        }
    }
    private func decorative(_ text: String, _ units: Double, height: CGFloat = 50, accent: Bool = false) -> some View {
        Text(text).font(.system(size: accent ? 21 : 10, weight: .medium))
            .foregroundColor(accent ? .mint : .secondary)
            .frame(width: width(units), height: height)
            .background(accent ? Color.mint.opacity(0.10) : Color.primary.opacity(0.035))
            .cornerRadius(8)
    }
}

private struct KeycapStyle: ButtonStyle {
    var bound = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.mint.opacity(0.22) : Color.primary.opacity(bound ? 0.085 : 0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(bound ? 0.12 : 0.045), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
