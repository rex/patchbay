/// One source in the left column: an app that can play audio.
public struct AppRow: Equatable, Sendable {
  public let key: String
  public let name: String
  public let isPlaying: Bool
  /// UID of the output this app is routed to, if any.
  public let routedUID: String?
  /// Loudest recent sample on the route, 0...1, for the level meter.
  public let level: Float
  /// The app is playing but its route has carried only silence for a while,
  /// usually because the terminal lacks the audio-recording permission.
  public let isSilent: Bool
  /// Routed, but the app has no audio processes yet; the route starts when it plays.
  public let isWaiting: Bool
  /// The route's volume, 0–100%, and whether it's muted. Shown only when routed.
  public let volume: Int
  public let isMuted: Bool

  public init(
    key: String, name: String, isPlaying: Bool, routedUID: String? = nil, level: Float = 0,
    isSilent: Bool = false, isWaiting: Bool = false, volume: Int = 100, isMuted: Bool = false
  ) {
    self.key = key
    self.name = name
    self.isPlaying = isPlaying
    self.routedUID = routedUID
    self.level = level
    self.isSilent = isSilent
    self.isWaiting = isWaiting
    self.volume = volume
    self.isMuted = isMuted
  }
}

/// One output in the right column.
public struct DeviceRow: Equatable, Sendable {
  public let uid: String
  public let label: String
  /// Sample rate and "default", shown beside the label.
  public let detail: String

  public init(uid: String, label: String, detail: String = "") {
    self.uid = uid
    self.label = label
    self.detail = detail
  }
}

/// What an input asks the controller to do. Moving around needs no command.
public enum Command: Equatable, Sendable {
  case route(appKey: String, deviceUID: String)
  case unroute(appKey: String)
  /// Change a routed app's volume by `step` percentage points (±5 per keypress).
  case volume(appKey: String, step: Int)
  case toggleMute(appKey: String)
  case toggleAll
  case quit
}

/// The patch panel: sources on the left, outputs on the right. Pick a source
/// (click or ⏎), then pick an output, and that pair becomes a route. Pure: no
/// Core Audio, no terminal, so it is tested directly.
public struct TUIState: Equatable, Sendable {
  public enum Column: Equatable, Sendable { case sources, outputs }

  public private(set) var apps: [AppRow] = []
  public private(set) var devices: [DeviceRow] = []
  public private(set) var focus: Column = .sources
  public private(set) var sourceIndex = 0
  /// Output rows: 0 is "normal output" (no route); n is `devices[n - 1]`.
  public private(set) var outputIndex = 0
  /// The source picked on the left, waiting for an output.
  public private(set) var armed: String?
  public private(set) var showAll = false
  public var status = ""

  public init() {}

  public var outputCount: Int { devices.count + 1 }
  public var selectedApp: AppRow? { apps.indices.contains(sourceIndex) ? apps[sourceIndex] : nil }

  /// Swaps in fresh lists, keeping both cursors on the same app and output.
  public mutating func update(apps: [AppRow], devices: [DeviceRow]) {
    let appKey = selectedApp?.key
    let deviceUID =
      self.devices.indices.contains(outputIndex - 1) ? self.devices[outputIndex - 1].uid : nil
    self.apps = apps
    self.devices = devices
    sourceIndex = apps.firstIndex { $0.key == appKey } ?? min(sourceIndex, max(apps.count - 1, 0))
    if outputIndex > 0 {
      outputIndex =
        devices.firstIndex { $0.uid == deviceUID }.map { $0 + 1 } ?? min(outputIndex, devices.count)
    }
    if let armed, !apps.contains(where: { $0.key == armed }) {
      self.armed = nil
      focus = .sources
    }
  }

  public mutating func handle(_ key: Key) -> Command? {
    switch key {
    case .quit, .character("q"): return .quit
    case .character("a"):
      showAll.toggle()
      return .toggleAll
    case .tab: focus = focus == .sources ? .outputs : .sources
    case .escape, .left, .character("h"): cancel()
    case .up, .character("k"): move(by: -1)
    case .down, .character("j"): move(by: 1)
    case .right, .character("l"): if focus == .sources { return pickSource(sourceIndex) }
    case .enter, .character(" "):
      return focus == .sources ? pickSource(sourceIndex) : pickOutput(outputIndex)
    case .scroll(_, _, let delta): move(by: delta)
    case .backspace, .character("d"):
      return routedSelection.map { .unroute(appKey: $0) }
    case .character("+"), .character("="):
      return routedSelection.map { .volume(appKey: $0, step: 5) }
    case .character("-"), .character("_"):
      return routedSelection.map { .volume(appKey: $0, step: -5) }
    case .character("m"):
      return routedSelection.map { .toggleMute(appKey: $0) }
    default: break
    }
    return nil
  }

  /// The selected source's key, when the cursor is on the left and it's routed.
  /// Disconnect, volume and mute all act on it.
  private var routedSelection: String? {
    guard focus == .sources, let app = selectedApp, app.routedUID != nil else { return nil }
    return app.key
  }

  /// Arms a source and moves to the outputs, cursor on where it plays now.
  public mutating func pickSource(_ index: Int) -> Command? {
    guard apps.indices.contains(index) else { return nil }
    sourceIndex = index
    armed = apps[index].key
    focus = .outputs
    outputIndex = devices.firstIndex { $0.uid == apps[index].routedUID }.map { $0 + 1 } ?? 0
    status = "Now pick an output for \(apps[index].name)."
    return nil
  }

  /// Connects the armed source to this output (row 0 disconnects it).
  public mutating func pickOutput(_ index: Int) -> Command? {
    guard (0..<outputCount).contains(index) else { return nil }
    outputIndex = index
    guard let key = armed, let app = apps.first(where: { $0.key == key }) else {
      status = "Pick a source on the left first."
      return nil
    }
    armed = nil
    focus = .sources
    status = ""
    if index == 0 { return app.routedUID == nil ? nil : .unroute(appKey: key) }
    let uid = devices[index - 1].uid
    return uid == app.routedUID ? nil : .route(appKey: key, deviceUID: uid)
  }

  private mutating func cancel() {
    if armed != nil { status = "" }
    armed = nil
    focus = .sources
  }

  private mutating func move(by step: Int) {
    switch focus {
    case .sources: sourceIndex = min(max(sourceIndex + step, 0), max(apps.count - 1, 0))
    case .outputs: outputIndex = min(max(outputIndex + step, 0), outputCount - 1)
    }
  }
}
