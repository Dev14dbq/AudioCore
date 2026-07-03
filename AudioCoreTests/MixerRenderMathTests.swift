import CoreAudio
import Testing
@testable import AudioCore

@Suite("MixerRenderMath")
struct MixerRenderMathTests {
    private static func makeBufferList(frameCount: Int, buffers: Int = 1, fill: Float32) -> UnsafeMutableAudioBufferListPointer {
        let bytes = frameCount * MemoryLayout<Float32>.size
        let listPtr = AudioBufferList.allocate(maximumBuffers: buffers)
        for i in 0..<buffers {
            let dataPtr = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<Float32>.alignment)
            dataPtr.assumingMemoryBound(to: Float32.self).update(repeating: fill, count: frameCount)
            listPtr[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes), mData: dataPtr)
        }
        return listPtr
    }

    private static func deallocate(_ list: UnsafeMutableAudioBufferListPointer) {
        for buffer in list {
            buffer.mData?.deallocate()
        }
        list.unsafeMutablePointer.deallocate()
    }

    private static func samples(_ list: UnsafeMutableAudioBufferListPointer, buffer: Int = 0) -> [Float32] {
        guard let mData = list[buffer].mData else { return [] }
        let count = Int(list[buffer].mDataByteSize) / MemoryLayout<Float32>.size
        return Array(UnsafeBufferPointer(start: mData.assumingMemoryBound(to: Float32.self), count: count))
    }

    @Test func silenceWithNoChannelsZerosOutput() {
        let input = Self.makeBufferList(frameCount: 4, fill: 0)
        let output = Self.makeBufferList(frameCount: 4, fill: 99) // stale data
        defer { Self.deallocate(input); Self.deallocate(output) }

        MixerRenderMath.render(input: input, output: output, channels: [])

        #expect(Self.samples(output) == [0, 0, 0, 0])
    }

    @Test func gainScalesInputIntoOutput() {
        let input = Self.makeBufferList(frameCount: 4, fill: 1.0)
        let output = Self.makeBufferList(frameCount: 4, fill: 0)
        defer { Self.deallocate(input); Self.deallocate(output) }

        let channels = [MixerRenderMath.ChannelInput(bufferIndex: 0, gain: 0.5, isMuted: false)]
        MixerRenderMath.render(input: input, output: output, channels: channels)

        #expect(Self.samples(output) == [0.5, 0.5, 0.5, 0.5])
    }

    @Test func mutedChannelContributesNothing() {
        let input = Self.makeBufferList(frameCount: 4, fill: 1.0)
        let output = Self.makeBufferList(frameCount: 4, fill: 0)
        defer { Self.deallocate(input); Self.deallocate(output) }

        let channels = [MixerRenderMath.ChannelInput(bufferIndex: 0, gain: 1.0, isMuted: true)]
        MixerRenderMath.render(input: input, output: output, channels: channels)

        #expect(Self.samples(output) == [0, 0, 0, 0])
    }

    @Test func multipleChannelsSumIntoTheSingleOutputBuffer() {
        let input = Self.makeBufferList(frameCount: 4, buffers: 2, fill: 0.3)
        let output = Self.makeBufferList(frameCount: 4, fill: 0)
        defer { Self.deallocate(input); Self.deallocate(output) }

        let channels = [
            MixerRenderMath.ChannelInput(bufferIndex: 0, gain: 1.0, isMuted: false),
            MixerRenderMath.ChannelInput(bufferIndex: 1, gain: 1.0, isMuted: false)
        ]
        MixerRenderMath.render(input: input, output: output, channels: channels)

        for sample in Self.samples(output) {
            #expect(abs(sample - 0.6) < 0.0001)
        }
    }

    @Test func clippingClampsPositiveOverflowToOne() {
        let input = Self.makeBufferList(frameCount: 2, buffers: 2, fill: 0.9)
        let output = Self.makeBufferList(frameCount: 2, fill: 0)
        defer { Self.deallocate(input); Self.deallocate(output) }

        let channels = [
            MixerRenderMath.ChannelInput(bufferIndex: 0, gain: 1.0, isMuted: false),
            MixerRenderMath.ChannelInput(bufferIndex: 1, gain: 1.0, isMuted: false)
        ]
        MixerRenderMath.render(input: input, output: output, channels: channels)

        #expect(Self.samples(output) == [1.0, 1.0])
    }

    @Test func clippingClampsNegativeOverflowToNegativeOne() {
        let input = Self.makeBufferList(frameCount: 2, buffers: 2, fill: -0.9)
        let output = Self.makeBufferList(frameCount: 2, fill: 0)
        defer { Self.deallocate(input); Self.deallocate(output) }

        let channels = [
            MixerRenderMath.ChannelInput(bufferIndex: 0, gain: 1.0, isMuted: false),
            MixerRenderMath.ChannelInput(bufferIndex: 1, gain: 1.0, isMuted: false)
        ]
        MixerRenderMath.render(input: input, output: output, channels: channels)

        #expect(Self.samples(output) == [-1.0, -1.0])
    }
}
