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
  private let book = RouteBook()
  private var apps: [AudioApp] = []
  private var devices: [OutputDevice] = []
  private var sources: [any DispatchSourceProtocol] = []
  /// The last screen drawn, so a click can be matched to what was under it.
  private var frame: Frame?
  /// The terminal app whose audio-recording permission the taps depend on.
  private let host = HostApp.name()
  /// Always listed, whether or not they have touched audio yet.
  private let pinned = [AppGrouping.finder: "Finder"]

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
    AudioProcess.onListChange(queue: .main) { [weak self] in
      MainActor.assumeIsolated {
        self?.refresh()
        self?.draw()
      }
    }
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
    guard book.target(of: appKey) != nil else { return }
    let volume = book.volume(for: appKey)
    volume.set(perMille: volume.perMille + step * 10)
    volume.setMuted(false)
    state.status = "\(name(of: appKey)): \(volume.perMille / 10)%"
    refresh()
  }

  private func toggleMute(_ appKey: String) {
    guard book.target(of: appKey) != nil else { return }
    let volume = book.volume(for: appKey)
    volume.setMuted(!volume.isMuted)
    state.status = "\(name(of: appKey)) \(volume.isMuted ? "muted" : "unmuted")"
    refresh()
  }

  private func route(_ appKey: String, to uid: String) {
    guard let device = devices.first(where: { $0.uid == uid }) else { return }
    book.connect(appKey, to: uid)
    let failure = book.reconcile(apps: apps, devices: devices)
    let name = name(of: appKey)
    state.status =
      failure
      ?? (book.isWaiting(appKey)
        ? "\(name) → \(device.name), as soon as \(name) makes a sound" : "\(name) → \(device.name)")
    refresh()
  }

  private func unroute(_ appKey: String, reason: String) {
    guard book.target(of: appKey) != nil else { return }
    book.disconnect(appKey)
    state.status = "\(name(of: appKey)) \(reason)"
    refresh()
  }

  private func name(of appKey: String) -> String {
    apps.first { $0.key == appKey }?.name ?? appKey
  }

  /// Re-reads apps and devices, keeps each route pointed at what it should be,
  /// and rebuilds the rows. Runs every second and after every route change.
  ///
  /// `tick` marks the once-a-second call: only then are meters read and silence
  /// counted, so a refresh after a click doesn't count as a second of silence.
  private func refresh(tick: Bool = false) {
    do {
      let processes = try AudioProcess.all().filter { $0.pid != getpid() }
      apps = AppGrouping.apps(
        from: processes, name: AppNames.name(forKey:process:), host: AppNames.hostKey(for:),
        pinned: pinned)
      devices = try OutputDevice.all()
    } catch {
      state.status = "Couldn't read audio state: \(error)"
    }
    if let message = book.reconcile(apps: apps, devices: devices) { state.status = message }
    if tick, let advice = book.measure(apps: apps, host: host) { state.status = advice }

    let rows = apps.filter(isVisible).map { app in
      let volume = book.target(of: app.key) == nil ? nil : book.volume(for: app.key)
      return AppRow(
        key: app.key, name: app.name, isPlaying: app.isPlaying,
        routedUID: book.target(of: app.key), level: book.level(of: app.key),
        isSilent: book.isSilent(app.key), isWaiting: book.isWaiting(app.key),
        volume: (volume?.perMille ?? Volume.full) / 10, isMuted: volume?.isMuted ?? false)
    }
    let deviceRows = zip(devices, DeviceLabels.labels(for: devices)).map { device, label in
      DeviceRow(uid: device.uid, label: label, detail: DeviceLabels.detail(for: device))
    }
    state.update(apps: rows, devices: deviceRows)
  }

  /// Pinned, playing, routed, or a real app with a Dock icon. `a` shows everything.
  private func isVisible(_ app: AudioApp) -> Bool {
    state.showAll || pinned[app.key] != nil || app.isPlaying || book.target(of: app.key) != nil
      || AppNames.isRegularApp(key: app.key)
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
    book.stopAll()
    terminal.restore()
    exit(0)
  }
}
