import CoreAudio

/// One process the audio server knows about.
public struct AudioProcess: Sendable, Hashable {
  /// The HAL's object ID for the process; what a tap is built from.
  public let objectID: AudioObjectID
  public let pid: pid_t
  /// Empty for processes with no bundle (command-line tools such as `afplay`).
  public let bundleID: String
  public let isRunningOutput: Bool

  public init(objectID: AudioObjectID, pid: pid_t, bundleID: String, isRunningOutput: Bool) {
    self.objectID = objectID
    self.pid = pid
    self.bundleID = bundleID
    self.isRunningOutput = isRunningOutput
  }

  /// Every process registered with the audio server, playing or not.
  public static func all() throws -> [AudioProcess] {
    let ids = try HAL.objectIDs(HAL.system, kAudioHardwarePropertyProcessObjectList)
    return ids.compactMap { id in
      guard let pid: pid_t = try? HAL.value(id, kAudioProcessPropertyPID, initial: 0) else {
        return nil
      }
      let running: UInt32 =
        (try? HAL.value(id, kAudioProcessPropertyIsRunningOutput, initial: 0)) ?? 0
      return AudioProcess(
        objectID: id,
        pid: pid,
        bundleID: (try? HAL.string(id, kAudioProcessPropertyBundleID)) ?? "",
        isRunningOutput: running != 0)
    }
  }

  /// Calls `handler` on `queue` whenever a process starts or stops using audio, so
  /// a route can take in a new helper (a QuickLook preview, say) straight away
  /// instead of on the next poll. For the life of the process.
  public static func onListChange(queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void) {
    var address = HAL.address(kAudioHardwarePropertyProcessObjectList)
    AudioObjectAddPropertyListenerBlock(HAL.system, &address, queue) { _, _ in handler() }
  }
}

/// An app as a person thinks of it: Chrome, not "Google Chrome Helper (pid 812)".
public struct AudioApp: Sendable, Hashable, Identifiable {
  /// The app's bundle ID, or `pid:<n>` for a process with no bundle.
  public let key: String
  public let name: String
  /// The app's own process plus any helpers that play audio for it.
  public let processes: [AudioProcess]

  public var id: String { key }
  public var isPlaying: Bool { processes.contains { $0.isRunningOutput } }

  public init(key: String, name: String, processes: [AudioProcess]) {
    self.key = key
    self.name = name
    self.processes = processes
  }
}
