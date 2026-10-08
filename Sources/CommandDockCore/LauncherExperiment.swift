import Foundation

/// Aggregate, in-memory measurements only; no key codes or application names.
public struct LauncherExperiment {
    public private(set) var launchesBeforeHint = 0
    public private(set) var launchesAfterHint = 0
    public private(set) var cancellations = 0
    private var totalResponseTime: TimeInterval = 0
    public var launches: Int { launchesBeforeHint + launchesAfterHint }
    public var averageResponseTime: TimeInterval? {
        launches == 0 ? nil : totalResponseTime / Double(launches)
    }
    public init() {}

    public mutating func recordLaunch(beforeHint: Bool, responseTime: TimeInterval) {
        guard responseTime.isFinite, responseTime >= 0 else { return }
        if beforeHint { launchesBeforeHint += 1 } else { launchesAfterHint += 1 }
        totalResponseTime += responseTime
    }
    public mutating func recordCancellation() { cancellations += 1 }
}
