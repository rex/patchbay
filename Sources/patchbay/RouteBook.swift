import PatchbayCore

/// What the person asked for (this app → that output) versus what is running.
///
/// A wish waits while its app has no audio processes (Finder before anything has
/// previewed) and goes live the moment one appears. It is rebuilt whenever the
/// app's processes change (a QuickLook preview starting, a browser helper
/// spawning), and ends only when the person disconnects it, the app quits, or the
/// output goes away. Volumes are kept per app for the whole session.
@MainActor
final class RouteBook {
  private var wishes: [String: String] = [:]
  private var routes: [String: Route] = [:]
  private var volumes: [String: Volume] = [:]
  private var levels: [String: Float] = [:]
  private var watches: [String: SilenceWatch] = [:]

  /// The output an app is routed to, live or waiting.
  func target(of key: String) -> String? { wishes[key] }
  /// Routed, but nothing to tap yet: the app has no audio processes.
  func isWaiting(_ key: String) -> Bool { wishes[key] != nil && routes[key] == nil }
  func level(of key: String) -> Float { levels[key] ?? 0 }
  func isSilent(_ key: String) -> Bool { watches[key]?.isSilent ?? false }

  func volume(for key: String) -> Volume {
    if let volume = volumes[key] { return volume }
    let volume = Volume()
    volumes[key] = volume
    return volume
  }

  func connect(_ key: String, to uid: String) { wishes[key] = uid }

  func disconnect(_ key: String) {
    wishes[key] = nil
    routes.removeValue(forKey: key)?.stop()
    levels[key] = nil
    watches[key] = nil
  }

  /// Makes the running routes match the wishes. Returns a message worth showing,
  /// if anything ended or failed.
  func reconcile(apps: [AudioApp], devices: [OutputDevice]) -> String? {
    var message: String?
    for (key, uid) in wishes {
      let app = apps.first { $0.key == key }
      let name = app?.name ?? routes[key]?.app.name ?? key
      guard let device = devices.first(where: { $0.uid == uid }) else {
        let output = routes[key]?.device.name ?? "Its output"
        disconnect(key)
        message = "\(output) went away; \(name) is back on its normal output"
        continue
      }
      guard let app else {
        disconnect(key)
        message = "\(name) quit"
        continue
      }
      let wanted = Set(app.processes.map(\.objectID))
      if let route = routes[key], route.device.uid == uid,
        Set(route.app.processes.map(\.objectID)) == wanted
      {
        continue
      }
      routes.removeValue(forKey: key)?.stop()
      watches[key] = nil
      guard !wanted.isEmpty else { continue }  // wait for the app to make a sound
      do {
        routes[key] = try Route(app: app, device: device, volume: volume(for: key))
      } catch {
        disconnect(key)
        message = "Couldn't route \(app.name): \(error)"
      }
    }
    return message
  }

  /// Once a second: reads each live route's meter, and returns the permission
  /// advice the first time a playing app's route turns out silent.
  func measure(apps: [AudioApp], host: String?) -> String? {
    var advice: String?
    for (key, route) in routes {
      let peak = route.stats.take().peak
      levels[key] = peak
      let playing = apps.first { $0.key == key }?.isPlaying ?? false
      if watches[key, default: SilenceWatch()].observe(peak: peak, appIsPlaying: playing) {
        advice = SilenceWatch.advice(appName: route.app.name, host: host)
      }
    }
    return advice
  }

  /// Stops every route; each app goes back to its normal output.
  func stopAll() {
    for route in routes.values { route.stop() }
    routes.removeAll()
  }
}
