import CoreAudio
import Foundation
import os

enum ProcessTapError: LocalizedError {
    case noOutputDevice
    case tapCreationFailed
    case aggregateCreationFailed
    case ioProcCreationFailed

    var errorDescription: String? {
        switch self {
        case .noOutputDevice: return "No default output device is available."
        case .tapCreationFailed: return "Failed to create a Core Audio process tap."
        case .aggregateCreationFailed: return "Failed to create the shared aggregate playback device."
        case .ioProcCreationFailed: return "Failed to install the audio IO callback."
        }
    }
}

/// Coordinates *which* apps have a live tap and at what gain/mute state,
/// delegating the actual aggregate-device lifecycle to `AggregateMixerDevice`
/// and the sample math to `MixerRenderMath`.
///
/// Every physical output device can only be driven by one exclusive I/O
/// client at a time. Earlier this app created one private aggregate device
/// *per tapped app*, and each one claimed the same physical output device as
/// its main sub-device — running several of those simultaneously corrupts
/// the real output's timing (CoreAudio logs "skipping cycle due to
/// overload" / "out of order message" and audio breaks entirely).
///
/// The fix: exactly one aggregate device combines the real output device
/// with every currently-active app's tap as a subtap. One IO callback reads
/// all of the tapped streams, scales each by its own gain/mute state, sums
/// them, and writes the mix to the single real output.
final class AudioMixerEngine: @unchecked Sendable {
    static let shared = AudioMixerEngine()

    private var channels: [String: TapChannel] = [:]
    /// Order channels were last handed to the aggregate device, in list order —
    /// CoreAudio aggregate devices present one `AudioBuffer` per constituent
    /// sub-stream in composition order, so this is how the render callback
    /// maps `inputData` buffers back to the app that owns each one.
    private var channelOrder: [String] = []
    private let lock = NSLock()
    private let log = Logger(subsystem: "com.audiocore.app", category: "AudioMixerEngine")

    /// The render callback runs on Core Audio's real-time I/O thread, where it
    /// must never block on a lock the control thread might hold (during `sync`
    /// that lock is held across slow `makeProcessTap` calls, which would stall
    /// the audio thread and cause "skipping cycle due to overload") and must
    /// never allocate. So instead of letting the render thread reach into
    /// `channels`/`channelOrder` under `lock`, the control thread precomputes
    /// an immutable snapshot and publishes it under a dedicated, always-brief
    /// unfair lock; the render thread reads it with a *non-blocking* trylock
    /// and falls back to the last value it saw. Heap-allocated so its address
    /// is stable (required by `os_unfair_lock`).
    private let renderLock: UnsafeMutablePointer<os_unfair_lock>
    /// Guarded by `renderLock`; written by the control thread only.
    private var publishedSnapshot: [MixerRenderMath.ChannelInput] = []
    /// Touched only on the render thread; the value reused when `trylock` fails.
    private var cachedSnapshot: [MixerRenderMath.ChannelInput] = []

    private lazy var aggregateMixerDevice = AggregateMixerDevice { [weak self] in
        self?.channelSnapshot() ?? []
    }

    private init() {
        renderLock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        renderLock.initialize(to: os_unfair_lock())
    }

    /// True once the render callback has observed several consecutive silent
    /// cycles from a channel CoreAudio itself reports as actively outputting
    /// audio — see `AggregateMixerDevice.permissionWarningDetected` for why
    /// that's a reasonably reliable (if heuristic) signal that the system
    /// audio recording permission was never granted or got revoked.
    var permissionWarningDetected: Bool { aggregateMixerDevice.permissionWarningDetected }

