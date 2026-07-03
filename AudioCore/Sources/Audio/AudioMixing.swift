/// Seam between `VolumeManager` and the real Core Audio mixer engine, so
/// app-state coordination logic can be exercised in tests with a fake
/// instead of live Core Audio hardware.
protocol AudioMixing {
    func setGain(_ gain: Float, isMuted: Bool, for bundleID: String)
    func sync(activeBundleIDs: Set<String>, initialState: (String) -> (gain: Float, isMuted: Bool))
    func stopAll()

    /// Best-effort, heuristic signal that system audio recording permission
    /// is missing: a tapped app CoreAudio itself reports as actively
    /// outputting audio has rendered nothing but silence for a sustained
    /// stretch. Safe to poll from any thread.
    var permissionWarningDetected: Bool { get }

    /// Triggers the OS's system-audio-recording consent prompt as early as
    /// possible (app launch) rather than waiting for the first real tap.
    func primeAudioCapturePermission()
}
