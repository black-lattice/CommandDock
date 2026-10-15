import Foundation

public enum BindingDragPayload {
    private static let prefix = "CommandDock key "
    public static func encode(_ code: UInt16) -> String { prefix + String(code) }
    public static func decode(_ text: String) -> UInt16? {
        guard text.hasPrefix(prefix), let code = UInt16(text.dropFirst(prefix.count)),
              KeyboardLayout.key(code: code) != nil else { return nil }
        return code
    }
}
