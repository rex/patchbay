import Foundation
import Testing

@testable import PatchbayCore

private func scratchFile() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "patchbay-tests-\(UUID().uuidString)/nested/routes.json")
}

private let finderToHeadset = RouteMemory.Entry(
  app: "com.apple.finder", appName: "Finder", output: "headset-uid", outputName: "Ear Force One",
  volume: 70, muted: false)

@Suite struct RouteMemoryTests {
  @Test func savesAndLoadsAgainCreatingTheFolder() throws {
    let url = scratchFile()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent())
    }
    let memory = RouteMemory(routes: [finderToHeadset])
    try memory.save(to: url)
    #expect(RouteMemory.load(from: url) == memory)
  }

  @Test func aMissingOrBrokenFileMeansNoRoutes() throws {
    let url = scratchFile()
    #expect(RouteMemory.load(from: url).routes.isEmpty)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(RouteMemory.load(from: url).routes.isEmpty)
  }

  @Test @MainActor func aRouteBookRestoresWishesNamesAndVolumes() {
    let muted = RouteMemory.Entry(
      app: "com.google.Chrome", appName: "Google Chrome", output: "scarlett-uid",
      outputName: "Scarlett 2i2 USB", volume: 40, muted: true)
    let book = RouteBook()
    book.restore(RouteMemory(routes: [finderToHeadset, muted]))

    #expect(book.target(of: "com.apple.finder") == "headset-uid")
    #expect(book.isWaiting("com.apple.finder"))  // nothing goes live until reconcile
    #expect(
      book.routedApps == ["com.apple.finder": "Finder", "com.google.Chrome": "Google Chrome"])
    #expect(book.outputName(of: "com.google.Chrome") == "Scarlett 2i2 USB")
    #expect(book.volume(for: "com.google.Chrome").perMille == 400)
    #expect(book.volume(for: "com.google.Chrome").isMuted)
    #expect(
      book.remember() == RouteMemory(routes: [finderToHeadset, muted].sorted { $0.app < $1.app }))
  }

  @Test @MainActor func disconnectingForgetsTheRoute() {
    let book = RouteBook()
    book.restore(RouteMemory(routes: [finderToHeadset]))
    book.disconnect("com.apple.finder")
    #expect(book.remember().routes.isEmpty)
    #expect(book.routedApps.isEmpty)
  }

  @Test @MainActor func appsKnownOnlyByProcessIDAreNotRemembered() {
    let book = RouteBook()
    book.connect("pid:4242", to: "blackhole-uid")
    book.restore(RouteMemory(routes: [finderToHeadset]))
    #expect(book.remember().routes.map(\.app) == ["com.apple.finder"])
  }

  @Test @MainActor func anEntryWithoutAnAppOrOutputIsSkipped() {
    let book = RouteBook()
    var broken = finderToHeadset
    broken.output = ""
    book.restore(RouteMemory(routes: [broken]))
    #expect(book.routedApps.isEmpty)
  }
}
