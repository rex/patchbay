import AudioToolbox
import CoreAudio

/// What the render callback needs, behind its one `refCon` pointer.
private final class RenderContext {
  let ring: RingBuffer
  let volume: Volume
  init(ring: RingBuffer, volume: Volume) {
    self.ring = ring
    self.volume = volume
  }
}

/// An output-only HAL audio unit on one device, playing whatever a `RingBuffer`
/// holds at the route's `Volume`.
///
/// Output-only matters: it never opens the device's input, so AirPods stay in
/// high-quality playback mode instead of dropping to their call-quality headset
/// profile. The unit also converts from the ring's sample rate to the device's.
final class OutputUnit {
  private var unit: AudioUnit?
  private let context: RenderContext
  private var ring: RingBuffer { context.ring }

  init(device: AudioDeviceID, sampleRate: Double, ring: RingBuffer, volume: Volume) throws {
    context = RenderContext(ring: ring, volume: volume)
    var description = AudioComponentDescription(
      componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
      componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0,
      componentFlagsMask: 0)
    guard let component = AudioComponentFindNext(nil, &description) else {
      throw HALError(status: kAudioUnitErr_InvalidElement, operation: "find HAL output unit")
    }
    try HAL.check(AudioComponentInstanceNew(component, &unit), "create output unit")
    do {
      try configure(device: device, sampleRate: sampleRate)
      try HAL.check(AudioUnitInitialize(unit!), "initialize output unit")
      try HAL.check(AudioOutputUnitStart(unit!), "start output unit")
    } catch {
      stop()
      throw error
    }
  }

  deinit { stop() }

  private func configure(device: AudioDeviceID, sampleRate: Double) throws {
    guard let unit else { return }
    var device = device
    try HAL.check(
      AudioUnitSetProperty(
        unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
        UInt32(MemoryLayout<AudioDeviceID>.size)), "point output unit at device")

    let bytesPerFrame = UInt32(MemoryLayout<Float32>.size * ring.channels)
    var format = AudioStreamBasicDescription(
      mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
      mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
      mChannelsPerFrame: UInt32(ring.channels), mBitsPerChannel: 32, mReserved: 0)
    try HAL.check(
      AudioUnitSetProperty(
        unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format,
        UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set output unit format")

    var callback = AURenderCallbackStruct(
      inputProc: { refCon, _, _, _, frames, data in
        let context = Unmanaged<RenderContext>.fromOpaque(refCon).takeUnretainedValue()
        if let buffer = data?.pointee.mBuffers, let raw = buffer.mData {
          let samples = raw.assumingMemoryBound(to: Float32.self)
          context.ring.read(into: samples, frames: Int(frames))
          context.volume.apply(to: samples, frames: Int(frames), channels: context.ring.channels)
        }
        return noErr
      },
      inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
    try HAL.check(
      AudioUnitSetProperty(
        unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
        UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set render callback")
  }

  /// Stops and disposes of the unit. Safe to call twice.
  func stop() {
    guard let unit else { return }
    AudioOutputUnitStop(unit)
    AudioUnitUninitialize(unit)
    AudioComponentInstanceDispose(unit)
    self.unit = nil
  }
}
