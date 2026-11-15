import PatchbayCore

/// Display labels for output devices, in the same order as the devices.
public enum DeviceLabels {
  /// Names that repeat (two outputs of one monitor, say) get " (1)", " (2)", ...
  public static func labels(for devices: [OutputDevice]) -> [String] {
    var counts: [String: Int] = [:]
    for device in devices { counts[device.name, default: 0] += 1 }
    var seen: [String: Int] = [:]
    return devices.map { device in
      guard counts[device.name, default: 0] > 1 else { return device.name }
      seen[device.name, default: 0] += 1
      return "\(device.name) (\(seen[device.name, default: 0]))"
    }
  }

  /// "44.1 kHz · default": what goes beside a device's label.
  public static func detail(for device: OutputDevice) -> String {
    let tenths = Int((device.sampleRate / 100).rounded())
    let rate = tenths % 10 == 0 ? "\(tenths / 10) kHz" : "\(tenths / 10).\(tenths % 10) kHz"
    return device.isDefault ? rate + " · default" : rate
  }
}
