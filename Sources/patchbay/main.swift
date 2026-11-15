// patchbay: send each app's audio to the output device you pick.
// `patchbay list` prints what can be routed; the TUI comes next (see TASK_STATE.md).
import Foundation
import PatchbayCore

func list() throws {
  print("Output devices")
  for device in try OutputDevice.all() {
    let mark = device.isDefault ? "*" : " "
    let rate = String(format: "%.1f kHz", device.sampleRate / 1000)
    print("  \(mark) \(device.name)  [\(rate)]  \(device.uid)")
  }
  print("\nApps (▶ = playing now)")
  let apps = AppGrouping.apps(from: try AudioProcess.all(), name: AppNames.name(forKey:process:))
  for app in apps {
    let mark = app.isPlaying ? "▶" : " "
    let pids = app.processes.map { String($0.pid) }.joined(separator: ",")
    print("  \(mark) \(app.name)  (\(app.key), pid \(pids))")
  }
}

/// First app or device whose name or ID contains `query`, ignoring case.
func pick<T>(_ query: String, from items: [T], _ fields: (T) -> [String]) -> T? {
  items.first { fields($0).contains { $0.localizedCaseInsensitiveContains(query) } }
}

/// `patchbay route <app> <device> [seconds]`: route until Ctrl-C (or for `seconds`).
func route(_ appQuery: String, _ deviceQuery: String, seconds: Int?) throws {
  let apps = AppGrouping.apps(from: try AudioProcess.all(), name: AppNames.name(forKey:process:))
  guard let app = pick(appQuery, from: apps, { [$0.name, $0.key] }) else {
    throw CLIError("no app matches \"\(appQuery)\"; try `patchbay list`")
  }
  guard let device = pick(deviceQuery, from: try OutputDevice.all(), { [$0.name, $0.uid] }) else {
    throw CLIError("no output device matches \"\(deviceQuery)\"; try `patchbay list`")
  }
  let route = try Route(app: app, device: device)
  let format = try route.tapFormat()
  print("routing \(app.name) → \(device.name)")
  print(
    "  tap \(format.mChannelsPerFrame)ch @ \(Int(format.mSampleRate)) Hz,"
      + " device @ \(Int(device.sampleRate)) Hz. Ctrl-C stops.")

  let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  signal(SIGINT, SIG_IGN)
  interrupt.setEventHandler {
    route.stop()
    print("\nstopped; \(app.name) is back on its normal output")
    exit(0)
  }
  interrupt.resume()

  var elapsed = 0
  let timer = DispatchSource.makeTimerSource(queue: .main)
  timer.schedule(deadline: .now() + 1, repeating: 1)
  timer.setEventHandler {
    elapsed += 1
    let (cycles, peak, channels) = route.stats.take()
    print(
      String(
        format: "  %3ds  io cycles %6d  tap ch %d  peak %.3f  buffered %5d frames",
        elapsed, cycles, channels, peak, route.bufferedFrames))
    if let seconds, elapsed >= seconds {
      route.stop()
      exit(0)
    }
  }
  timer.resume()
  dispatchMain()
}

struct CLIError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
  switch arguments.first {
  case "list":
    try list()
  case "route" where arguments.count >= 3:
    try route(arguments[1], arguments[2], seconds: arguments.count > 3 ? Int(arguments[3]) : nil)
  default:
    print("usage: patchbay list\n       patchbay route <app> <device> [seconds]")
    exit(arguments.isEmpty ? 0 : 64)
  }
} catch {
  FileHandle.standardError.write(Data("patchbay: \(error)\n".utf8))
  exit(1)
}
