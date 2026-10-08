public enum OverlayKeyAction: Equatable {
    case passThrough
    case consume
    case dismissAndPassThrough
    case dismiss
    case launch(UInt16)
}

/// Ensures a swallowed keyDown has a swallowed keyUp, even after the overlay closes.
public struct OverlayKeyRouter {
    private var consumed: Set<UInt16> = []
    public init() {}
    public mutating func reset() { consumed.removeAll() }
    public mutating func keyUp(code: UInt16) -> OverlayKeyAction {
        consumed.remove(code) != nil ? .consume : .passThrough
    }
    public mutating func keyDown(code: UInt16, modifiers: KeyModifiers, visible: Bool, bound: Bool, repeatKey: Bool) -> OverlayKeyAction {
        if consumed.contains(code) { return .consume }
        guard visible else { return .passThrough }
        // All modifier shortcuts immediately return to the foreground application.
        guard modifiers.isEmpty else { return .dismissAndPassThrough }
        if code == 53 { consumed.insert(code); return .dismiss }
        guard KeyboardLayout.key(code: code) != nil else { return .dismissAndPassThrough }
        consumed.insert(code)
        return bound && !repeatKey ? .launch(code) : .consume
    }
}
