import CoreAudio

/// A single process's audio, captured via Core Audio process tap and muted
/// at the source (`CATapMuteBehavior.muted`) so it never reaches real
/// hardware except through our own re-render in `MixerRenderMath`.
struct TapChannel {
    let bundleID: String
    let tap: AudioHardwareTap
    var gain: Float
    var isMuted: Bool
}
