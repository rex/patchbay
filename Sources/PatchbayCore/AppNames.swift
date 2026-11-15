import AppKit

/// Display names for grouping keys, from the running app or its bundle on disk.
public enum AppNames {
  public static func name(forKey key: String, process: AudioProcess) -> String {
    // WebKit plays every web view's audio (Safari, Mail, any WKWebView app) from one
    // shared GPU process, so naming it after whichever app owns it first misleads.
    if key == "com.apple.WebKit.GPU" { return "Safari & other web views" }
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

  /// True when `key` belongs to a running app with a Dock icon, as opposed to a
  /// daemon, agent or extension. Those are what a person expects to pick from.
  public static func isRegularApp(key: String) -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: key)
      .contains { $0.activationPolicy == .regular }
  }

  /// The app a process works for, when macOS names it that way: extensions and
  /// services it runs on an app's behalf are called "QLC quicklook (Finder)",
  /// "QuickLookUIService (Mail)". Returns that app's bundle ID if it is running.
  public static func hostKey(for process: AudioProcess) -> String? {
    guard let name = NSRunningApplication(processIdentifier: process.pid)?.localizedName,
      let host = hostName(fromDisplayName: name)
    else { return nil }
    return NSWorkspace.shared.runningApplications.first {
      $0.activationPolicy == .regular && $0.localizedName == host
    }?.bundleIdentifier
  }

  /// "QLC quicklook (Finder)" → "Finder". Nil when the name ends in no parentheses.
  public static func hostName(fromDisplayName name: String) -> String? {
    guard name.hasSuffix(")"), let open = name.lastIndex(of: "("), open > name.startIndex else {
      return nil
    }
    let host = name[name.index(after: open)..<name.index(before: name.endIndex)]
    return host.isEmpty ? nil : String(host)
  }

  /// `afplay`, `say` and other bundle-less tools: the executable's short name.
  static func executableName(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 256)
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
