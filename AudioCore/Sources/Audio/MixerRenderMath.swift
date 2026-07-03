import CoreAudio

/// Pure sample-mixing math for the shared aggregate device's render
/// callback: zero the output, sum each active channel's gain-scaled input
/// into it, then clamp. No locking, no Core Audio device APIs, no
/// allocation — safe to call from the real-time I/O thread, and testable
/// without any live hardware by constructing synthetic buffer lists.
enum MixerRenderMath {
    struct ChannelInput {
        let bufferIndex: Int
        let gain: Float
        let isMuted: Bool
    }

    static func render(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        channels: [ChannelInput]
    ) {
        zero(output)
        guard output.count > 0 else { return }

        for channel in channels {
            guard channel.bufferIndex < input.count, !channel.isMuted, channel.gain > 0,
                  let inMemory = input[channel.bufferIndex].mData else { continue }

            // Every tap is a stereo mixdown targeting the same physical output,
            // so in the overwhelmingly common case there is exactly one output
            // buffer and every app's buffer sums straight into it. Fall back to
            // index-matching if the device ever exposes more than one.
            let outIndex = output.count == 1 ? 0 : min(channel.bufferIndex, output.count - 1)
            guard let outMemory = output[outIndex].mData else { continue }

            let inByteSize = Int(input[channel.bufferIndex].mDataByteSize)
            let outByteSize = Int(output[outIndex].mDataByteSize)
            let sampleCount = min(inByteSize, outByteSize) / MemoryLayout<Float32>.size

            let inPtr = inMemory.assumingMemoryBound(to: Float32.self)
            let outPtr = outMemory.assumingMemoryBound(to: Float32.self)
            for sample in 0..<sampleCount {
                outPtr[sample] += inPtr[sample] * channel.gain
            }
        }

        // Multiple apps summed together can exceed [-1, 1] and clip harshly;
        // a hard clamp trades that for gentler (if audible) saturation.
        clamp(output)
    }

    private static func zero(_ output: UnsafeMutableAudioBufferListPointer) {
        for outIndex in 0..<output.count {
            guard let outMemory = output[outIndex].mData else { continue }
            let sampleCount = Int(output[outIndex].mDataByteSize) / MemoryLayout<Float32>.size
            outMemory.assumingMemoryBound(to: Float32.self).update(repeating: 0, count: sampleCount)
        }
    }

    private static func clamp(_ output: UnsafeMutableAudioBufferListPointer) {
        for outIndex in 0..<output.count {
            guard let outMemory = output[outIndex].mData else { continue }
            let sampleCount = Int(output[outIndex].mDataByteSize) / MemoryLayout<Float32>.size
            let outPtr = outMemory.assumingMemoryBound(to: Float32.self)
            for sample in 0..<sampleCount {
                outPtr[sample] = max(-1, min(1, outPtr[sample]))
            }
        }
    }
}
