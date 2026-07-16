import Foundation
import Observation

final class PublishedStateObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func recordChange() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

@MainActor
func observePublishedState<Value>(
    _ value: @autoclosure () -> Value
) -> PublishedStateObservationProbe {
    let probe = PublishedStateObservationProbe()
    withObservationTracking {
        _ = value()
    } onChange: {
        probe.recordChange()
    }
    return probe
}
