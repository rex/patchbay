/// Turns the audio server's process list into the apps a person would pick from.
///
/// Pure logic, no Core Audio: the tests run it without any permission.
public enum AppGrouping {
  public static let finder = "com.apple.finder"

  /// The bundle ID of the app a process plays audio for.
  ///
  /// Browsers and Electron apps play sound from a helper whose bundle ID extends
  /// the app's: `com.google.Chrome.helper` and `com.google.Chrome.helper.Renderer`
  /// both belong to `com.google.Chrome`. QuickLook's own processes belong to Finder,
  /// whose previews they play. Anything else is its own app.
  public static func appKey(forBundleID bundleID: String) -> String {
    if bundleID.hasPrefix("com.apple.quicklook") { return finder }
    let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
    guard let helper = parts.firstIndex(where: { $0.lowercased().hasPrefix("helper") }),
      helper > 0
    else { return bundleID }
    return parts[..<helper].joined(separator: ".")
  }

  /// The grouping key for one process: its app's bundle ID, or `pid:<n>` when it has none.
  public static func key(for process: AudioProcess) -> String {
    process.bundleID.isEmpty ? "pid:\(process.pid)" : appKey(forBundleID: process.bundleID)
  }

  /// Groups processes into apps, playing apps first, then by name.
  ///
  /// - Parameters:
  ///   - name: resolves a grouping key to a display name, given one of its processes.
  ///   - host: the key of the app a process works for, when it says so (an
  ///     extension named "QLC quicklook (Finder)" works for Finder). Wins over
  ///     the bundle-ID rules.
  ///   - pinned: apps to list even with no audio processes yet, as key → name.
  public static func apps(
    from processes: [AudioProcess],
    name: (String, AudioProcess) -> String,
    host: (AudioProcess) -> String? = { _ in nil },
    pinned: [String: String] = [:]
  ) -> [AudioApp] {
    let grouped = Dictionary(grouping: processes) { host($0) ?? key(for: $0) }
    var apps = grouped.map { key, members in
      AudioApp(
        key: key,
        name: pinned[key] ?? name(key, members[0]),
        processes: members.sorted { $0.pid < $1.pid })
    }
    for (key, label) in pinned where grouped[key] == nil {
      apps.append(AudioApp(key: key, name: label, processes: []))
    }
    return apps.sorted {
      $0.isPlaying != $1.isPlaying
        ? $0.isPlaying : $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}
