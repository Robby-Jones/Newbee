import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A single reading of every clock the session engine cares about.
public struct Instant: Sendable, Hashable {
    /// Wall-clock time. The persisted source of truth.
    public var wall: Date
    /// Seconds on a continuous clock that keeps counting during sleep but resets on reboot.
    /// `nil` when unavailable.
    public var monotonic: Double?
    /// Identifies the current boot, so monotonic readings are only compared within one boot.
    public var bootID: String?

    public init(wall: Date, monotonic: Double? = nil, bootID: String? = nil) {
        self.wall = wall
        self.monotonic = monotonic
        self.bootID = bootID
    }
}

/// Clock abstraction so all timing logic can be unit tested deterministically.
public protocol AppClock: Sendable {
    func instant() -> Instant
}

extension AppClock {
    public var now: Date { instant().wall }
}

/// The real clock.
public struct SystemClock: AppClock {
    public init() {}

    public func instant() -> Instant {
        Instant(wall: Date(), monotonic: Self.monotonicSeconds(), bootID: Self.bootID)
    }

    /// Continuous time since boot, including sleep.
    /// On Darwin `CLOCK_MONOTONIC` includes sleep; on Linux that is `CLOCK_BOOTTIME`.
    /// To verify on device in Phase 5 (docs/TIMER_ENGINE.md §8).
    static func monotonicSeconds() -> Double? {
        #if canImport(Darwin)
        return Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
        #elseif os(Linux)
        var ts = timespec()
        guard clock_gettime(CLOCK_BOOTTIME, &ts) == 0 else { return nil }
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000
        #else
        return nil
        #endif
    }

    /// Identifies the current boot, stable for the life of one boot.
    ///
    /// Darwin: `kern.bootsessionuuid`, a per-boot UUID that does not depend on the wall clock.
    /// (`kern.boottime` is only a fallback: XNU moves it when the clock is set, so after a clock
    /// change and relaunch it would look like a reboot and hide the change. To verify on device:
    /// TESTING.md D12b.)
    static let bootID: String? = {
        #if canImport(Darwin)
        var size = 0
        if sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 {
                let uuid = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                if !uuid.isEmpty { return uuid }
            }
        }
        var tv = timeval()
        var tvSize = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &tvSize, nil, 0) == 0 else { return nil }
        return "boottime-\(tv.tv_sec)"
        #else
        guard let id = try? String(contentsOfFile: "/proc/sys/kernel/random/boot_id", encoding: .utf8) else { return nil }
        return id.trimmingCharacters(in: .whitespacesAndNewlines)
        #endif
    }()
}

/// A controllable clock for tests. Simulates time passing, wall-clock changes and reboots.
public final class TestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var wall: Date
    private var monotonic: Double
    private var bootCount: Int

    public init(wall: Date = Date(timeIntervalSince1970: 1_800_000_000), monotonic: Double = 1_000) {
        self.wall = wall
        self.monotonic = monotonic
        self.bootCount = 1
    }

    public func instant() -> Instant {
        lock.withLock { Instant(wall: wall, monotonic: monotonic, bootID: "boot-\(bootCount)") }
    }

    /// Real time passes: wall and monotonic clocks both advance.
    public func advance(by seconds: TimeInterval) {
        lock.withLock {
            wall = wall.addingTimeInterval(seconds)
            monotonic += seconds
        }
    }

    /// The user changes the device clock: only wall time moves.
    public func jumpWall(by seconds: TimeInterval) {
        lock.withLock { wall = wall.addingTimeInterval(seconds) }
    }

    /// Sets wall time directly (only wall time moves).
    public func setWall(_ date: Date) {
        lock.withLock { wall = date }
    }

    /// The device restarts: monotonic resets and a new boot ID is issued.
    public func reboot(downtime seconds: TimeInterval = 60) {
        lock.withLock {
            wall = wall.addingTimeInterval(seconds)
            monotonic = 10
            bootCount += 1
        }
    }
}