    /// Fires the system's "AudioCore would like to record system audio" TCC
    /// prompt as early as possible (app launch) instead of waiting for the
    /// user to first touch a slider. Uses a global tap with `.unmuted`
    /// behavior — audio keeps playing normally through it, so unlike the
    /// per-app taps this never silences anything even before permission is
    /// granted; it exists purely to trigger the OS dialog. Fire-and-forget:
    /// the tap is destroyed immediately after creation.
    func primeAudioCapturePermission() {
        DispatchQueue.global(qos: .utility).async { [log] in
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "AudioCore Permission Probe"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            do {
                guard let tap = try AudioHardwareSystem.shared.makeProcessTap(description: description) else { return }
                try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            } catch {
                log.error("Permission probe tap failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setGain(_ gain: Float, isMuted: Bool, for bundleID: String) {
        lock.lock()
        channels[bundleID]?.gain = gain
        channels[bundleID]?.isMuted = isMuted
        publishRenderSnapshot()
        lock.unlock()
    }

    /// Reconciles which apps currently have a live tap against the given set
    /// of bundle IDs the registry reports as audio-capable right now, then
    /// rebuilds the single shared aggregate device if the tap set changed.
    /// `initialState` supplies the starting gain/mute for newly-added apps.
    func sync(activeBundleIDs: Set<String>, initialState: (String) -> (gain: Float, isMuted: Bool)) {
        lock.lock()
        let currentIDs = Set(channels.keys)

        for bundleID in currentIDs.subtracting(activeBundleIDs) {
            if let channel = channels.removeValue(forKey: bundleID) {
                try? AudioHardwareSystem.shared.destroyProcessTap(channel.tap)
            }
        }

        // Query CoreAudio's live process list once per sync call (not once
        // per newly-active bundle ID) and group it up front — this used to
        // re-run the full process query from scratch for every new app.
        let newlyActive = activeBundleIDs.subtracting(currentIDs)
        let processIDsByBundleID = newlyActive.isEmpty
            ? [:]
            : ProcessTapRegistry.processObjectIDsByBundleID(ProcessTapRegistry.audioCapableProcesses())

        for bundleID in newlyActive {
            guard let processIDs = processIDsByBundleID[bundleID], !processIDs.isEmpty else { continue }

            let description = CATapDescription(stereoMixdownOfProcesses: processIDs)
            description.name = "AudioCore Tap – \(bundleID)"
            description.isPrivate = true
            description.muteBehavior = .muted

            let tap: AudioHardwareTap
            do {
                guard let created = try AudioHardwareSystem.shared.makeProcessTap(description: description) else {
                    log.error("makeProcessTap returned nil for \(bundleID, privacy: .public)")
                    continue
                }
                tap = created
            } catch {
                log.error("Failed to create tap for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            let (gain, isMuted) = initialState(bundleID)
            channels[bundleID] = TapChannel(bundleID: bundleID, tap: tap, gain: gain, isMuted: isMuted)
        }

        let changed = Set(channels.keys) != Set(channelOrder)
        channelOrder = Array(channels.keys)
        let taps = channelOrder.compactMap { channels[$0]?.tap }
        publishRenderSnapshot()
        lock.unlock()

        guard changed else { return }

        if !taps.isEmpty && !aggregateMixerDevice.rebuild(with: taps) {
            // The tap(s) we just created already muted their app's audio at
            // the source (CATapMuteBehavior.muted). If the aggregate device
            // that's supposed to play it back never comes up, that app would
            // stay silent forever with no way to notice. Tear everything back
            // down immediately so the app's audio falls back to playing
            // normally instead of going silent for no visible reason.
            log.error("Aggregate mixer failed to start — reverting, tapped apps will play untouched")
            lock.lock()
            let allTaps = channels.values.map(\.tap)
            channels.removeAll()
            channelOrder.removeAll()
            publishRenderSnapshot()
            lock.unlock()
            for tap in allTaps {
                try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            }
        } else if taps.isEmpty {
            aggregateMixerDevice.rebuild(with: [])
        }
    }

    func stopAll() {
        lock.lock()
        let allTaps = channels.values.map(\.tap)
        channels.removeAll()
        channelOrder.removeAll()
        publishRenderSnapshot()
        lock.unlock()

        aggregateMixerDevice.rebuild(with: [])
        for tap in allTaps {
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
        }
    }

    /// Rebuilds the immutable render snapshot from the current channel state
    /// and publishes it for the render thread. Must be called with `lock`
    /// held (it reads `channels`/`channelOrder`); the `renderLock` section is
    /// intentionally tiny — just swapping one array reference — so the render
    /// thread's `trylock` almost never has to fall back.
    private func publishRenderSnapshot() {
        let snapshot: [MixerRenderMath.ChannelInput] = channelOrder.enumerated().compactMap { index, bundleID in
            guard let channel = channels[bundleID] else { return nil }
            return MixerRenderMath.ChannelInput(bufferIndex: index, gain: channel.gain, isMuted: channel.isMuted)
        }
        os_unfair_lock_lock(renderLock)
        publishedSnapshot = snapshot
        os_unfair_lock_unlock(renderLock)
    }

    /// Handed to the render callback and called synchronously on the real-time
    /// Core Audio I/O thread. Never blocks (non-blocking `trylock`) and never
    /// allocates a new collection: on success it re-seats `cachedSnapshot` to
    /// the already-built published array (a retain, not a copy); on contention
    /// it reuses the previous value. See `renderLock` for the full rationale.
    private func channelSnapshot() -> [MixerRenderMath.ChannelInput] {
        if os_unfair_lock_trylock(renderLock) {
            cachedSnapshot = publishedSnapshot
            os_unfair_lock_unlock(renderLock)
        }
        return cachedSnapshot
    }
}

extension AudioMixerEngine: AudioMixing {}
