import Foundation

/// Input becomes active immediately; only the visual hint is delayed.
/// Tokens prevent a cancelled or replaced presentation from opening later.
public struct LauncherSession {
    public enum Phase: Equatable { case idle, waiting, visible }
    public private(set) var phase: Phase = .idle
    private var generation: UInt64 = 0
    public var isActive: Bool { phase != .idle }
    public init() {}

    @discardableResult public mutating func begin() -> UInt64 {
        generation &+= 1
        phase = .waiting
        return generation
    }

    @discardableResult public mutating func reveal(token: UInt64) -> Bool {
        guard token == generation, phase == .waiting else { return false }
        phase = .visible
        return true
    }

    public var presentationToken: UInt64 { generation }

    public mutating func end() {
        generation &+= 1
        phase = .idle
    }
}

/// Do not reactivate an old app after the user has switched to another one.
public enum LauncherFocusPolicy {
    public static func shouldRestore(previous: Int32?, current: Int32?, launcher: Int32) -> Bool {
        guard let previous = previous, previous != launcher else { return false }
        return current == previous || current == launcher
    }
}
