import Foundation

public enum TriggerMode: String, Codable, CaseIterable {
    case eitherCommand, leftCommand, rightCommand, doubleCommand, shortcut
    public var title: String {
        switch self {
        case .eitherCommand: return "单击任意 ⌘"
        case .leftCommand: return "仅单击左 ⌘"
        case .rightCommand: return "仅单击右 ⌘"
        case .doubleCommand: return "双击 ⌘"
        case .shortcut: return "自定义快捷键"
        }
    }
}

public struct CustomHotKey: Codable, Equatable {
    public var code: UInt16
    public var modifiers: UInt
    public init(code: UInt16 = 49, modifiers: UInt = KeyModifiers.control.union(.option).rawValue) {
        self.code = code; self.modifiers = modifiers
    }
    public var isValid: Bool {
        let flags = KeyModifiers(rawValue: modifiers)
        return KeyboardLayout.key(code: code) != nil && !flags.intersection([.command, .control, .option]).isEmpty
            && flags.subtracting([.command, .control, .option, .shift]).isEmpty
    }
    public func matches(code: UInt16, modifiers: KeyModifiers) -> Bool {
        isValid && self.code == code && self.modifiers == modifiers.rawValue
    }
    public var label: String {
        let flags = KeyModifiers(rawValue: modifiers)
        return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            + (KeyboardLayout.key(code: code)?.label ?? "?")
    }
}

/// Filters already isolated Command taps; interrupted double taps never combine.
public struct TriggerMatcher {
    private var lastTap: (code: UInt16, time: TimeInterval)?
    public init() {}
    public mutating func reset() { lastTap = nil }
    public mutating func acceptTap(code: UInt16, time: TimeInterval, mode: TriggerMode) -> Bool {
        switch mode {
        case .eitherCommand: return true
        case .leftCommand: return code == 55
        case .rightCommand: return code == 54
        case .shortcut: return false
        case .doubleCommand:
            if let last = lastTap, last.code == code, time >= last.time, time - last.time <= 0.4 {
                lastTap = nil
                return true
            }
            lastTap = (code, time)
            return false
        }
    }
}
