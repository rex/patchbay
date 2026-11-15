/// One drawn screen, plus where each source and output landed so clicks can find them.
public struct Frame: Equatable, Sendable {
  public enum Target: Equatable, Sendable {
    case source(Int)
    /// 0 is "normal output"; n is device n - 1.
    case output(Int)
  }

  public let canvas: Canvas
  let sourceRows: [Int: Int]
  let outputRows: [Int: Int]
  let leftWidth: Int
  let rightStart: Int

  /// What a click at 0-based (x, y) landed on, if anything.
  public func target(x: Int, y: Int) -> Target? {
    if x < leftWidth, let index = sourceRows[y] { return .source(index) }
    if x >= rightStart, let index = outputRows[y] { return .output(index) }
    return nil
  }
}

/// Lays out the patch panel: sources left, outputs right, cables between.
public enum Screen {
  /// Cable colors, one per route: cyan, magenta, yellow, green, blue, bright red.
  static let palette: [UInt8] = [36, 35, 33, 32, 34, 91]
  static let armedColor: UInt8 = 33
  static let firstListRow = 3

  public static func render(_ state: TUIState, width: Int, height: Int) -> Frame {
    var canvas = Canvas(width: width, height: height)
    let leftWidth = min(max(width * 2 / 5, 18), 38)
    let rightStart = leftWidth + min(max(width - leftWidth - 34, 6), 18)
    let visible = max(height - firstListRow - 2, 1)
    header(state, on: &canvas, rightStart: rightStart)

    var colors: [String: UInt8] = [:]
    for app in state.apps where app.routedUID != nil {
      colors[app.key] = palette[colors.count % palette.count]
    }

    var sourceRows: [Int: Int] = [:]
    let sourceOffset = scrollOffset(state.sourceIndex, state.apps.count, visible)
    if state.apps.isEmpty {
      let empty =
        state.showAll
        ? "No app has opened audio yet." : "Nothing is playing. Press a for every app."
      canvas.put(empty, row: firstListRow, column: 3, limit: leftWidth - 4, style: Style(dim: true))
    }
    for (index, app) in state.apps.enumerated().dropFirst(sourceOffset).prefix(visible) {
      let row = firstListRow + index - sourceOffset
      sourceRows[row] = index
      drawSource(
        app, row: row, width: leftWidth, color: colors[app.key], armed: state.armed == app.key,
        on: &canvas)
      if state.focus == .sources, index == state.sourceIndex {
        canvas.restyle(row: row, columns: 0..<leftWidth) { $0.reverse = true }
      }
    }

    var outputRows: [Int: Int] = [:]
    var rowForUID: [String: Int] = [:]
    let outputOffset = scrollOffset(state.outputIndex, state.outputCount, visible)
    for index in Array(0..<state.outputCount).dropFirst(outputOffset).prefix(visible) {
      let row = firstListRow + index - outputOffset
      outputRows[row] = index
      if index == 0 {
        canvas.put("↩ Normal output", row: row, column: rightStart + 1, style: Style(dim: true))
      } else {
        let device = state.devices[index - 1]
        rowForUID[device.uid] = row
        let color = state.apps.first { $0.routedUID == device.uid }.flatMap { colors[$0.key] }
        drawOutput(
          device, row: row, column: rightStart + 1, width: width - rightStart - 1, color: color,
          on: &canvas)
      }
      if state.focus == .outputs, index == state.outputIndex {
        canvas.restyle(row: row, columns: rightStart..<width) { $0.reverse = true }
      }
    }

    let cables = sourceRows.sorted { $0.key < $1.key }.compactMap {
      row, index -> Connectors.Cable? in
      let app = state.apps[index]
      guard let uid = app.routedUID, let to = rowForUID[uid], let color = colors[app.key] else {
        return nil
      }
      return Connectors.Cable(sourceRow: row, outputRow: to, color: color)
    }
    Connectors.draw(cables, on: &canvas, from: leftWidth, to: rightStart - 1)
    if let armed = state.armed,
      let row = sourceRows.first(where: { state.apps[$0.value].key == armed })?.key
    {
      canvas.put("●╌╌", row: row, column: leftWidth, style: Style(color: armedColor, bold: true))
    }

    let statusStyle = Style(color: state.armed == nil ? nil : armedColor)
    canvas.put(state.status, row: height - 1, column: 1, limit: width - 2, style: statusStyle)
    return Frame(
      canvas: canvas, sourceRows: sourceRows, outputRows: outputRows, leftWidth: leftWidth,
      rightStart: rightStart)
  }

  static func header(_ state: TUIState, on canvas: inout Canvas, rightStart: Int) {
    canvas.put("patchbay", row: 0, column: 1, style: Style(bold: true))
    let help =
      "click a source, then an output · ↑↓←→ ⏎ · +/- volume · m mute · d disconnect · a "
      + (state.showAll ? "fewer apps" : "all apps") + " · q quit"
    canvas.put(
      help, row: 0, column: max(11, canvas.width - help.count - 1), style: Style(dim: true))
    canvas.put("SOURCES", row: 2, column: 3, style: Style(bold: true, dim: state.focus != .sources))
    canvas.put(
      "OUTPUTS", row: 2, column: rightStart + 1,
      style: Style(bold: true, dim: state.focus != .outputs))
  }

  static func drawSource(
    _ app: AppRow, row: Int, width: Int, color: UInt8?, armed: Bool, on canvas: inout Canvas
  ) {
    if app.isPlaying { canvas.put("▶", row: row, column: 1, style: Style(color: 32)) }
    // A routed source ends with "▮▮▯▯▯ 100% ": its level meter, then its volume.
    let suffixWidth = app.routedUID == nil ? 0 : 11
    let style = Style(color: armed ? armedColor : color, bold: armed || color != nil)
    canvas.put(app.name, row: row, column: 3, limit: width - 4 - suffixWidth, style: style)
    guard suffixWidth > 0 else { return }
    if app.isSilent {
      canvas.put("⚠ none", row: row, column: width - 11, style: Style(color: 91, bold: true))
    } else {
      canvas.put(meter(app.level), row: row, column: width - 11, style: Style(color: color))
    }
    canvas.put(
      volumeLabel(app), row: row, column: width - 5,
      style: app.isMuted ? Style(color: 91) : Style(color: color, bold: app.volume < 100))
  }

  /// " 45%", "100%", or "mute": always four characters.
  static func volumeLabel(_ app: AppRow) -> String {
    if app.isMuted { return "mute" }
    let percent = "\(app.volume)%"
    return String(repeating: " ", count: max(4 - percent.count, 0)) + percent
  }

  static func drawOutput(
    _ device: DeviceRow, row: Int, column: Int, width: Int, color: UInt8?, on canvas: inout Canvas
  ) {
    let detailWidth = device.detail.count <= width - 12 ? device.detail.count : 0
    canvas.put(
      device.label, row: row, column: column, limit: width - detailWidth - 2,
      style: Style(color: color, bold: color != nil))
    if detailWidth > 0 {
      canvas.put(
        device.detail, row: row, column: column + width - detailWidth - 1, style: Style(dim: true))
    }
  }

  /// Five cells, filled in proportion to the route's recent peak.
  static func meter(_ level: Float) -> String {
    let filled = min(5, max(0, Int((level * 5).rounded(.up))))
    return String(repeating: "▮", count: filled) + String(repeating: "▯", count: 5 - filled)
  }

  /// First row to show so the cursor stays near the middle of a scrolled list.
  static func scrollOffset(_ cursor: Int, _ count: Int, _ visible: Int) -> Int {
    max(0, min(cursor - visible / 2, count - visible))
  }
}
