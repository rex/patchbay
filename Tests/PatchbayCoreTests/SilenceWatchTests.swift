import Testing

@testable import PatchbayCore

/// Feeds `seconds` one at a time and returns what `observe` said each time.
private func feed(
  _ watch: inout SilenceWatch, _ seconds: [(peak: Float, playing: Bool)]
) -> [Bool] {
  seconds.map { watch.observe(peak: $0.peak, appIsPlaying: $0.playing) }
}

@Suite struct SilenceWatchTests {
  @Test func warnsOnceAfterThreeSilentSecondsWhilePlaying() {
    var watch = SilenceWatch(threshold: 3)
    let said = feed(&watch, Array(repeating: (0, true), count: 4))
    #expect(said == [false, false, true, false])  // speaks up on the third second, once
    #expect(watch.isSilent)
  }

  @Test func anySoundResetsIt() {
    var watch = SilenceWatch(threshold: 2)
    _ = feed(&watch, [(0, true), (0, true)])
    #expect(watch.isSilent)
    _ = feed(&watch, [(0.01, true)])
    #expect(!watch.isSilent)
    #expect(watch.silentSeconds == 0)
  }

  @Test func silenceFromAnIdleAppIsNotSuspicious() {
    var watch = SilenceWatch(threshold: 1)
    #expect(feed(&watch, [(0, false)]) == [false])
    #expect(!watch.isSilent)
  }

  @Test func adviceNamesTheTerminalOrFallsBack() {
    let named = SilenceWatch.advice(appName: "Chrome", host: "iTerm")
    #expect(named.contains("allow iTerm in System Settings"))
    #expect(SilenceWatch.advice(appName: "Chrome", host: nil).contains("allow your terminal app"))
  }

  @Test(arguments: [
    ("/Applications/iTerm.app/Contents/MacOS/iTerm2", "iTerm"),
    ("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", "Terminal"),
    ("/Applications/Ghostty.app/Contents/MacOS/ghostty", "Ghostty"),
  ])
  func hostAppNameComesFromTheBundle(path: String, expected: String) {
    #expect(HostApp.appName(fromExecutablePath: path) == expected)
  }

  @Test func plainExecutablesAreNotApps() {
    #expect(HostApp.appName(fromExecutablePath: "/bin/zsh") == nil)
  }
}
