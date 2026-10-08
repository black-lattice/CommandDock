import Foundation

public struct KeyModifiers: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let option = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
}

/// Recognizes a short, isolated press of either Command key. Never consumes input.
public struct CommandTapRecognizer {
    public var maximumDuration: TimeInterval = 0.5
    private var pressedAt: TimeInterval?
    private var eligible = false
    private var commandWasDown = false
    private var heldKeys: Set<UInt16> = []
    private var heldMouseButtons: Set<Int> = []

    public init() {}

    public mutating func reset() {
        pressedAt = nil
        eligible = false
        commandWasDown = false
        heldKeys.removeAll()
        heldMouseButtons.removeAll()
    }

    public mutating func cancel() { eligible = false }
    public mutating func keyDown(_ code: UInt16) { heldKeys.insert(code); cancel() }
    public mutating func keyUp(_ code: UInt16) { heldKeys.remove(code) }
    public mutating func mouseDown(_ button: Int) { heldMouseButtons.insert(button); cancel() }
    public mutating func mouseUp(_ button: Int) { heldMouseButtons.remove(button) }

    public mutating func flagsChanged(keyCode: UInt16, modifiers: KeyModifiers, time: TimeInterval) -> Bool {
        let commandIsDown = modifiers.contains(.command)
        let isCommandKey = keyCode == 54 || keyCode == 55
        let hasOtherModifier = !modifiers.subtracting(.command).isEmpty
        defer { commandWasDown = commandIsDown }

        if commandIsDown && !commandWasDown {
            pressedAt = time
            eligible = isCommandKey && !hasOtherModifier && heldKeys.isEmpty && heldMouseButtons.isEmpty
            return false
        }
        if commandIsDown {
            // A second Command or any other modifier disqualifies this gesture.
            eligible = false
            return false
        }
        if commandWasDown {
            let duration = time - (pressedAt ?? time)
            let trigger = eligible && isCommandKey && !hasOtherModifier && duration >= 0 && duration <= maximumDuration
            pressedAt = nil
            eligible = false
            return trigger
        }
        return false
    }
}
