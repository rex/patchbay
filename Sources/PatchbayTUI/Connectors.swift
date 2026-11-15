/// Patch cables: box-drawing lines across the gutter between the two columns.
///
/// Each cable gets its own vertical lane, so cables never share a vertical run.
/// Where one cable's horizontal crosses another's vertical, the cell's directions
/// merge into ┼, so crossings read correctly.
enum Connectors {
  struct Cable: Equatable {
    let sourceRow: Int
    let outputRow: Int
    let color: UInt8
  }

  /// Directions a cell's line runs in.
  struct Directions: OptionSet {
    let rawValue: UInt8
    static let north = Directions(rawValue: 1)
    static let south = Directions(rawValue: 2)
    static let east = Directions(rawValue: 4)
    static let west = Directions(rawValue: 8)
  }

  /// Draws `cables` in columns `start...end`, with a ● plug at each end.
  static func draw(_ cables: [Cable], on canvas: inout Canvas, from start: Int, to end: Int) {
    guard end - start >= 2 else { return }
    var cells: [Int: [Int: (Directions, UInt8)]] = [:]
    func add(_ row: Int, _ column: Int, _ directions: Directions, _ color: UInt8) {
      let existing = cells[row]?[column]?.0 ?? []
      cells[row, default: [:]][column] = (existing.union(directions), color)
    }

    for (index, cable) in cables.enumerated() {
      let lane = start + 1 + (index + 1) * (end - start - 1) / (cables.count + 1)
      let (from, to) = (cable.sourceRow, cable.outputRow)
      for column in start..<lane { add(from, column, [.east, .west], cable.color) }
      if from == to {
        for column in lane...end { add(from, column, [.east, .west], cable.color) }
        continue
      }
      let down = to > from
      add(from, lane, [.west, down ? .south : .north], cable.color)
      for row in (min(from, to) + 1)..<max(from, to) {
        add(row, lane, [.north, .south], cable.color)
      }
      add(to, lane, [down ? .north : .south, .east], cable.color)
      for column in (lane + 1)...end { add(to, column, [.east, .west], cable.color) }
    }

    for (row, columns) in cells {
      for (column, (directions, color)) in columns {
        canvas.set(glyph(directions), row: row, column: column, style: Style(color: color))
      }
    }
    for cable in cables {
      canvas.set(
        "●", row: cable.sourceRow, column: start, style: Style(color: cable.color, bold: true))
      canvas.set(
        "●", row: cable.outputRow, column: end, style: Style(color: cable.color, bold: true))
    }
  }

  static func glyph(_ directions: Directions) -> Character {
    switch directions {
    case [.east, .west], [.east], [.west]: "─"
    case [.north, .south], [.north], [.south]: "│"
    case [.south, .west]: "┐"
    case [.north, .east]: "└"
    case [.north, .west]: "┘"
    case [.south, .east]: "┌"
    case [.north, .south, .east]: "├"
    case [.north, .south, .west]: "┤"
    case [.east, .west, .south]: "┬"
    case [.east, .west, .north]: "┴"
    default: "┼"
    }
  }
}
