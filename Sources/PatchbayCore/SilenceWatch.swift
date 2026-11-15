import Darwin

/// Notices a route that carries nothing while its app is playing.
///
/// That is what a missing permission looks like: if the terminal running patchbay
/// isn't allowed to record system audio, macOS hands the tap digital silence
/// instead of failing, and the tap still mutes the app. Without this watch the
/// app just goes quiet everywhere and nothing says why.
public struct SilenceWatch: Sendable, Equatable {
  /// Seconds of exact silence, with the app playing, before the watch speaks up.
  public let threshold: Int
  public private(set) var silentSeconds = 0

  public init(threshold: Int = 3) { self.threshold = threshold }

  public var isSilent: Bool { silentSeconds >= threshold }

  /// Feeds one second's loudest sample. Returns true only on the second the route
  /// first counts as silent, so the warning is shown once, not every second.
  public mutating func observe(peak: Float, appIsPlaying: Bool) -> Bool {
    let wasSilent = isSilent
    silentSeconds = appIsPlaying && peak == 0 ? silentSeconds + 1 : 0
    return isSilent && !wasSilent
  }

  /// What to tell the person, naming the terminal app that needs the permission.
  public static func advice(appName: String, host: String?) -> String {
    let terminal = host ?? "your terminal app"
    return
      "No sound is reaching patchbay from \(appName). If you hear nothing, allow \(terminal) in "
      + "System Settings → Privacy & Security → Screen & System Audio Recording, then reopen \(terminal)."
  }
}

/// The app patchbay runs inside (iTerm, Terminal, Ghostty...): macOS checks *its*
/// permissions, not patchbay's, because patchbay is a command-line tool.
public enum HostApp {
  /// Walks up the process tree to the first ancestor that lives in a `.app` bundle.
  public static func name() -> String? {
    var pid = getpid()
    for _ in 0..<16 where pid > 1 {
      var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
      let length = Int(proc_pidpath(pid, &path, UInt32(path.count)))
      let executable = String(
        decoding: path.prefix(max(length, 0)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
      if let name = appName(fromExecutablePath: executable) { return name }
      var info = proc_bsdinfo()
      let size = Int32(MemoryLayout<proc_bsdinfo>.size)
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
      pid = pid_t(info.pbi_ppid)
    }
    return nil
  }

  /// "/Applications/iTerm.app/Contents/MacOS/iTerm2" → "iTerm".
  public static func appName(fromExecutablePath path: String) -> String? {
    guard let bundle = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) else {
      return nil
    }
    return String(bundle.dropLast(4))
  }
}
