import Combine
import Foundation

/// Central coordinator: discovers audio-capable apps, keeps the shared
/// `AudioMixerEngine` in sync with which apps should have a live tap and at
/// what gain, persists desired volume/mute state to the App Group so the
/// Control Center extension can read/write it, and reacts to changes the
/// extension makes via a Darwin notification.
@MainActor
final class VolumeManager: ObservableObject {
    @Published private(set) var apps: [AudioAppInfo] = []
    @Published private(set) var states: [String: AppVolumeState] = [:]
    /// Set when the render callback has noticed a tapped app going silent for
    /// far longer than is plausible for real audio — see
    /// `AggregateMixerDevice.permissionWarningDetected`. Surfaced in the UI so
    /// a missing/revoked System Audio Recording permission doesn't look like
    /// silent, unexplained breakage.
    @Published private(set) var needsAudioCapturePermission = false

    private let store: SharedStore
    private let mixer: AudioMixing

    private var refreshTimer: Timer?
    private var darwinToken: DarwinObserverToken?

    /// `startTimer`/`observeDarwinNotifications` default to real production
    /// behavior; tests disable both to avoid a live 3-second polling loop and
    /// a real Darwin notification center registration firing during
    /// construction.
    init(
        store: SharedStore = .shared,
        mixer: AudioMixing = AudioMixerEngine.shared,
        launchAtLogin: LaunchAtLoginRegistering = LaunchAtLoginService.shared,
        startTimer: Bool = true,
        observeDarwinNotifications: Bool = true
    ) {
        self.store = store
        self.mixer = mixer

        launchAtLogin.registerIfNeeded()
        // Trigger the system's audio-capture consent prompt as early as
        // possible (fresh installs would otherwise only see it the first
        // time a slider is touched, with no sound and no explanation in the
        // meantime).
        mixer.primeAudioCapturePermission()

        if observeDarwinNotifications {
            darwinToken = DarwinNotification.observe(DarwinNotification.volumeStateChanged) { [weak self] in
                Task { @MainActor in self?.reloadStatesFromDisk() }
            }
        }

        refresh()

        if startTimer {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// Re-scans which apps currently have an audio-capable process. Polling
    /// is simple and cheap (CoreAudio has no "process started making sound"
    /// notification), so a menu bar app can afford to do this every few seconds.
    func refresh() {
        let discovered = ProcessTapRegistry.controllableApps()
        apps = discovered
        store.knownApps = discovered

        for app in discovered where states[app.bundleID] == nil {
            // Loads whatever was last saved for this app (e.g. from a
            // previous run, or before it was relaunched), so volume choices
            // survive the target app being quit and reopened.
            states[app.bundleID] = store.state(for: app.bundleID)
        }

        syncMixer()
        needsAudioCapturePermission = mixer.permissionWarningDetected
    }

    func setGain(_ gain: Double, for bundleID: String) {
        states[bundleID] = store.setGain(gain, for: bundleID)
        syncMixer()
    }

    func setMuted(_ muted: Bool, for bundleID: String) {
        states[bundleID] = store.setMuted(muted, for: bundleID)
        syncMixer()
    }

    func adjustVolume(by delta: Double, for bundleID: String) {
        states[bundleID] = store.adjustGain(by: delta, for: bundleID)
        syncMixer()
    }

    /// Picks up state written by the Control Center extension (a separate
    /// process/sandbox) since our own @Published state can't observe its writes.
    private func reloadStatesFromDisk() {
        for app in apps {
            states[app.bundleID] = store.state(for: app.bundleID)
        }
        syncMixer()
    }

    /// Only apps whose volume/mute the user has actually touched (state
    /// differs from `.default`) get a live Core Audio tap. Everything else
    /// keeps playing through its normal, untouched path. Tapping *every*
    /// app the moment it makes any sound at all — the previous behavior —
    /// meant a single bug in the capture/mix pipeline could silence
    /// everything on the system the instant AudioCore was running, even for
    /// apps nobody asked it to touch.
    private func syncMixer() {
        let active = states.filter { $0.value != .default }
        mixer.sync(activeBundleIDs: Set(active.keys)) { [states] bundleID in
            let state = states[bundleID] ?? .default
            return (Float(state.gain), state.isMuted)
        }
        // `sync` only applies gain/mute to apps it *newly* taps; for an app
        // that already has a live tap it early-outs without touching the
        // channel. So every ongoing slider/mute change to an already-active
        // app must be pushed into the render callback explicitly here, or it
        // would never take effect.
        for (bundleID, state) in active {
            mixer.setGain(Float(state.gain), isMuted: state.isMuted, for: bundleID)
        }
    }
}
