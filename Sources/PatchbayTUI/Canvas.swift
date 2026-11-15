/// How one cell is drawn. `color` is an ANSI foreground code (31–37, 90–97).
public struct Style: Equatable, Sendable {
  public var color: UInt8?
  public var bold = false
  public var dim = false
  public var reverse = false

  public init(color: UInt8? = nil, bold: Bool = false, dim: Bool = false, reverse: Bool = false) {
    self.color = color
    self.bold = bold
    self.dim = dim
    self.reverse = reverse
  }

  /// The SGR escape that switches the terminal to this style.
  public var escape: String {
    var codes = ["0"]
    if bold { codes.append("1") }
    if dim { codes.append("2") }
    if reverse { codes.append("7") }
    if let color { codes.append(String(color)) }
    return "\u{1B}[" + codes.joined(separator: ";") + "m"
  }
}

public struct Cell: Equatable, Sendable {
  public var character: Character
  public var style: Style
}

/// A fixed-size grid of styled characters: the whole screen, built off-terminal.
public struct Canvas: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var cells: [[Cell]]

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    cells = Array(
      repeating: Array(repeating: Cell(character: " ", style: Style()), count: self.width),
      count: self.height)
  }

  /// The screen as plain text, trailing spaces trimmed. For tests and debugging.
  public var text: [String] {
    cells.map { row in
      var line = String(row.map(\.character))
      while line.last == " " { line.removeLast() }
      return line
    }
  }

  /// Writes `text` at (row, column), cut to `limit` characters with an ellipsis.
  mutating func put(
    _ text: String, row: Int, column: Int, limit: Int? = nil, style: Style = Style()
  ) {
    guard (0..<height).contains(row), column < width else { return }
    let room = min(limit ?? width, width - max(column, 0))
    guard room > 0 else { return }
    let fitted = text.count > room ? String(text.prefix(room - 1)) + "…" : text
    for (offset, character) in fitted.enumerated() where column + offset >= 0 {
      cells[row][column + offset] = Cell(character: character, style: style)
    }
  }

  mutating func set(_ character: Character, row: Int, column: Int, style: Style = Style()) {
    guard (0..<height).contains(row), (0..<width).contains(column) else { return }
    cells[row][column] = Cell(character: character, style: style)
  }

  /// Applies `change` to the styles of columns `range` in `row`.
  mutating func restyle(row: Int, columns range: Range<Int>, _ change: (inout Style) -> Void) {
    guard (0..<height).contains(row) else { return }
    for column in range.clamped(to: 0..<width) { change(&cells[row][column].style) }
  }
}
