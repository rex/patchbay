import Testing

@testable import PatchbayTUI

@Suite struct KeyTests {
  @Test func arrowsEnterAndControlKeys() {
    let bytes: [UInt8] = [0x1B, 0x5B, 0x41, 0x1B, 0x4F, 0x42, 0x0D, 0x09, 0x7F, 0x03]
    #expect(Key.parse(bytes) == [.up, .down, .enter, .tab, .backspace, .quit])
  }

  @Test func loneEscapeAndPrintableCharacters() {
    #expect(Key.parse([0x1B]) == [.escape])
    #expect(Key.parse(Array("qa".utf8)) == [.character("q"), .character("a")])
  }

  @Test func sgrMouseClickIsZeroBased() {
    #expect(Key.parse(Array("\u{1B}[<0;12;5M".utf8)) == [.click(x: 11, y: 4)])
  }

  @Test func mouseReleasesAndOtherButtonsAreIgnored() {
    #expect(Key.parse(Array("\u{1B}[<0;12;5m".utf8)).isEmpty)
    #expect(Key.parse(Array("\u{1B}[<2;12;5M".utf8)).isEmpty)
  }

  @Test func scrollWheelKeepsWhereItHappened() {
    #expect(
      Key.parse(Array("\u{1B}[<64;3;2M\u{1B}[<65;3;2M".utf8)) == [
        .scroll(x: 2, y: 1, delta: -1), .scroll(x: 2, y: 1, delta: 1),
      ])
  }

  @Test func aClickAndAKeyInOneRead() {
    #expect(Key.parse(Array("\u{1B}[<0;3;4Mq".utf8)) == [.click(x: 2, y: 3), .character("q")])
  }
}
