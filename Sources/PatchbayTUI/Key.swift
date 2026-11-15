/// One input event from patchbay's own terminal: a key, or a mouse click the
/// terminal reports back (SGR mouse mode, enabled only while the TUI runs).
///
/// patchbay never installs an event tap. It sees keys and clicks only when its
/// own terminal window has focus and passes them along on standard input.
public enum Key: Equatable, Sendable {
  case up, down, left, right, tab, enter, escape, backspace
  /// Ctrl-C or Ctrl-D.
  case quit
  case character(Character)
  /// Left-button press at a 0-based column and row.
  case click(x: Int, y: Int)
  /// Scroll wheel at a 0-based column and row: -1 is up (away), +1 is down.
  case scroll(x: Int, y: Int, delta: Int)

  /// Decodes one read from the terminal; one read can hold several events.
  public static func parse(_ bytes: [UInt8]) -> [Key] {
    var keys: [Key] = []
    var index = 0
    while index < bytes.count {
      if let (key, length) = escapeSequence(bytes, at: index) {
        if let key { keys.append(key) }
        index += length
        continue
      }
      switch bytes[index] {
      case 0x1B: keys.append(.escape)
      case 0x09: keys.append(.tab)
      case 0x0D, 0x0A: keys.append(.enter)
      case 0x7F, 0x08: keys.append(.backspace)
      case 0x03, 0x04: keys.append(.quit)
      case 0x20..<0x7F: keys.append(.character(Character(UnicodeScalar(bytes[index]))))
      default: break
      }
      index += 1
    }
    return keys
  }

  /// `ESC [ A` arrows (or `ESC O A`), and `ESC [ < b ; x ; y M` mouse reports.
  /// Returns the decoded key (nil for ones patchbay ignores) and bytes consumed.
  private static func escapeSequence(_ bytes: [UInt8], at index: Int) -> (Key?, Int)? {
    guard bytes[index] == 0x1B, index + 2 < bytes.count,
      bytes[index + 1] == 0x5B || bytes[index + 1] == 0x4F
    else { return nil }
    let arrows: [UInt8: Key] = [0x41: .up, 0x42: .down, 0x43: .right, 0x44: .left]
    if let arrow = arrows[bytes[index + 2]] { return (arrow, 3) }
    guard bytes[index + 2] == 0x3C else { return (nil, 3) }  // not "<": skip it

    var end = index + 3
    while end < bytes.count, bytes[end] != 0x4D, bytes[end] != 0x6D { end += 1 }
    guard end < bytes.count else { return (nil, bytes.count - index) }
    let fields = String(decoding: bytes[(index + 3)..<end], as: UTF8.self)
      .split(separator: ";").compactMap { Int($0) }
    let length = end - index + 1
    guard fields.count == 3, bytes[end] == 0x4D else { return (nil, length) }  // press only
    switch fields[0] {
    case 0: return (.click(x: fields[1] - 1, y: fields[2] - 1), length)
    case 64: return (.scroll(x: fields[1] - 1, y: fields[2] - 1, delta: -1), length)
    case 65: return (.scroll(x: fields[1] - 1, y: fields[2] - 1, delta: 1), length)
    default: return (nil, length)
    }
  }
}
