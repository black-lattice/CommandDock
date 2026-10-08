public enum OverlayKeyAction: Equatable {
    case passThrough
    case consume
    case dismissAndPassThrough
    case dismiss
    case launch(UInt16)

    /// Both the Quartz and local AppKit paths use the same consumption decision.
    /// Launch closes the session in its handler, without restoring the old app.
    public func perform(dismiss: () -> Void, launch: (UInt16) -> Void) -> Bool {
        switch self {
        case .passThrough: return false
        case .consume: return true
        case .dismissAndPassThrough: dismiss(); return false
        case .dismiss: dismiss(); return true
        case .launch(let code): launch(code); return true
        }
    }
}

/// Ensures a swallowed keyDown has a swallowed keyUp, even after the overlay closes.
public struct OverlayKeyRouter {
    private var consumed: Set<UInt16> = []
    public init() {}
    public var hasConsumedKeys: Bool { !consumed.isEmpty }
    public mutating func reconcileHeldKeys(_ isDown: (UInt16) -> Bool) {
        consumed = consumed.filter(isDown)
    }
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
