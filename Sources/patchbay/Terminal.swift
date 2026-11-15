import Darwin
import PatchbayTUI

/// patchbay's own terminal: raw keystrokes in, full-screen frames out.
///
/// Raw mode affects this terminal only. Nothing here hooks system-wide input.
final class Terminal {
  private var original = termios()
  private var active = false

  /// Raw input (no echo, no line buffering, no signal keys), alternate screen,
  /// hidden cursor, and click reporting (the terminal sends clicks inside its own
  /// window as escape sequences on stdin). `restore()` puts all of it back.
  func enter() throws {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
      throw TerminalError("patchbay's TUI needs an interactive terminal; try `patchbay list`")
    }
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
      throw TerminalError("can't read terminal settings")
    }
    var raw = original
    raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
    raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
    guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
      throw TerminalError("can't switch the terminal to raw mode")
    }
    active = true
    write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1006h")
  }

  /// Puts the terminal back the way it was. Safe to call twice.
  func restore() {
    guard active else { return }
    write("\u{1B}[?1006l\u{1B}[?1000l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    active = false
  }

  var size: (width: Int, height: Int) {
    var window = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0, window.ws_col > 0, window.ws_row > 0
    else {
      return (80, 24)
    }
    return (Int(window.ws_col), Int(window.ws_row))
  }

  /// Redraws the whole screen in one write, so it never flickers half-drawn.
  /// Emits a style escape only where the style changes.
  func draw(_ canvas: Canvas) {
    var current = Style()
    var output = "\u{1B}[H" + current.escape
    for (index, row) in canvas.cells.enumerated() {
      for cell in row {
        if cell.style != current {
          current = cell.style
          output += current.escape
        }
        output.append(cell.character)
      }
      if index < canvas.height - 1 { output += "\r\n" }
    }
    write(output + "\u{1B}[0m")
  }

  /// Reads whatever bytes are waiting on standard input (nil at end of input).
  func readBytes() -> [UInt8]? {
    var buffer = [UInt8](repeating: 0, count: 64)
    let count = read(STDIN_FILENO, &buffer, buffer.count)
    return count > 0 ? Array(buffer.prefix(count)) : nil
  }

  private func write(_ text: String) {
    var bytes = Array(text.utf8)
    var offset = 0
    while offset < bytes.count {
      let written = bytes.withUnsafeMutableBytes {
        Darwin.write(STDOUT_FILENO, $0.baseAddress! + offset, $0.count - offset)
      }
      guard written > 0 else { return }
      offset += written
    }
  }
}

struct TerminalError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
