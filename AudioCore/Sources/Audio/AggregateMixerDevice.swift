import CoreAudio
import Foundation
import os

/// Owns the shared aggregate device + IO callback that mixes every active
/// tap's audio into the real output device. See `AudioMixerEngine` for why
/// there is exactly one of these for the whole app rather than one per
/// tapped app.
final class AggregateMixerDevice {
    private var aggregateDevice: AudioHardwareAggregateDevice?
    private var ioProcID: AudioDeviceIOProcID?
    private var didLogFormat = false
    private let log = Logger(subsystem: "com.audiocore.app", category: "AggregateMixerDevice")

    /// Supplies the current channel list for the render callback. Called
    /// synchronously on the real-time Core Audio I/O thread, so the closure
    /// must return quickly and must not suspend — the owner is expected to
    /// do a fast lock/snapshot/unlock internally, matching the shape of the
    /// locking this replaces.
    private let channelsProvider: () -> [MixerRenderMath.ChannelInput]

    /// Consecutive-silent-render-cycle count per `bufferIndex`, touched only
    /// on the render thread. Resized (control thread) in `rebuild`/`tearDown`.
    /// See `trackSilence` for why a long streak indicates a likely-missing
    /// system audio recording permission.
    private var silentStreaks: [Int] = []
    private static let silentStreakThreshold = 250 // ~ a few seconds at typical buffer sizes; heuristic.

    /// Guards `permissionWarningFlag`. The render thread only ever
    /// `trylock`s it (never blocks); readers off the render thread (the
    /// control thread polling `permissionWarningDetected`) may block briefly,
    /// which is fine since they're never real-time.
    private let permissionLock: UnsafeMutablePointer<os_unfair_lock>
    private var permissionWarningFlag = false

    init(channelsProvider: @escaping () -> [MixerRenderMath.ChannelInput]) {
        self.channelsProvider = channelsProvider
        permissionLock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        permissionLock.initialize(to: os_unfair_lock())
    }

    /// Best-effort signal that system audio recording permission is missing
    /// or was revoked: a tapped app CoreAudio reports as actively outputting
    /// audio (that's the only reason it has a live tap — see
    /// `AudioMixerEngine.sync`) has rendered nothing but silence for a
    /// sustained stretch. There's no public API to check this permission
    /// directly, so this heuristic is the practical alternative. Safe to
    /// call from any thread.
    var permissionWarningDetected: Bool {
        os_unfair_lock_lock(permissionLock)
        defer { os_unfair_lock_unlock(permissionLock) }
        return permissionWarningFlag
    }

    /// Returns `false` if `taps` was non-empty but the mixer failed to come
    /// up (caller must then undo the taps it just created).
    @discardableResult
    func rebuild(with taps: [AudioHardwareTap]) -> Bool {
        tearDown()
        didLogFormat = false
        guard !taps.isEmpty else { return true }

        guard let outputDeviceUID = try? Self.defaultOutputDeviceUID() else {
            log.error("No default output device; cannot start mixer")
            return false
        }

        let tapUUIDs: [String] = taps.compactMap { try? $0.description.uuid.uuidString }
        guard tapUUIDs.count == taps.count else {
            log.error("Failed to read UUID for one or more taps")
            return false
        }

        let composition: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "com.audiocore.app.mixer",
            kAudioAggregateDeviceNameKey: "AudioCore Mixer",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: tapUUIDs.map { [kAudioSubTapUIDKey: $0] }
        ]

        let newAggregate: AudioHardwareAggregateDevice
        do {
            guard let created = try AudioHardwareSystem.shared.makeAggregateDevice(description: composition) else {
                log.error("makeAggregateDevice returned nil")
                return false
            }
            newAggregate = created
        } catch {
            log.error("Failed to create shared aggregate device: \(error.localizedDescription, privacy: .public)")
            return false
        }

        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, newAggregate.id, nil) { [weak self] _, inputData, _, outputData, _ in
            self?.render(inputData: inputData, outputData: outputData)
        }
        guard ioStatus == noErr, let procID else {
            try? AudioHardwareSystem.shared.destroyAggregateDevice(newAggregate)
            log.error("Failed to install IO proc on shared aggregate device, OSStatus \(ioStatus)")
            return false
        }

        do {
            try newAggregate.start(IOProcID: procID)
        } catch {
            AudioDeviceDestroyIOProcID(newAggregate.id, procID)
            try? AudioHardwareSystem.shared.destroyAggregateDevice(newAggregate)
            log.error("Failed to start shared aggregate device: \(error.localizedDescription, privacy: .public)")
            return false
        }

        aggregateDevice = newAggregate
        ioProcID = procID
        silentStreaks = Array(repeating: 0, count: taps.count)
        log.info("Mixer running with \(taps.count) tap(s)")
        return true
    }

    func tearDown() {
        if let aggregateDevice, let ioProcID {
            try? aggregateDevice.stop(IOProcID: ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDevice.id, ioProcID)
        }
        if let aggregateDevice {
            try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
        }
        aggregateDevice = nil
        ioProcID = nil
        silentStreaks = []
        os_unfair_lock_lock(permissionLock)
        permissionWarningFlag = false
        os_unfair_lock_unlock(permissionLock)
    }

    private func render(inputData: UnsafePointer<AudioBufferList>, outputData: UnsafeMutablePointer<AudioBufferList>) {
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let output = UnsafeMutableAudioBufferListPointer(outputData)

        if !didLogFormat {
            didLogFormat = true
            let inputShape = input.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B" }.joined(separator: ", ")
            let outputShape = output.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B" }.joined(separator: ", ")
            log.info("Render buffer shapes — input: [\(inputShape, privacy: .public)] output: [\(outputShape, privacy: .public)]")
        }

        let channels = channelsProvider()
        trackSilence(input: input, channels: channels)
        MixerRenderMath.render(input: input, output: output, channels: channels)
    }

    /// Updates `silentStreaks` and `permissionWarningFlag`. Real-time safe:
    /// only reads already-allocated buffers, no allocation, and only ever
    /// `trylock`s `permissionLock` (never blocks the audio thread).
    private func trackSilence(input: UnsafeMutableAudioBufferListPointer, channels: [MixerRenderMath.ChannelInput]) {
        guard !silentStreaks.isEmpty else { return }

        for channel in channels {
            guard channel.bufferIndex < silentStreaks.count, channel.bufferIndex < input.count else { continue }

            // A muted/zero-gain channel is expected to be silent — that's not
            // evidence of anything, so don't let it count toward (or falsely
            // clear right after) a real streak.
            guard !channel.isMuted, channel.gain > 0 else {
                silentStreaks[channel.bufferIndex] = 0
                continue
            }

            if isSilent(input[channel.bufferIndex]) {
                silentStreaks[channel.bufferIndex] += 1
            } else {
                silentStreaks[channel.bufferIndex] = 0
            }
        }

        let warning = silentStreaks.contains { $0 >= Self.silentStreakThreshold }
        if os_unfair_lock_trylock(permissionLock) {
            permissionWarningFlag = warning
            os_unfair_lock_unlock(permissionLock)
        }
    }

    private func isSilent(_ buffer: AudioBuffer) -> Bool {
        guard let mem = buffer.mData else { return true }
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
        guard sampleCount > 0 else { return true }
        let ptr = mem.assumingMemoryBound(to: Float32.self)
        for i in 0..<sampleCount where ptr[i] != 0 { return false }
        return true
    }

    private static func defaultOutputDeviceUID() throws -> String? {
        guard let device = try AudioHardwareSystem.shared.defaultOutputDevice else { return nil }
        return try device.uid
    }
}
