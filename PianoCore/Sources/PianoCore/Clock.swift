import Foundation
import Dispatch

/// Monotonic time in seconds. Injected so lesson-state tests can control time.
public protocol MonotonicClock: AnyObject {
    var now: TimeInterval { get }
}

/// Uptime-based clock (mach absolute time on Apple platforms). Not affected by wall-clock
/// changes, and on iOS it shares a base with `AVAudioTime.seconds(forHostTime:)`.
public final class SystemMonotonicClock: MonotonicClock {
    public init() {}
    public var now: TimeInterval { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
}

/// Test clock.
public final class ManualClock: MonotonicClock {
    public var now: TimeInterval
    public init(now: TimeInterval = 1000) { self.now = now }
    public func advance(by seconds: TimeInterval) { now += seconds }
}
