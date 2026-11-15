import Darwin
import Dispatch
import PatchbayCore
import PatchbayTUI

/// The interactive app: keeps the lists live, turns commands into routes, and
/// tears every route down on the way out.
@MainActor
final class Controller {
  private let terminal = Terminal()
  private var state = TUIState()
  private var routes: [String: Route] = [:]
  private var apps: [AudioApp] = []
  private var devices: [OutputDevice] = []
  private var sources: [any DispatchSourceProtocol] = []
  /// The last screen drawn, so a click can be matched to what was under it.
  private var frame: Frame?
  /// Per route: last second's peak, and whether it has gone suspiciously silent.
  private var levels: [String: Float] = [:]
  private var watches: [String: SilenceWatch] = [:]
  /// Each app's volume, kept for the session so rerouting it keeps its level.
  private var volumes: [String: Volume] = [:]
  /// The terminal app whose audio-recording permission the taps depend on.
  private let host = HostApp.name()

  func run() throws -> Never {
    try terminal.enter()
    refresh()
    draw()

    let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
    input.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readInput() } }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.refresh(tick: true)
        self?.draw()
      }
    }
    sources = [input, timer]
    for signalNumber in [SIGWINCH, SIGINT, SIGTERM, SIGHUP] {
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
      source.setEventHandler { [weak self] in
        MainActor.assumeIsolated {
          if signalNumber == SIGWINCH { self?.draw() } else { self?.quit() }
        }
      }
      sources.append(source)
    }
    for source in sources { source.resume() }
    dispatchMain()
  }

  private func readInput() {
    guard let bytes = terminal.readBytes() else { quit() }
    for key in Key.parse(bytes) {
      guard let command = command(for: key) else { continue }
      switch command {
      case .quit: quit()
      case .toggleAll: refresh()
      case .route(let appKey, let uid): route(appKey, to: uid)
      case .unroute(let appKey): unroute(appKey, reason: "is back on its normal output")
      case .volume(let appKey, let step): changeVolume(appKey, by: step)
      case .toggleMute(let appKey): toggleMute(appKey)
      }
    }
    draw()
  }

  /// Clicks go to whatever was drawn under them. The scroll wheel over a routed
  /// source turns its volume; anywhere else it moves the cursor.
  private func command(for key: Key) -> Command? {
    switch key {
    case .click(let x, let y):
      switch frame?.target(x: x, y: y) {
      case .source(let index): return state.pickSource(index)
      case .output(let index): return state.pickOutput(index)
      case nil: return nil
      }
    case .scroll(let x, let y, let delta):
      if case .source(let index)? = frame?.target(x: x, y: y), state.apps.indices.contains(index),
        state.apps[index].routedUID != nil
      {
        return .volume(appKey: state.apps[index].key, step: -5 * delta)
      }
      return state.handle(key)
    default:
      return state.handle(key)
    }
  }

  /// Nudges a route's volume. Changing the level also unmutes it.
  private func changeVolume(_ appKey: String, by step: Int) {
    guard let route = routes[appKey] else { return }
    route.volume.set(perMille: route.volume.perMille + step * 10)
    route.volume.setMuted(false)
    state.status = "\(route.app.name): \(route.volume.perMille / 10)%"
    refresh()
  }

  private func toggleMute(_ appKey: String) {
    guard let route = routes[appKey] else { return }
    route.volume.setMuted(!route.volume.isMuted)
    state.status = "\(route.app.name) \(route.volume.isMuted ? "muted" : "unmuted")"
    refresh()
  }

  private func route(_ appKey: String, to uid: String) {
    guard let app = apps.first(where: { $0.key == appKey }),
      let device = devices.first(where: { $0.uid == uid })
    else { return }
    routes.removeValue(forKey: appKey)?.stop()
    watches[appKey] = nil
    do {
      let volume = volumes[appKey] ?? Volume()
      volumes[appKey] = volume
      routes[appKey] = try Route(app: app, device: device, volume: volume)
      state.status = "\(app.name) → \(device.name)"
    } catch {
      state.status = "Couldn't route \(app.name): \(error)"
    }
    refresh()
  }

  private func unroute(_ appKey: String, reason: String) {
    guard let route = routes.removeValue(forKey: appKey) else { return }
    route.stop()
    state.status = "\(route.app.name) \(reason)"
    refresh()
  }

  /// Re-reads apps and devices, keeps each route pointed at what it should be,
  /// and rebuilds the rows. Runs every second and after every route change.
  ///
  /// `tick` marks the once-a-second call: only then are meters read and silence
  /// counted, so a refresh after a click doesn't count as a second of silence.
  private func refresh(tick: Bool = false) {
    do {
      apps = AppGrouping.apps(from: try AudioProcess.all(), name: AppNames.name(forKey:process:))
        .filter { app in !app.processes.contains { $0.pid == getpid() } }
      devices = try OutputDevice.all()
    } catch {
      state.status = "Couldn't read audio state: \(error)"
    }
    reconcileRoutes()
    if tick { measureRoutes() }

    let rows = apps.filter(isVisible).map { app in
      AppRow(
        key: app.key, name: app.name, isPlaying: app.isPlaying,
        routedUID: routes[app.key]?.device.uid, level: levels[app.key] ?? 0,
        isSilent: watches[app.key]?.isSilent ?? false,
        volume: (routes[app.key]?.volume.perMille ?? Volume.full) / 10,
        isMuted: routes[app.key]?.volume.isMuted ?? false)
    }
    let deviceRows = zip(devices, DeviceLabels.labels(for: devices)).map { device, label in
      DeviceRow(uid: device.uid, label: label, detail: DeviceLabels.detail(for: device))
    }
    state.update(apps: rows, devices: deviceRows)
  }

  /// Drops routes whose app or device went away, and rebuilds a route when its app
  /// gains or loses processes (a browser starting a new audio helper, say).
  private func reconcileRoutes() {
    for (key, route) in routes {
      guard devices.contains(where: { $0.uid == route.device.uid }) else {
        unrouteQuietly(
          key,
          status:
            "\(route.device.name) disconnected; \(route.app.name) is back on its normal output")
        continue
      }
      guard let app = apps.first(where: { $0.key == key }) else {
        unrouteQuietly(key, status: "\(route.app.name) quit")
        continue
      }
      let before = Set(route.app.processes.map(\.objectID))
      if before != Set(app.processes.map(\.objectID)) {
        route.stop()
        watches[key] = nil
        routes[key] = try? Route(app: app, device: route.device, volume: route.volume)
      }
    }
  }

  /// Reads each route's meter for the last second, and warns once when a route of
  /// a playing app has carried nothing but silence (see `SilenceWatch`).
  private func measureRoutes() {
    levels = levels.filter { routes[$0.key] != nil }
    watches = watches.filter { routes[$0.key] != nil }
    for (key, route) in routes {
      let peak = route.stats.take().peak
      levels[key] = peak
      let playing = apps.first { $0.key == key }?.isPlaying ?? false
      if watches[key, default: SilenceWatch()].observe(peak: peak, appIsPlaying: playing) {
        state.status = SilenceWatch.advice(appName: route.app.name, host: host)
      }
    }
  }

  private func unrouteQuietly(_ key: String, status: String) {
    routes.removeValue(forKey: key)?.stop()
    state.status = status
  }

  /// Playing, routed, or a real app with a Dock icon. `a` shows everything.
  private func isVisible(_ app: AudioApp) -> Bool {
    state.showAll || app.isPlaying || routes[app.key] != nil || AppNames.isRegularApp(key: app.key)
  }

  private func draw() {
    let size = terminal.size
    let frame = Screen.render(state, width: size.width, height: size.height)
    self.frame = frame
    terminal.draw(frame.canvas)
  }

  /// Stops every route (each app goes back to its normal output), restores the terminal.
  private func quit() -> Never {
    for source in sources { source.cancel() }
    for route in routes.values { route.stop() }
    routes.removeAll()
    terminal.restore()
    exit(0)
  }
}
