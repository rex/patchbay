import Foundation

/// The routes patchbay restores when it starts, kept in
/// `~/Library/Application Support/patchbay/routes.json`.
///
/// Names are stored next to the IDs so a route can be shown while its app isn't
/// running or its output is away (AirPods in their case). Hand-editable; a
/// missing or unreadable file just means no remembered routes.
public struct RouteMemory: Codable, Equatable, Sendable {
  public struct Entry: Codable, Equatable, Sendable {
    /// App key (bundle ID) and the name it was last seen under.
    public var app: String
    public var appName: String
    /// Output device UID (stable across reconnects) and its name.
    public var output: String
    public var outputName: String
    /// 0–100.
    public var volume: Int
    public var muted: Bool

    public init(
      app: String, appName: String, output: String, outputName: String, volume: Int, muted: Bool
    ) {
      self.app = app
      self.appName = appName
      self.output = output
      self.outputName = outputName
      self.volume = volume
      self.muted = muted
    }
  }

  public var routes: [Entry]

  public init(routes: [Entry] = []) { self.routes = routes }

  /// `$PATCHBAY_ROUTES_FILE` if set (handy for testing), else
  /// `~/Library/Application Support/patchbay/routes.json`.
  public static var defaultURL: URL {
    if let path = ProcessInfo.processInfo.environment["PATCHBAY_ROUTES_FILE"], !path.isEmpty {
      return URL(filePath: path)
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "patchbay/routes.json")
  }

  public static func load(from url: URL = defaultURL) -> RouteMemory {
    guard let data = try? Data(contentsOf: url),
      let memory = try? JSONDecoder().decode(RouteMemory.self, from: data)
    else { return RouteMemory() }
    return memory
  }

  public func save(to url: URL = defaultURL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
