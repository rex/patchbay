import Testing

@testable import PatchbayCore

/// Runs `buffers` buffers of `frames` stereo frames of 1.0 through `volume`,
/// returning the last buffer.
private func render(_ volume: Volume, buffers: Int = 1, frames: Int = 4) -> [Float32] {
  var samples: [Float32] = []
  for _ in 0..<buffers {
    samples = Array(repeating: 1, count: frames * 2)
    samples.withUnsafeMutableBufferPointer {
      volume.apply(to: $0.baseAddress!, frames: frames, channels: 2)
    }
  }
  return samples
}

@Suite struct VolumeTests {
  @Test func fullVolumeLeavesSamplesAlone() {
    #expect(render(Volume()) == Array(repeating: 1, count: 8))
  }

  @Test func aChangeRampsAcrossOneBufferThenHolds() {
    let volume = Volume()
    volume.set(perMille: 500)  // 50% → amplitude 0.25
    let ramp = render(volume)
    #expect(ramp == [0.8125, 0.8125, 0.625, 0.625, 0.4375, 0.4375, 0.25, 0.25])
    #expect(render(volume) == Array(repeating: 0.25, count: 8))
  }

  @Test func muteFadesToSilenceAndKeepsTheSetting() {
    let volume = Volume(perMille: 800)
    volume.setMuted(true)
    #expect(render(volume, buffers: 2) == Array(repeating: 0, count: 8))
    #expect(volume.perMille == 800)
  }

  @Test func settingsClampToZeroThroughFull() {
    let volume = Volume()
    volume.set(perMille: 1_250)
    #expect(volume.perMille == 1_000)
    volume.set(perMille: -40)
    #expect(volume.perMille == 0)
  }

  @Test func theCurveIsSquaredSoHalfSoundsHalfAsLoud() {
    #expect(Volume.amplitude(perMille: 1_000) == 1)
    #expect(Volume.amplitude(perMille: 500) == 0.25)
    #expect(Volume.amplitude(perMille: 0) == 0)
  }
}
