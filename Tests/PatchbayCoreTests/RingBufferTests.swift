import CoreAudio
import Testing

@testable import PatchbayCore

/// Builds a one-buffer interleaved list holding `frames`, calls `body`, frees it.
private func withInterleaved(
  _ samples: [Float32], channels: Int, _ body: (UnsafeMutableAudioBufferListPointer) -> Void
) {
  var copy = samples
  copy.withUnsafeMutableBytes { bytes in
    let list = AudioBufferList.allocate(maximumBuffers: 1)
    defer { list.unsafeMutablePointer.deallocate() }
    list[0] = AudioBuffer(
      mNumberChannels: UInt32(channels), mDataByteSize: UInt32(bytes.count),
      mData: bytes.baseAddress)
    body(list)
  }
}

private func read(_ ring: RingBuffer, frames: Int) -> [Float32] {
  var out = [Float32](repeating: -1, count: frames * ring.channels)
  out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frames: frames) }
  return out
}

@Suite struct RingBufferTests {
  @Test func playsSilenceUntilPrimedThenPlaysInOrder() {
    let ring = RingBuffer(channels: 2, capacity: 16, target: 4, ceiling: 8)
    withInterleaved([1, -1, 2, -2], channels: 2) { ring.write(from: $0) }
    #expect(read(ring, frames: 2) == [0, 0, 0, 0])  // 2 frames < target 4: still priming

    withInterleaved([3, -3, 4, -4], channels: 2) { ring.write(from: $0) }
    #expect(read(ring, frames: 3) == [1, -1, 2, -2, 3, -3])
    #expect(ring.buffered == 1)
  }

  @Test func underrunPadsWithSilenceAndReprimes() {
    let ring = RingBuffer(channels: 1, capacity: 16, target: 2, ceiling: 8)
    withInterleaved([1, 2, 3], channels: 1) { ring.write(from: $0) }
    #expect(read(ring, frames: 5) == [1, 2, 3, 0, 0])
    withInterleaved([4], channels: 1) { ring.write(from: $0) }
    #expect(read(ring, frames: 1) == [0])  // 1 frame < target 2 after the underrun
  }

  @Test func aFastWriterIsTrimmedBackToTarget() {
    let ring = RingBuffer(channels: 1, capacity: 16, target: 2, ceiling: 4)
    withInterleaved([1, 2, 3, 4, 5, 6], channels: 1) { ring.write(from: $0) }
    #expect(read(ring, frames: 2) == [5, 6])  // 6 > ceiling 4: keep only the newest 2
  }

  @Test func aFullRingDropsWhatDoesNotFit() {
    let ring = RingBuffer(channels: 1, capacity: 4, target: 1, ceiling: 3)
    let peak = withInterleavedPeak([1, 2, 3, 4, 5, 6], channels: 1, ring: ring)
    #expect(ring.buffered == 4)
    #expect(peak == 4)
  }

  @Test func readsTheTapFromTheLastChannels() {
    // A 4-channel aggregate input: 2 device channels first, then the 2-channel tap.
    let ring = RingBuffer(channels: 2, capacity: 16, target: 1, ceiling: 8)
    withInterleaved([9, 9, 1, -1, 9, 9, 2, -2], channels: 4) { ring.write(from: $0) }
    #expect(read(ring, frames: 2) == [1, -1, 2, -2])
  }
}

private func withInterleavedPeak(_ samples: [Float32], channels: Int, ring: RingBuffer) -> Float {
  var peak: Float = 0
  withInterleaved(samples, channels: channels) { peak = ring.write(from: $0) }
  return peak
}
