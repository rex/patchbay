import PatchbayCore
import Testing

@testable import PatchbayTUI

@Suite struct ScreenTests {
  private func routedPanel() -> TUIState {
    var state = TUIState()
    state.update(
      apps: [
        AppRow(key: "a", name: "Google Chrome", isPlaying: true, routedUID: "spk", level: 0.5),
        AppRow(key: "b", name: "Finder", isPlaying: false),
      ],
      devices: [
        DeviceRow(uid: "pods", label: "AirPods", detail: "48 kHz"),
        DeviceRow(uid: "spk", label: "MacBook Pro Speakers", detail: "44.1 kHz · default"),
      ])
    return state
  }

  @Test func drawsBothColumnsAndACableBetweenThem() {
    let frame = Screen.render(routedPanel(), width: 100, height: 12)
    let text = frame.canvas.text
    #expect(text[2].contains("SOURCES") && text[2].contains("OUTPUTS"))
    // Chrome sits on row 3; its output (speakers) is output row 2, screen row 5.
    #expect(
      text[3].contains("Google Chrome") && text[3].contains("▮▮▮▯▯") && text[3].contains("●─"))
    #expect(text[4].contains("│"))
    #expect(text[5].contains("─●") && text[5].contains("MacBook Pro Speakers"))
    #expect(text[5].hasSuffix("44.1 kHz · default"))
  }

  @Test func clicksLandOnWhatWasDrawnThere() {
    let frame = Screen.render(routedPanel(), width: 100, height: 12)
    #expect(frame.target(x: 5, y: 4) == .source(1))
    #expect(frame.target(x: 95, y: 3) == .output(0))
    #expect(frame.target(x: 95, y: 4) == .output(1))
    #expect(frame.target(x: 45, y: 4) == nil)  // the gutter
    #expect(frame.target(x: 5, y: 0) == nil)  // the header
  }

  @Test func theFrameFillsTheTerminalExactly() {
    let canvas = Screen.render(routedPanel(), width: 70, height: 9).canvas
    #expect(canvas.cells.count == 9)
    #expect(canvas.cells.allSatisfy { $0.count == 70 })
  }

  @Test func crossingCablesMergeIntoACross() {
    var canvas = Canvas(width: 12, height: 4)
    Connectors.draw(
      [.init(sourceRow: 0, outputRow: 3, color: 36), .init(sourceRow: 2, outputRow: 2, color: 35)],
      on: &canvas, from: 0, to: 11)
    #expect(canvas.text[2].contains("┼"))
    #expect(canvas.text[0].hasPrefix("●") && canvas.text[3].hasSuffix("●"))
  }

  @Test func duplicateDeviceNamesGetNumbers() {
    let devices = [
      OutputDevice(id: 1, uid: "u1", name: "LG ULTRAGEAR", sampleRate: 48_000, isDefault: false),
      OutputDevice(id: 2, uid: "u2", name: "Scarlett", sampleRate: 44_100, isDefault: true),
      OutputDevice(id: 3, uid: "u3", name: "LG ULTRAGEAR", sampleRate: 48_000, isDefault: false),
    ]
    #expect(
      DeviceLabels.labels(for: devices) == ["LG ULTRAGEAR (1)", "Scarlett", "LG ULTRAGEAR (2)"])
    #expect(DeviceLabels.detail(for: devices[1]) == "44.1 kHz · default")
    #expect(DeviceLabels.detail(for: devices[0]) == "48 kHz")
  }

  @Test func longNamesAreCutWithAnEllipsis() {
    var canvas = Canvas(width: 10, height: 1)
    canvas.put("A very long app name", row: 0, column: 0, limit: 6)
    #expect(canvas.text[0] == "A ver…")
  }
}
