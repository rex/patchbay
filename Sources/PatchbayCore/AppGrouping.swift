/// Turns the audio server's process list into the apps a person would pick from.
///
/// Pure logic, no Core Audio: the tests run it without any permission.
public enum AppGrouping {
  /// The bundle ID of the app a process plays audio for.
  ///
  /// Browsers and Electron apps play sound from a helper whose bundle ID extends
  /// the app's: `com.google.Chrome.helper` and `com.google.Chrome.helper.Renderer`
  /// both belong to `com.google.Chrome`. Anything else is its own app.
  public static func appKey(forBundleID bundleID: String) -> String {
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
  /// - Parameter name: resolves a grouping key to a display name, given one of its processes.
  public static func apps(
    from processes: [AudioProcess],
    name: (String, AudioProcess) -> String
  ) -> [AudioApp] {
    let grouped = Dictionary(grouping: processes, by: key(for:))
    let apps = grouped.map { key, members in
      AudioApp(
        key: key,
        name: name(key, members[0]),
        processes: members.sorted { $0.pid < $1.pid })
    }
    return apps.sorted {
      $0.isPlaying != $1.isPlaying
        ? $0.isPlaying : $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}
