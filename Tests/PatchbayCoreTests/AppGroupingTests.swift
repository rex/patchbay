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
    ("com.apple.quicklook.QuickLookUIService", "com.apple.finder"),
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

  @Test func aProcessWorkingForAnAppGroupsUnderIt() {
    let processes = [
      AudioProcess(objectID: 1, pid: 10, bundleID: "com.apple.finder", isRunningOutput: false),
      AudioProcess(
        objectID: 2, pid: 11, bundleID: "com.oil3.QLC.QLC-quicklook", isRunningOutput: true),
      AudioProcess(objectID: 3, pid: 12, bundleID: "com.example.other", isRunningOutput: false),
    ]
    let apps = AppGrouping.apps(
      from: processes, name: { key, _ in key },
      host: { $0.pid == 11 ? "com.apple.finder" : nil })
    #expect(apps.map(\.key) == ["com.apple.finder", "com.example.other"])
    #expect(apps[0].processes.map(\.pid) == [10, 11])
    #expect(apps[0].isPlaying)
  }

  @Test func pinnedAppsAreListedBeforeTheyMakeASound() {
    let other = AudioProcess(objectID: 1, pid: 5, bundleID: "com.example.b", isRunningOutput: false)
    let apps = AppGrouping.apps(
      from: [other], name: { key, _ in key }, pinned: ["com.apple.finder": "Finder"])
    #expect(apps.map(\.name) == ["com.example.b", "Finder"])
    #expect(apps.first { $0.key == "com.apple.finder" }?.processes.isEmpty == true)
  }

  @Test(
    arguments: [
      ("QLC quicklook (Finder)", "Finder"),
      ("QuickLookUIService (Mail)", "Mail"),
      ("Google Chrome", nil),
      ("(Finder)", nil),
      ("Odd ()", nil),
    ] as [(String, String?)])
  func hostNameComesFromTheTrailingParentheses(display: String, expected: String?) {
    #expect(AppNames.hostName(fromDisplayName: display) == expected)
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
