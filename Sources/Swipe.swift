import Foundation

// A trackpad gesture and its inertial tail are one operation.
struct ReelSwipeGate {
    private var sum = 0.0
    private var fired = false
    private var wheelUntil = -Double.infinity
    mutating func reset() { sum = 0; fired = false; wheelUntil = -Double.infinity }
    mutating func step(delta: Double, began: Bool, ended: Bool, momentum: Bool, phased: Bool, time: Double) -> Int? {
        if momentum { return nil }
        if began { sum = 0; fired = false }
        if !phased && time > wheelUntil { sum = 0; fired = false }
        if !phased { wheelUntil = time + 0.3 }
        defer { if ended { sum = 0 } }
        guard !fired else { return nil }
        sum += delta
        guard abs(sum) >= 35 else { return nil }
        fired = true
        return sum < 0 ? 1 : -1
    }
}
