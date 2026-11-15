import CoreAudio
import Synchronization

/// A single-producer, single-consumer ring of interleaved Float32 frames.
///
/// The tap's IO thread writes; the output unit's render thread reads. They run on
/// different clocks, so the reader keeps latency bounded: it waits for `target`
/// frames before playing, plays silence when the writer falls behind, and skips
/// ahead when more than `ceiling` frames pile up. Lock-free and allocation-free
/// after init, so both sides are safe on real-time threads.
public final class RingBuffer: @unchecked Sendable {
  public let channels: Int
  let capacity: Int
  let target: Int
  let ceiling: Int
  private let samples: UnsafeMutablePointer<Float32>
  /// Total frames ever written / read. Only the writer stores `written`, only the
  /// reader stores `read`; each side loads the other's with acquire ordering.
  private let written = Atomic<Int>(0)
  private let read = Atomic<Int>(0)
  /// Reader-only: false until `target` frames have arrived (and again after an underrun).
  private var primed = false

  public init(channels: Int, capacity: Int = 16_384, target: Int = 1_024, ceiling: Int = 4_096) {
    precondition(channels > 0 && target < ceiling && ceiling < capacity)
    self.channels = channels
    self.capacity = capacity
    self.target = target
    self.ceiling = ceiling
    samples = .allocate(capacity: capacity * channels)
    samples.initialize(repeating: 0, count: capacity * channels)
  }

  deinit { samples.deallocate() }

  /// Writer side: append the frames held in the LAST `channels` channels of `input`
  /// (an aggregate lists its taps after any device inputs). Frames that don't fit are
  /// dropped. Returns the peak absolute sample written.
  @discardableResult
  public func write(from input: UnsafeMutableAudioBufferListPointer) -> Float {
    let first = BufferCopy.channelCount(input) - channels
    guard first >= 0, let lead = BufferCopy.locate(channel: first, in: input) else { return 0 }
    let start = written.load(ordering: .relaxed)
    let space = capacity - (start - read.load(ordering: .acquiring))
    let count = min(lead.frames, space)
    guard count > 0 else { return 0 }
    var peak: Float = 0
    for channel in 0..<channels {
      guard let source = BufferCopy.locate(channel: first + channel, in: input) else { continue }
      for frame in 0..<min(count, source.frames) {
        let sample = source.samples[frame * source.stride + source.lane]
        samples[((start + frame) % capacity) * channels + channel] = sample
        peak = max(peak, abs(sample))
      }
    }
    written.store(start + count, ordering: .releasing)
    return peak
  }

  /// Reader side: fill `frames` interleaved frames at `output`, padding with silence.
  public func read(into output: UnsafeMutablePointer<Float32>, frames: Int) {
    var start = read.load(ordering: .relaxed)
    let end = written.load(ordering: .acquiring)
    var available = end - start
    if available > ceiling {  // writer's clock runs fast: drop the oldest frames
      start = end - target
      available = target
    }
    if !primed { primed = available >= target }
    let count = primed ? min(frames, available) : 0
    for frame in 0..<count {
      let from = ((start + frame) % capacity) * channels
      for channel in 0..<channels { output[frame * channels + channel] = samples[from + channel] }
    }
    if count < frames {
      output.advanced(by: count * channels).update(repeating: 0, count: (frames - count) * channels)
      if primed { primed = false }  // underrun: wait for `target` frames again
    }
    read.store(start + count, ordering: .releasing)
  }

  /// Frames waiting to be read. Approximate when called off the audio threads.
  public var buffered: Int { written.load(ordering: .relaxed) - read.load(ordering: .relaxed) }
}
