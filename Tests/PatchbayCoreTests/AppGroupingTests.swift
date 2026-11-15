import CoreAudio
import Testing

@testable import PatchbayCore

@Suite struct AppGroupingTests {
  @Test(arguments: [
    ("com.google.Chrome.helper", "com.google.Chrome"),
    ("com.google.Chrome.helper.Renderer", "com.google.Chrome"),
    ("com.tinyspeck.slackmacgap.helper", "com.tinyspeck.slackmacgap"),
    ("com.microsoft.edgemac.helper.GPU", "com.microsoft.edgemac"),
    ("com.apple.finder", "com.apple.finder"),
    ("com.apple.WebKit.GPU", "com.apple.WebKit.GPU"),
    ("helper", "helper"),
    ("", ""),
  ])
  func appKeyStripsHelperSuffixes(bundleID: String, expected: String) {
    #expect(AppGrouping.appKey(forBundleID: bundleID) == expected)
  }

  @Test func helpersGroupUnderTheirAppAndPlayingAppsComeFirst() {
    let processes = [
      AudioProcess(objectID: 1, pid: 10, bundleID: "com.apple.finder", isRunningOutput: false),
      AudioProcess(
        objectID: 2, pid: 30, bundleID: "com.google.Chrome.helper", isRunningOutput: true),
      AudioProcess(objectID: 3, pid: 20, bundleID: "com.google.Chrome", isRunningOutput: false),
      AudioProcess(objectID: 4, pid: 40, bundleID: "", isRunningOutput: false),
    ]
    let apps = AppGrouping.apps(from: processes) { key, _ in key }

    #expect(apps.map(\.key) == ["com.google.Chrome", "com.apple.finder", "pid:40"])
    #expect(apps[0].isPlaying)
    #expect(apps[0].processes.map(\.pid) == [20, 30])
    #expect(!apps[1].isPlaying)
  }

  @Test func processesWithoutABundleStayApart() {
    let processes = [
      AudioProcess(objectID: 1, pid: 7, bundleID: "", isRunningOutput: true),
      AudioProcess(objectID: 2, pid: 8, bundleID: "", isRunningOutput: true),
    ]
    let apps = AppGrouping.apps(from: processes) { key, _ in key }
    #expect(Set(apps.map(\.key)) == ["pid:7", "pid:8"])
  }

  @Test func halErrorsReadAsFourCharacterCodes() {
    let status = OSStatus(bitPattern: 0x7768_6F3F)  // 'who?'
    #expect(HALError.fourCC(status) == "'who?'")
    #expect(HALError.fourCC(-50) == "-50")
  }
}
