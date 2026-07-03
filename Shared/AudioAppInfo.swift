import Foundation

/// Identifies an app that AudioCore can control the volume of.
/// `bundleID` is the stable identity used as a storage key and as the
/// AppIntent parameter value, since PIDs change across launches.
struct AudioAppInfo: Codable, Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String

    var id: String { bundleID }
}

/// Persisted per-app state, shared between the main app and the Control
/// Center extension through the App Group defaults suite.
struct AppVolumeState: Codable, Hashable, Sendable {
    var gain: Double // 0.0...1.5, 1.0 = unchanged passthrough
    var isMuted: Bool

    static let `default` = AppVolumeState(gain: 1.0, isMuted: false)
}

/// Reads/writes per-app volume state in the App Group `UserDefaults` suite.
/// `defaults` and `notify` are injected (defaulting to the real App Group
/// suite and a real Darwin notification post) so tests can swap in an
/// isolated suite and a spy closure instead of touching global state.
struct SharedStore {
    // Same reasoning as `AppGroup.defaults`: the underlying `UserDefaults` is
    // thread-safe internally even though it isn't `Sendable` in the SDK, and
    // `notify` defaults to a stateless free function — safe to share statically.
    nonisolated(unsafe) static let shared = SharedStore()

    private let defaults: UserDefaults
    private let notify: () -> Void

    init(defaults: UserDefaults = AppGroup.defaults, notify: @escaping () -> Void = {
        DarwinNotification.post(DarwinNotification.volumeStateChanged)
    }) {
        self.defaults = defaults
        self.notify = notify
    }

    private static let knownAppsKey = "knownApps"
    private static func stateKey(_ bundleID: String) -> String { "volumeState.\(bundleID)" }

    /// Apps currently known to have (or recently had) an audio-capable process.
    /// The main app keeps this list fresh; the extension reads it to populate
    /// the AppIntent picker shown when the user configures a Control Center tile.
    var knownApps: [AudioAppInfo] {
        get {
            guard let data = defaults.data(forKey: Self.knownAppsKey),
                  let apps = try? JSONDecoder().decode([AudioAppInfo].self, from: data) else {
                return []
            }
            return apps
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.knownAppsKey)
        }
    }

    func state(for bundleID: String) -> AppVolumeState {
        guard let data = defaults.data(forKey: Self.stateKey(bundleID)),
              let state = try? JSONDecoder().decode(AppVolumeState.self, from: data) else {
            return .default
        }
        return state
    }

    @discardableResult
    func setState(_ state: AppVolumeState, for bundleID: String) -> AppVolumeState {
        guard let data = try? JSONEncoder().encode(state) else { return state }
        defaults.set(data, forKey: Self.stateKey(bundleID))
        // Force an immediate flush to disk: this app is usually stopped by
        // force-kill (Xcode Stop, `pkill`, log out) rather than a graceful
        // quit, and UserDefaults' normal lazy/periodic write-back can lose
        // the most recent change if we don't push it out right away.
        defaults.synchronize()
        notify()
        return state
    }

    /// Clamps to the valid gain range and persists in one step, centralizing
    /// logic that was previously duplicated across the main app and both
    /// Control Center intents.
    @discardableResult
    func setGain(_ gain: Double, for bundleID: String) -> AppVolumeState {
        var state = state(for: bundleID)
        state.gain = Self.clampGain(gain)
        return setState(state, for: bundleID)
    }

    @discardableResult
    func setMuted(_ muted: Bool, for bundleID: String) -> AppVolumeState {
        var state = state(for: bundleID)
        state.isMuted = muted
        return setState(state, for: bundleID)
    }

    @discardableResult
    func adjustGain(by delta: Double, for bundleID: String) -> AppVolumeState {
        var state = state(for: bundleID)
        state.gain = Self.clampGain(state.gain + delta)
        return setState(state, for: bundleID)
    }

    static func clampGain(_ gain: Double) -> Double { min(1.5, max(0, gain)) }
}

/// Static forwarding surface so call sites that only ever need the default,
/// App-Group-backed store (the widget extension's read-only lookups) can
/// keep using `SharedStore.xxx` without holding an instance themselves.
extension SharedStore {
    static var knownApps: [AudioAppInfo] {
        get { shared.knownApps }
        set { shared.knownApps = newValue }
    }

    static func state(for bundleID: String) -> AppVolumeState { shared.state(for: bundleID) }

    @discardableResult
    static func setState(_ state: AppVolumeState, for bundleID: String) -> AppVolumeState {
        shared.setState(state, for: bundleID)
    }
}
