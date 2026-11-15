import AppKit

/// Display names for grouping keys, from the running app or its bundle on disk.
public enum AppNames {
  public static func name(forKey key: String, process: AudioProcess) -> String {
    if !key.hasPrefix("pid:") {
      if let app = NSRunningApplication.runningApplications(withBundleIdentifier: key).first,
        let name = app.localizedName
      {
        return name
      }
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
        return FileManager.default.displayName(atPath: url.path)
          .replacingOccurrences(of: ".app", with: "")
      }
      return key
    }
    if let name = NSRunningApplication(processIdentifier: process.pid)?.localizedName {
      return name
    }
    return executableName(pid: process.pid) ?? key
  }

  /// `afplay`, `say` and other bundle-less tools: the executable's short name.
  static func executableName(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 256)
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
