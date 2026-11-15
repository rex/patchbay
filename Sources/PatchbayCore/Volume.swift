import Synchronization

/// One route's volume, applied by patchbay itself as audio passes through.
///
/// Because the gain is applied in software, every output gets per-route volume,
/// including interfaces like the Scarlett that have no hardware volume control,
/// and two apps on one device can sit at different levels.
///
/// The UI thread sets a target; the render thread reads it once per buffer and
/// ramps toward it across that buffer, so a change never clicks. Lock-free and
/// allocation-free on the render side.
public final class Volume: @unchecked Sendable {
  /// 100%, in the per-mille units the setting is kept in.
  public static let full = 1_000

  private let target = Atomic<Int>(Volume.full)
  private let mute = Atomic<Bool>(false)
  /// Render thread only: the gain the last buffer ended on.
  private var current: Float = 1

  public init(perMille: Int = Volume.full) { set(perMille: perMille) }

  /// The setting, 0...1000 (shown as 0–100%).
  public var perMille: Int { target.load(ordering: .relaxed) }
  public var isMuted: Bool { mute.load(ordering: .relaxed) }

  public func set(perMille: Int) {
    target.store(min(max(perMille, 0), Volume.full), ordering: .relaxed)
  }

  public func setMuted(_ muted: Bool) { mute.store(muted, ordering: .relaxed) }

  /// The amplitude a setting maps to. Squared, so 50% sounds about half as loud
  /// rather than barely quieter (loudness tracks amplitude roughly logarithmically).
  public static func amplitude(perMille: Int) -> Float {
    let fraction = Float(min(max(perMille, 0), full)) / Float(full)
    return fraction * fraction
  }

  /// Render thread: scales `frames` interleaved frames in place, ramping linearly
  /// from the previous buffer's gain to the current target.
  func apply(to samples: UnsafeMutablePointer<Float32>, frames: Int, channels: Int) {
    let goal = isMuted ? 0 : Volume.amplitude(perMille: perMille)
    defer { current = goal }
    if goal == 1, current == 1 { return }
    guard frames > 0 else { return }
    let step = (goal - current) / Float(frames)
    for frame in 0..<frames {
      let gain = current + step * Float(frame + 1)
      for channel in 0..<channels { samples[frame * channels + channel] *= gain }
    }
  }
}
