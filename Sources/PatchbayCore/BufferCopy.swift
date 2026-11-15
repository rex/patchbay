import CoreAudio

/// Channel addressing across a Core Audio buffer list. No allocation, no locks,
/// so it is safe on real-time IO threads.
///
/// Samples are Float32 (the HAL's canonical IO format). Each buffer holds one
/// channel (deinterleaved) or several (interleaved); channels are numbered across
/// buffers in order. Buffers whose `mData` is nil were switched off and are skipped.
enum BufferCopy {
  /// Total channels across the buffers that are switched on.
  static func channelCount(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
    var count = 0
    for buffer in list where buffer.mData != nil { count += Int(buffer.mNumberChannels) }
    return count
  }

  /// Where channel `channel` lives: its buffer's samples, interleave stride, lane
  /// within the stride, and how many frames the buffer holds.
  static func locate(channel: Int, in list: UnsafeMutableAudioBufferListPointer) -> (
    samples: UnsafeMutablePointer<Float32>, stride: Int, lane: Int, frames: Int
  )? {
    var first = 0
    for buffer in list where buffer.mData != nil {
      let stride = Int(buffer.mNumberChannels)
      if stride > 0, channel < first + stride {
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * stride)
        return (
          buffer.mData!.assumingMemoryBound(to: Float32.self), stride, channel - first, frames
        )
      }
      first += stride
    }
    return nil
  }
}
