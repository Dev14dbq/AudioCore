import Foundation
import Testing
@testable import AudioCore

@Suite("SharedStore")
struct SharedStoreTests {
    /// Each test gets a uniquely-named UserDefaults suite so tests can't see
    /// each other's writes and need no teardown.
    private func makeStore(notify: @escaping () -> Void = {}) -> SharedStore {
        let suiteName = "SharedStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SharedStore(defaults: defaults, notify: notify)
    }

    @Test func stateRoundTrips() {
        let store = makeStore()
        let state = AppVolumeState(gain: 0.75, isMuted: true)
        store.setState(state, for: "com.example.app")
        #expect(store.state(for: "com.example.app") == state)
    }

    @Test func stateDefaultsForUnknownBundleID() {
        let store = makeStore()
        #expect(store.state(for: "com.unknown.app") == .default)
    }

    @Test func setGainClampsAboveMax() {
        let store = makeStore()
        let result = store.setGain(2.0, for: "com.example.app")
        #expect(result.gain == 1.5)
    }

    @Test func setGainClampsBelowMin() {
        let store = makeStore()
        let result = store.setGain(-1.0, for: "com.example.app")
        #expect(result.gain == 0)
    }

    @Test func adjustGainClampsAtUpperBound() {
        let store = makeStore()
        store.setState(AppVolumeState(gain: 1.4, isMuted: false), for: "com.example.app")
        let result = store.adjustGain(by: 0.5, for: "com.example.app")
        #expect(result.gain == 1.5)
    }

    @Test func adjustGainClampsAtLowerBound() {
        let store = makeStore()
        store.setState(AppVolumeState(gain: 0.1, isMuted: false), for: "com.example.app")
        let result = store.adjustGain(by: -0.5, for: "com.example.app")
        #expect(result.gain == 0)
    }

    @Test func setMutedPersists() {
        let store = makeStore()
        let result = store.setMuted(true, for: "com.example.app")
        #expect(result.isMuted == true)
        #expect(store.state(for: "com.example.app").isMuted == true)
    }

    @Test func notifyInvokedExactlyOnceOnSetState() {
        let counter = Counter()
        let store = makeStore(notify: { counter.increment() })
        store.setState(.default, for: "com.example.app")
        #expect(counter.count == 1)
    }

    @Test func notifyInvokedExactlyOnceOnSetGain() {
        let counter = Counter()
        let store = makeStore(notify: { counter.increment() })
        store.setGain(0.5, for: "com.example.app")
        #expect(counter.count == 1)
    }

    @Test func notifyInvokedExactlyOnceOnSetMuted() {
        let counter = Counter()
        let store = makeStore(notify: { counter.increment() })
        store.setMuted(true, for: "com.example.app")
        #expect(counter.count == 1)
    }

    @Test func notifyInvokedExactlyOnceOnAdjustGain() {
        let counter = Counter()
        let store = makeStore(notify: { counter.increment() })
        store.adjustGain(by: 0.1, for: "com.example.app")
        #expect(counter.count == 1)
    }

    @Test func knownAppsRoundTrips() {
        let store = makeStore()
        let apps = [
            AudioAppInfo(bundleID: "com.example.a", name: "A"),
            AudioAppInfo(bundleID: "com.example.b", name: "B")
        ]
        store.knownApps = apps
        #expect(store.knownApps == apps)
    }
}

/// A plain reference-type counter for observing closure invocation count
/// from a `@Sendable`-inferred `notify: () -> Void` closure in tests.
private final class Counter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}
