import Testing

@testable import PatchbayTUI

private let chrome = AppRow(key: "com.google.Chrome", name: "Google Chrome", isPlaying: true)
private let finder = AppRow(key: "com.apple.finder", name: "Finder", isPlaying: false)
private let speakers = DeviceRow(uid: "spk", label: "MacBook Pro Speakers")
private let airpods = DeviceRow(uid: "pods", label: "AirPods")

private func panel(_ apps: [AppRow] = [chrome, finder]) -> TUIState {
  var state = TUIState()
  state.update(apps: apps, devices: [speakers, airpods])
  return state
}

@Suite struct TUIStateTests {
  @Test func pickASourceThenAnOutputMakesARoute() {
    var state = panel()
    #expect(state.pickSource(1) == nil)
    #expect(state.armed == "com.apple.finder")
    #expect(state.focus == .outputs)
    #expect(state.pickOutput(2) == .route(appKey: "com.apple.finder", deviceUID: "pods"))
    #expect(state.armed == nil)
    #expect(state.focus == .sources)
  }

  @Test func theKeyboardDoesTheSameThing() {
    var state = panel()
    #expect(state.handle(.down) == nil)
    #expect(state.handle(.enter) == nil)  // arms Finder
    #expect(state.handle(.down) == nil)  // normal output → speakers
    #expect(state.handle(.enter) == .route(appKey: "com.apple.finder", deviceUID: "spk"))
  }

  @Test func pickingTheNormalOutputDisconnectsARoutedApp() {
    let routed = AppRow(key: chrome.key, name: chrome.name, isPlaying: true, routedUID: "pods")
    var state = panel([routed, finder])
    _ = state.pickSource(0)
    #expect(state.outputIndex == 2)  // the cursor starts on where it plays now
    #expect(state.pickOutput(0) == .unroute(appKey: chrome.key))
  }

  @Test func repickingTheCurrentOutputOrNormalForAnUnroutedAppDoesNothing() {
    let routed = AppRow(key: chrome.key, name: chrome.name, isPlaying: true, routedUID: "pods")
    var state = panel([routed, finder])
    _ = state.pickSource(0)
    #expect(state.pickOutput(2) == nil)
    _ = state.pickSource(1)
    #expect(state.pickOutput(0) == nil)
  }

  @Test func anOutputWithNoSourcePickedAsksForOne() {
    var state = panel()
    #expect(state.pickOutput(1) == nil)
    #expect(state.status == "Pick a source on the left first.")
  }

  @Test func escapeCancelsAPick() {
    var state = panel()
    _ = state.pickSource(0)
    _ = state.handle(.escape)
    #expect(state.armed == nil)
    #expect(state.focus == .sources)
  }

  @Test func dDisconnectsTheSelectedSourceOnlyWhenRouted() {
    let routed = AppRow(key: chrome.key, name: chrome.name, isPlaying: true, routedUID: "spk")
    var state = panel([routed, finder])
    #expect(state.handle(.character("d")) == .unroute(appKey: chrome.key))
    _ = state.handle(.down)
    #expect(state.handle(.character("d")) == nil)
  }

  @Test func cursorsClampAtTheEnds() {
    var state = panel()
    _ = state.handle(.up)
    #expect(state.sourceIndex == 0)
    _ = state.handle(.down)
    _ = state.handle(.down)
    #expect(state.sourceIndex == 1)
  }

  @Test func refreshKeepsTheCursorOnTheSameAppAndDropsAVanishedPick() {
    var state = panel()
    _ = state.handle(.down)  // Finder
    state.update(
      apps: [AppRow(key: "x", name: "Xylo", isPlaying: true), chrome, finder], devices: [speakers])
    #expect(state.selectedApp?.key == finder.key)

    _ = state.pickSource(0)
    state.update(apps: [chrome, finder], devices: [speakers])
    #expect(state.armed == nil)
    #expect(state.focus == .sources)
  }

  @Test func quitAndShowAll() {
    var state = panel()
    #expect(state.handle(.character("a")) == .toggleAll)
    #expect(state.showAll)
    #expect(state.handle(.quit) == .quit)
  }
}
