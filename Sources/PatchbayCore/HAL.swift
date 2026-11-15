import CoreAudio

/// A Core Audio HAL call that returned something other than `noErr`.
public struct HALError: Error, CustomStringConvertible, Sendable {
  public let status: OSStatus
  public let operation: String

  public var description: String {
    "\(operation) failed: \(HALError.fourCC(status)) (\(status))"
  }

  /// Most HAL errors are four-character codes ('who?', '!dev'); show them that way.
  static func fourCC(_ status: OSStatus) -> String {
    let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian) { Array($0) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "\(status)" }
    return "'" + String(decoding: bytes, as: UTF8.self) + "'"
  }
}

/// Thin, throwing wrappers over `AudioObjectGetPropertyData` and friends.
enum HAL {
  static let system = AudioObjectID(kAudioObjectSystemObject)

  static func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw HALError(status: status, operation: operation()) }
  }

  static func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  /// A fixed-size property (UInt32, Float64, pid_t, AudioObjectID, an ASBD, ...).
  static func value<T: BitwiseCopyable>(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    initial: T
  ) throws -> T {
    var address = address(selector, scope)
    var size = UInt32(MemoryLayout<T>.size)
    var value = initial
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    try check(status, "read \(HALError.fourCC(OSStatus(bitPattern: selector)))")
    return value
  }

  /// A variable-length list of object IDs (devices, processes, streams).
  static func objectIDs(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) throws -> [AudioObjectID] {
    var address = address(selector, scope)
    var size: UInt32 = 0
    let label = "list \(HALError.fourCC(OSStatus(bitPattern: selector)))"
    try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), label)
    let count = Int(size) / MemoryLayout<AudioObjectID>.stride
    guard count > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: count)
    try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids), label)
    return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
  }

  /// A CFString property. The HAL hands back a +1 reference; this releases it.
  static func string(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) throws -> String {
    var address = address(selector, scope)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    try check(status, "read \(HALError.fourCC(OSStatus(bitPattern: selector)))")
    return value?.takeRetainedValue() as String? ?? ""
  }

  /// Byte size of a property, for "does this device have output streams" questions.
  static func size(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope
  ) -> UInt32 {
    var address = address(selector, scope)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr ? size : 0
  }
}
