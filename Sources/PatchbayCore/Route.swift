import CoreAudio
import Foundation

/// One app's audio, playing on one device instead of wherever it was going.
///
/// The chain: a private process tap mutes the app at its source; a private
/// aggregate device made of nothing but that tap runs an IOProc that writes the
/// audio into a ring buffer; an output-only unit on the destination plays the
/// ring, converting sample rates when the tap and the device differ.
///
/// The aggregate deliberately holds no real device. Putting the destination in
/// it would bring the destination's inputs onto the aggregate's input side, and
/// an open AirPods mic drops them into call-quality mode. The output unit never
/// opens an input.
///
/// `stop()` (or deinit) destroys everything. macOS also destroys private taps and
/// aggregates when their process dies, so a crash can't leave an app muted.
public final class Route {
  public let app: AudioApp
  public let device: OutputDevice
  /// Live counters, written by the IO thread. For diagnostics, not for logic.
  public let stats = RouteStats()

  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private var ring: RingBuffer?
  private var output: OutputUnit?

  public init(app: AudioApp, device: OutputDevice) throws {
    self.app = app
    self.device = device
    do { try start() } catch {
      stop()
      throw error
    }
  }

  deinit { stop() }

  /// The tap's own format: what the app produces, before any conversion.
  public func tapFormat() throws -> AudioStreamBasicDescription {
    try HAL.value(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
  }

  /// Frames queued between the tap and the output: the route's added latency.
  public var bufferedFrames: Int { ring?.buffered ?? 0 }

  private func start() throws {
    let description = CATapDescription(stereoMixdownOfProcesses: app.processes.map(\.objectID))
    description.uuid = UUID()
    description.name = "patchbay: \(app.name) → \(device.name)"
    description.muteBehavior = .mutedWhenTapped
    description.isPrivate = true
    try HAL.check(AudioHardwareCreateProcessTap(description, &tapID), "create process tap")

    let format = try tapFormat()
    let ring = RingBuffer(channels: Int(format.mChannelsPerFrame))
    self.ring = ring
    output = try OutputUnit(device: device.id, sampleRate: format.mSampleRate, ring: ring)

    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: description.name,
      kAudioAggregateDeviceUIDKey: "patchbay.\(UUID().uuidString)",
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapUIDKey: try HAL.string(tapID, kAudioTapPropertyUID)]
      ],
    ]
    try HAL.check(
      AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
      "create aggregate device")

    let stats = self.stats
    try HAL.check(
      AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, _, _ in
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        stats.record(peak: ring.write(from: inputs), inputChannels: BufferCopy.channelCount(inputs))
      }, "create IOProc")
    try HAL.check(AudioDeviceStart(aggregateID, procID), "start aggregate device")
  }

  /// Tears the route down; the app goes back to its normal output. Safe to call twice.
  public func stop() {
    if let procID, aggregateID != kAudioObjectUnknown {
      AudioDeviceStop(aggregateID, procID)
      AudioDeviceDestroyIOProcID(aggregateID, procID)
    }
    procID = nil
    output?.stop()
    output = nil
    if aggregateID != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(aggregateID)
      aggregateID = AudioObjectID(kAudioObjectUnknown)
    }
    if tapID != kAudioObjectUnknown {
      AudioHardwareDestroyProcessTap(tapID)
      tapID = AudioObjectID(kAudioObjectUnknown)
    }
    ring = nil
  }
}

/// Counters the IO thread bumps. Plain aligned stores: good enough for a meter.
public final class RouteStats: @unchecked Sendable {
  private let storage = UnsafeMutablePointer<Float>.allocate(capacity: 3)

  init() { storage.initialize(repeating: 0, count: 3) }
  deinit { storage.deallocate() }

  func record(peak: Float, inputChannels: Int) {
    storage[0] += 1
    storage[1] = max(storage[1], peak)
    storage[2] = Float(inputChannels)
  }

  /// IO cycles run, the loudest sample since the last call (then reset), and how
  /// many input channels the IOProc received in its latest cycle.
  public func take() -> (cycles: Int, peak: Float, inputChannels: Int) {
    let result = (Int(storage[0]), storage[1], Int(storage[2]))
    storage[1] = 0
    return result
  }
}
